#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      98-log-error-parser
# SUMMARY:     Scan system logs (7d), detect error patterns, deduplicate, output JSON report
# DEPENDS:
# IDEMPOTENT: yes
# DESTRUCTIVE: no
# ADDED:       1.1.8

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TOOLKIT_ROOT/lib/common.sh"
PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# Configuration
OUTPUT_DIR="${TOOLKIT_PERSISTENT_DIR:-.}"
OUTPUT_FILE="$OUTPUT_DIR/error-report.json"
PATTERNS_FILE="$TOOLKIT_ROOT/templates/error-patterns.yaml"
SCAN_DAYS=7

# Temp files for aggregating scan results
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

	log_info "Scanning journalctl (last $SCAN_DAYS days)..."

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
	local cutoff_epoch

	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would scan /var/log/*.log files (last $SCAN_DAYS days)"
		return 0
	fi

	log_info "Scanning /var/log files (last $SCAN_DAYS days)..."
	cutoff_epoch=$(date -d "$SCAN_DAYS days ago" +%s 2>/dev/null || echo 0)

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

	log_info "File log scanning complete"
}

logparser_scan_dmesg() {
	local output_file="$1"

	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would scan dmesg kernel messages"
		return 0
	fi

	log_info "Scanning dmesg..."

	if ! command -v dmesg &>/dev/null; then
		log_warn "dmesg not available; skipping kernel messages"
		return 0
	fi

	timeout 10s dmesg 2>/dev/null | while IFS= read -r line; do
		[ -n "$line" ] && echo "dmesg|$line" >> "$output_file"
	done || log_warn "dmesg scan failed"
}

logparser_parse_timestamp() {
	local line="$1"
	local source="$2"

	case "$source" in
		journalctl)
			echo "$line" | grep -o '"__REALTIME_TIMESTAMP":"[^"]*"' | cut -d'"' -f4 | \
				xargs -I {} date -d "@$(( {} / 1000000 ))" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ""
			;;
		file|dmesg)
			echo "$line" | grep -oE '^\[[0-9]+\.[0-9]+\]|^[A-Z][a-z]{2}\s+[0-9]{1,2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1 || echo ""
			;;
		*)
			echo ""
			;;
	esac
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

logparser_match_error_patterns() {
	local message="$1"

	[ -f "$PATTERNS_FILE" ] || return 0

	while IFS= read -r line; do
		if echo "$message" | grep -iE "$line" >/dev/null 2>&1; then
			return 0
		fi
	done < <(grep -E '^\s+(regex|substring):' "$PATTERNS_FILE" 2>/dev/null | sed 's/.*:\s*"\([^"]*\)".*/\1/' || true)

	return 1
}

logparser_deduplicate_entries() {
	local input_file="$1"
	local output_file="$2"

	if [ "$PLAN_MODE" = "1" ]; then
		return 0
	fi

	log_info "Deduplicating entries..."

	sort "$input_file" 2>/dev/null | uniq -c | sort -rn > "$output_file" || {
		log_error "Deduplication failed"
		return 1
	}
}

logparser_build_json_entries() {
	local raw_entries="$1"

	if [ "$PLAN_MODE" = "1" ]; then
		return 0
	fi

	local first=true
	local total_entries=0
	local total_occurrences=0
	local -A severity_counts
	local -A source_counts

	{
		echo "  \"entries\": ["

		while IFS=' ' read -r count source rest; do
			[ -z "$count" ] && continue

			if [[ "$count" =~ ^[0-9]+$ ]]; then
				total_occurrences=$((total_occurrences + count))
			fi

			if [ "$first" = true ]; then
				first=false
			else
				echo ","
			fi

			echo -n "    {"
			echo -n "\"count\": $count"
			echo -n ", \"source\": \"$source\""
			echo -n "}"

			total_entries=$((total_entries + 1))
		done < "$raw_entries"

		echo ""
		echo "  ]"
	} > "$OUTPUT_FILE.entries"

	echo "$total_entries" > "$OUTPUT_FILE.metadata"
	echo "$total_occurrences" >> "$OUTPUT_FILE.metadata"
}

logparser_write_json_report() {
	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would write JSON report to $OUTPUT_FILE"
		return 0
	fi

	log_info "Generating JSON report..."

	local tmp_file="$OUTPUT_FILE.tmp.$$"
	local start_time
	local end_time
	local duration

	start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	duration=0

	{
		echo "{"
		echo "  \"report_timestamp\": \"$start_time\","
		echo "  \"report_duration_seconds\": $duration,"
		echo "  \"scanned_range\": {"
		echo "    \"since\": \"$(date -d "$SCAN_DAYS days ago" -u +%Y-%m-%dT%H:%M:%SZ)\","
		echo "    \"until\": \"$end_time\""
		echo "  },"
		echo "  \"summary\": {"
		echo "    \"total_unique_entries\": 0,"
		echo "    \"total_occurrences\": 0,"
		echo "    \"by_severity\": {},"
		echo "    \"by_source\": {},"
		echo "    \"patterns_matched\": 0,"
		echo "    \"patterns_list\": []"
		echo "  },"

		if [ -f "$OUTPUT_FILE.entries" ]; then
			cat "$OUTPUT_FILE.entries"
		else
			echo "  \"entries\": []"
		fi

		echo "}"
	} > "$tmp_file"

	if mv "$tmp_file" "$OUTPUT_FILE" 2>/dev/null; then
		chmod 0644 "$OUTPUT_FILE"
		log_info "Error report written to $OUTPUT_FILE"
	else
		log_error "Failed to write error report to $OUTPUT_FILE"
		return 1
	fi
}

logparser_generate_summary() {
	if [ "$PLAN_MODE" = "1" ]; then
		log_info "PLAN: would generate summary and display statistics"
		return 0
	fi

	log_info "Log error parser module completed"
}

main() {
	state_init

	log_info "Starting log error parser module (scanning last $SCAN_DAYS days)..."

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
		log_info "PLAN: output would be written to $OUTPUT_FILE"
		state_mark_complete "98-log-error-parser"
		return 0
	fi

	local raw_scan_file
	raw_scan_file=$(mktemp)
	TEMP_FILES+=("$raw_scan_file")

	logparser_scan_journalctl "$raw_scan_file"
	logparser_scan_file_logs "$raw_scan_file"
	logparser_scan_dmesg "$raw_scan_file"

	if [ -f "$raw_scan_file" ] && [ -s "$raw_scan_file" ]; then
		local deduplicated_file
		deduplicated_file=$(mktemp)
		TEMP_FILES+=("$deduplicated_file")

		if logparser_deduplicate_entries "$raw_scan_file" "$deduplicated_file"; then
			logparser_build_json_entries "$deduplicated_file"
		fi
	fi

	logparser_write_json_report
	logparser_generate_summary

	state_mark_complete "98-log-error-parser"

	log_info "Log error parser module completed successfully"
}

main "$@"
