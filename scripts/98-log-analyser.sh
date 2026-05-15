#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      98-log-analyser
# SUMMARY:     Scan system logs (7d), analyze patterns, deduplicate, output JSON report
# DEPENDS:
# IDEMPOTENT: yes
# DESTRUCTIVE: no
# ADDED:       1.1.8

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TOOLKIT_ROOT/lib/common.sh"
PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# SECURITY NOTE: This module scans system logs which may contain sensitive data
# including failed authentication attempts, API tokens, and SSL/TLS key material.
# The report file is restricted to root and syslog group (chmod 0640).
# Keep the error-report.json file secure and do not transmit over untrusted networks.

OUTPUT_DIR="${TOOLKIT_PERSISTENT_DIR:-.}"
OUTPUT_FILE="$OUTPUT_DIR/error-report.json"
PATTERNS_FILE="$TOOLKIT_ROOT/templates/error-patterns.yaml"
SCAN_DAYS=7

declare -a TEMP_FILES=()

logparser_cleanup() {
	for f in "${TEMP_FILES[@]}"; do
		[ -f "$f" ] && rm -f "$f"
	done
}
trap logparser_cleanup EXIT

logparser_init() {
	mkdir -p "$OUTPUT_DIR" || {
		log_error "Cannot create output directory: $OUTPUT_DIR"
		return 1
	}

	log_check_diskspace "$OUTPUT_DIR" 200 || {
		log_warn "Low disk space; error report may be truncated"
	}

	if [ ! -f "$PATTERNS_FILE" ]; then
		log_warn "Patterns file not found: $PATTERNS_FILE"
	fi
}

logparser_scan_journalctl() {
	local output_file="$1"

	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would scan journalctl (last $SCAN_DAYS days, all priorities)"
		return 0
	fi

	if ! command -v journalctl &>/dev/null; then
		log_warn "journalctl not available; skipping systemd logs"
		return 0
	fi

	timeout 30s journalctl --since "$SCAN_DAYS days ago" -p debug..emerg --no-pager -o json 2>/dev/null | \
		while IFS= read -r line; do
			if [ -n "$line" ]; then
				echo "journalctl|$line" >> "$output_file"
			fi
		done || log_warn "journalctl scan interrupted or failed"
}

logparser_scan_file_logs() {
	local output_file="$1"

	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would scan /var/log/*.log files (last $SCAN_DAYS days)"
		return 0
	fi

	find /var/log -maxdepth 2 -name "*.log" -type f 2>/dev/null | head -50 | while read -r logfile; do
		[ -r "$logfile" ] || continue

		if [[ "$logfile" =~ \.gz$ ]]; then
			timeout 10s zcat "$logfile" 2>/dev/null | tail -c 5M 2>/dev/null | while IFS= read -r line; do
				[ -n "$line" ] && echo "file|$logfile|$line" >> "$output_file"
			done || true
		else
			timeout 10s tail -c 5M "$logfile" 2>/dev/null | while IFS= read -r line; do
				[ -n "$line" ] && echo "file|$logfile|$line" >> "$output_file"
			done || true
		fi
	done
}

logparser_scan_dmesg() {
	local output_file="$1"

	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would scan dmesg kernel messages"
		return 0
	fi

	if ! command -v dmesg &>/dev/null; then
		log_warn "dmesg not available; skipping kernel messages"
		return 0
	fi

	timeout 10s dmesg 2>/dev/null | while IFS= read -r line; do
		[ -n "$line" ] && echo "dmesg|$line" >> "$output_file"
	done || log_warn "dmesg scan failed"
}

logparser_extract_severity() {
	local line="$1"

	if echo "$line" | grep -iE 'emerg|alert|crit|critical' >/dev/null 2>&1; then
		echo "CRITICAL"
	elif echo "$line" | grep -iE 'err|error|failed|failure' >/dev/null 2>&1; then
		echo "ERROR"
	elif echo "$line" | grep -iE 'warn|warning' >/dev/null 2>&1; then
		echo "WARNING"
	elif echo "$line" | grep -iE '"PRIORITY":[0-2]' >/dev/null 2>&1; then
		echo "CRITICAL"
	elif echo "$line" | grep -iE '"PRIORITY":[3]' >/dev/null 2>&1; then
		echo "ERROR"
	elif echo "$line" | grep -iE '"PRIORITY":[4]' >/dev/null 2>&1; then
		echo "WARNING"
	else
		echo "INFO"
	fi
}

logparser_extract_message() {
	local line="$1"
	local source="$2"

	case "$source" in
		journalctl)
			echo "$line" | grep -o '"MESSAGE":"[^"]*"' | cut -d'"' -f4 | head -c 500
			;;
		file|dmesg)
			echo "$line" | sed 's/^.*\]: //; s/^.*\s\[.*\]\s//' | head -c 500
			;;
		*)
			echo "$line" | head -c 500
			;;
	esac
}

logparser_load_patterns() {
	if [ ! -f "$PATTERNS_FILE" ]; then
		return 0
	fi

	grep -E '^\s+-\s+id:' "$PATTERNS_FILE" | sed 's/.*id:\s*"\([^"]*\)".*/\1/' || true
}

logparser_match_pattern() {
	local message="$1"
	local pattern_id="$2"

	[ -z "$pattern_id" ] && return 1
	[ ! -f "$PATTERNS_FILE" ] && return 1

	local pattern_regex
	pattern_regex=$(awk "/id:\s*\"$pattern_id\"/,/^[[:space:]]*$/ {
		if (/regex:/) print \$0
	}" "$PATTERNS_FILE" | grep -o '"[^"]*"' | head -1 | tr -d '"')

	if [ -n "$pattern_regex" ]; then
		echo "$message" | grep -iE "$pattern_regex" >/dev/null 2>&1 && {
			echo "$pattern_id"
			return 0
		}
	fi

	return 1
}

logparser_escape_json_string() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	s="${s//$'\n'/\\n}"
	s="${s//$'\r'/\\r}"
	s="${s//$'\t'/\\t}"
	s="${s//[[:cntrl:]]/}"
	echo "$s"
}

logparser_deduplicate_and_parse() {
	local raw_entries="$1"
	local entries_json="$2"
	local metadata_file="$3"

	if [ "$PLAN_MODE" = "1" ]; then
		return 0
	fi

	log_info "Processing log entries..."

	local -A entry_map
	local -A severity_counts
	local -A source_counts
	local total_entries=0
	local total_occurrences=0
	local patterns_matched=0

	while IFS='|' read -r source rest; do
		[ -z "$source" ] && continue

		local severity message msg_key pattern

		case "$source" in
			journalctl)
				severity=$(logparser_extract_severity "$rest")
				message=$(logparser_extract_message "$rest" "journalctl")
				;;
			file)
				local logfile
				IFS='|' read -r logfile msg_rest <<< "$rest"
				severity=$(logparser_extract_severity "$msg_rest")
				message=$(logparser_extract_message "$msg_rest" "file")
				source="$logfile"
				;;
			dmesg)
				severity=$(logparser_extract_severity "$rest")
				message=$(logparser_extract_message "$rest" "dmesg")
				;;
			*)
				continue
				;;
		esac

		[ -z "$message" ] && continue

		msg_key="$source|$severity|$message"

		if [ -z "${entry_map[$msg_key]:-}" ]; then
			entry_map["$msg_key"]=1
			total_entries=$((total_entries + 1))
		else
			entry_map["$msg_key"]=$((entry_map["$msg_key"] + 1))
		fi

		severity_counts["$severity"]=$((${severity_counts["$severity"]:-0} + 1))
		source_counts["$source"]=$((${source_counts["$source"]:-0} + 1))
		total_occurrences=$((total_occurrences + 1))
	done < "$raw_entries"

	echo "$total_entries" > "$metadata_file"
	echo "$total_occurrences" >> "$metadata_file"

	{
		for sev in CRITICAL ERROR WARNING INFO; do
			echo "${severity_counts[$sev]:-0}"
		done
	} >> "$metadata_file"

	{
		for src in "${!source_counts[@]}"; do
			echo "$src:${source_counts[$src]}"
		done
	} >> "$metadata_file"

	{
		local first=true
		for key in "${!entry_map[@]}"; do
			IFS='|' read -r source severity message <<< "$key"
			local count="${entry_map[$key]}"

			if [ "$first" = true ]; then
				first=false
			else
				echo ","
			fi

			local msg_escaped pattern
			msg_escaped=$(logparser_escape_json_string "$message")
			local src_escaped
			src_escaped=$(logparser_escape_json_string "$source")

			pattern="null"
			if logparser_match_pattern "$message" "apt-lock" >/dev/null 2>&1; then
				pattern="apt-lock"
			fi

			echo -n "    {"
			echo -n "\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
			echo -n ", \"source\": \"$src_escaped\""
			echo -n ", \"severity\": \"$severity\""
			echo -n ", \"message\": \"$msg_escaped\""
			echo -n ", \"occurrence_count\": $count"
			echo -n ", \"matched_pattern\": $pattern"
			echo -n ", \"suggested_fixes\": []"
			echo -n "}"
		done
	} > "$entries_json"
}

logparser_write_json_report() {
	local entries_json="$1"
	local metadata_file="$2"

	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would write JSON report to $OUTPUT_FILE"
		return 0
	fi

	log_info "Generating JSON report..."

	local tmp_file="$OUTPUT_FILE.tmp.$$"

	[ ! -f "$metadata_file" ] && {
		echo "0" > "$metadata_file"
		echo "0" >> "$metadata_file"
	}

	local total_unique total_occurrences crit_count err_count warn_count info_count
	{
		read total_unique
		read total_occurrences
		read crit_count
		read err_count
		read warn_count
		read info_count
	} < "$metadata_file"

	total_unique=${total_unique:-0}
	total_occurrences=${total_occurrences:-0}
	crit_count=${crit_count:-0}
	err_count=${err_count:-0}
	warn_count=${warn_count:-0}
	info_count=${info_count:-0}

	local start_time
	start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)

	{
		echo "{"
		echo "  \"report_timestamp\": \"$start_time\","
		echo "  \"report_duration_seconds\": 0,"
		echo "  \"scanned_range\": {"
		echo "    \"since\": \"$(date -d "$SCAN_DAYS days ago" -u +%Y-%m-%dT%H:%M:%SZ)\","
		echo "    \"until\": \"$start_time\""
		echo "  },"
		echo "  \"summary\": {"
		echo "    \"total_unique_entries\": $total_unique,"
		echo "    \"total_occurrences\": $total_occurrences,"
		echo "    \"by_severity\": {"
		echo "      \"CRITICAL\": $crit_count,"
		echo "      \"ERROR\": $err_count,"
		echo "      \"WARNING\": $warn_count,"
		echo "      \"INFO\": $info_count"
		echo "    },"
		echo "    \"by_source\": {},"
		echo "    \"patterns_matched\": 0,"
		echo "    \"patterns_list\": []"
		echo "  },"
		echo "  \"entries\": ["

		if [ -f "$entries_json" ]; then
			cat "$entries_json"
		fi

		echo ""
		echo "  ]"
		echo "}"
	} > "$tmp_file"

	if mv "$tmp_file" "$OUTPUT_FILE" 2>/dev/null; then
		chmod 0640 "$OUTPUT_FILE"
		log_info "Error report written to $OUTPUT_FILE"
	else
		log_error "Failed to write error report to $OUTPUT_FILE"
		return 1
	fi

	rm -f "$entries_json" "$metadata_file"
}

logparser_generate_summary() {
	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would generate summary and display statistics"
		return 0
	fi

	[ -f "$OUTPUT_FILE" ] && {
		log_info "Log analyser module completed"
	}
}

main() {
	state_init

	log_info "Starting log analyser module (scanning last $SCAN_DAYS days)..."

	if ! logparser_init; then
		log_error "Initialization failed"
		return 1
	fi

	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN MODE: Log scanning would begin now"
		log_info "PLAN: sources to scan:"
		log_info "  - journalctl (systemd logs)"
		log_info "  - /var/log files"
		log_info "  - dmesg (kernel messages)"
		log_info "PLAN: deduplication enabled"
		log_info "PLAN: output will be written to $OUTPUT_FILE"
		state_mark_complete "98-log-analyser"
		return 0
	fi

	local raw_scan_file
	raw_scan_file=$(mktemp)
	TEMP_FILES+=("$raw_scan_file")

	logparser_scan_journalctl "$raw_scan_file"
	logparser_scan_file_logs "$raw_scan_file"
	logparser_scan_dmesg "$raw_scan_file"

	local entries_json
	local metadata_file
	entries_json=$(mktemp)
	metadata_file=$(mktemp)
	TEMP_FILES+=("$entries_json" "$metadata_file")

	if [ -f "$raw_scan_file" ] && [ -s "$raw_scan_file" ]; then
		logparser_deduplicate_and_parse "$raw_scan_file" "$entries_json" "$metadata_file"
	else
		log_warn "No log entries found to process"
		echo "0" > "$metadata_file"
		echo "0" >> "$metadata_file"
	fi

	logparser_write_json_report "$entries_json" "$metadata_file"

	logparser_generate_summary
	state_mark_complete "98-log-analyser"

	log_info "Log analyser module completed successfully"
}

main "$@"
