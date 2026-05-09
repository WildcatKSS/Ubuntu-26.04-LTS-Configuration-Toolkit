# Ubuntu 24.04 LTS Configuration Toolkit

A modular bash toolkit that takes a freshly installed Ubuntu 24.04 LTS system
and configures it from bare to production-ready in one run: partitions, network,
hardening, monitoring, mail relay and alerting.

The toolkit is **idempotent** (safe to re-run), **resumable** (state survives
reboot after script 02), and supports both **interactive** and **unattended**
modes.

---

## Quickstart

```bash
git clone <this-repo> ubuntu-toolkit
cd ubuntu-toolkit
cp config/defaults.conf.example config/defaults.conf
$EDITOR config/defaults.conf

sudo ./main.sh --list      # show modules and dependency graph
sudo ./main.sh --plan      # read-only audit (no changes)
sudo ./main.sh --dry-run   # bash -n syntax check
sudo ./main.sh             # actual run
```

---

## Configuration

All variables live in `config/defaults.conf` (gitignored — copy from
`config/defaults.conf.example`). The most important fields:

| Variable | Description |
|---|---|
| `NETWORK_INTERFACE` | Interface to configure (e.g. `ens3`) |
| `USE_DHCP` | `true` for DHCP, `false` for static IP |
| `IP_ADDRESS`, `PREFIX_LENGTH`, `GATEWAY`, `DNS_SERVERS` | Static IP fields |
| `HOSTNAME` | FQDN for the host |
| `TIMEZONE`, `LOCALE` | Locale settings |
| `NTP_SERVERS`, `FALLBACK_NTP` | chrony servers |
| `DISK_DEVICE` | Target disk for LVM creation (e.g. `/dev/sda`) |
| `EMAIL_TO`, `SMTP_RELAY_HOST`, `SMTP_RELAY_PORT` | Mail relay |
| `DISK_ALERT_THRESHOLD` | Disk-usage % that triggers an alert |

The following values are **never stored in config files** — they are prompted
interactively (or supplied via env var for unattended runs):

| Env var | Used by | Effect |
|---|---|---|
| `ADMIN_USER`, `ADMIN_PASSWORD` | `01-base-config` | Create sudo user without prompting |
| `SWAP_ENCRYPT` (`true`/`false`) | `02-partitions` | Skip the encryption prompt |
| `SKIP_PARTITIONS=true` | `02-partitions` | Skip partition creation entirely |
| `TOOLKIT_NONINTERACTIVE=1` | All | Use defaults for any interactive prompt |

---

## Flags

```
Inspection / preview:
  --list                Print discovered modules with metadata and exit.
  --plan                Read-only audit: modules report what they would change.
  --dry-run             Run scripts with bash -n (syntax check, no execution).

Execution control:
  --resume              Skip modules already recorded as complete.
  --force               Re-run all modules, even completed ones.
  --retry=<module>      Re-run a single previously-failed module.
  --only=<module>       Run only this module (and its prerequisites).
  --skip=<m1,m2,...>    Skip these modules (comma-separated short names).
  --ignore-errors       Continue when a non-critical module exits non-zero.
  -h, --help            Show this help and exit.
```

### Flag conflict resolution

| Combination | Behaviour |
|---|---|
| `--force` + `--resume` | `--force` wins (re-run all) |
| `--plan` + others | `--plan` wins (no changes) |
| `--only` + `--skip` | `--skip` removes from the filtered set |
| `--list` + others | `--list` only (print and exit) |

---

## Modules

Modules live in `scripts/` and are auto-discovered alphabetically. Each module
declares its metadata in a header:

```bash
# MODULE: 07-hardening
# DESC:   Kernel sysctl hardening, AppArmor verification, auditd setup
# DEPENDS: 06-packages
# IDEMPOTENT: yes
# DESTRUCTIVE: no
```

| # | Script | What it does |
|---|---|---|
| 00 | `00-preflight.sh` | OS=Ubuntu 24.04, internet, disk space, apt locks |
| 01 | `01-base-config.sh` | apt upgrade, sudo user, unattended-upgrades |
| 02 | `02-partitions.sh` | LVM `vg0` with hardened mount options (`nodev,nosuid,noexec`) |
| 03 | `03-ip-config.sh` | Hostname, Netplan, connectivity check + auto-restore |
| 04 | `04-network-hardening.sh` | cloud-init off, NetworkManager off, UFW (SSH-only), IPv6 off, fail2ban |
| 05 | `05-system-settings.sh` | Timezone, locale, chrony (replaces systemd-timesyncd) |
| 06 | `06-packages.sh` | Encrypted swap (if chosen) + standard tools |
| 07 | `07-hardening.sh` | sysctl, AppArmor verify, auditd rules |
| 08 | `08-monitoring.sh` | sysstat, rsyslog rules, logrotate |
| 09 | `09-mail-alerting.sh` | Postfix relay, daily report cron, disk/service alert cron |
| 99 | `99-cleanup.sh` | apt autoremove + clean, service verification, banner |

### Adding your own module

Drop `scripts/50-mycompany.sh` with a metadata header — it is picked up
automatically. See `CONTRIBUTING.md` for naming conventions and how to register
dependencies.

### Hooks

Optional `scripts/hooks/pre-<module>.sh` and `scripts/hooks/post-<module>.sh`
files run before/after the matching module. Hook failures are logged but never
stop the run.

---

## State and logging

The toolkit writes a state file recording which modules completed.
Its location moves once the `/var/log` LVM partition is mounted:

| Phase | State file | Survives reboot? |
|---|---|---|
| Scripts 0 → 2 (before mount) | `/tmp/toolkit-setup/.state` | no |
| After script 02 (`mount -a`) | `/var/log/toolkit-setup/.state` | yes |

Log file:

| Phase | Log file |
|---|---|
| During execution | `/tmp/toolkit-setup/toolkit-setup.log` |
| After script 07 | `/var/log/toolkit-setup.log` (consolidated) |

If a previous run failed before script 02 and the system rebooted, `--resume`
will warn that the temp state was lost — re-run with `--force` to start over.

---

## Unattended mode

```bash
ADMIN_USER=sysadmin \
ADMIN_PASSWORD='change-me-please' \
SWAP_ENCRYPT=true \
TOOLKIT_NONINTERACTIVE=1 \
sudo -E ./main.sh
```

For partition creation in unattended mode, set `SKIP_PARTITIONS=true` if the
disk is already partitioned by your installer. The toolkit refuses to silently
overwrite partitions.

Recommended secure pattern (avoids passwords in shell history):

```bash
chmod 600 .env
set -a; source .env; set +a
sudo -E ./main.sh
```

---

## Troubleshooting / quick recovery

| Symptom | Fix |
|---|---|
| Network broken after `03-ip-config` | `cp -a /etc/netplan.backup/. /etc/netplan/ && netplan apply` |
| One module failed | `sudo ./main.sh --retry=<module-name>` |
| Reboot mid-run, state lost (in `/tmp`) | `sudo ./main.sh --force` |
| Reboot mid-run, state preserved (in `/var/log`) | `sudo ./main.sh --resume` |
| `--list` shows wrong dependency | Inspect the `# DEPENDS:` header in the module |

Inspect the log for ERROR lines:
```bash
grep ERROR /var/log/toolkit-setup.log /tmp/toolkit-setup/toolkit-setup.log 2>/dev/null
```

---

## Testing

The repository ships with BATS unit tests and a GitHub Actions workflow
(`.github/workflows/ci.yml`) that runs `bash -n`, `shellcheck` and `bats` on
every push.

```bash
bash -n scripts/*.sh lib/*.sh main.sh
shellcheck -x -e SC1091,SC2034 scripts/*.sh lib/*.sh main.sh
bats tests/
```

End-to-end testing must happen on a real (or virtual) Ubuntu 24.04 host —
see the verification steps in the project plan for the full procedure.

---

## License

See repository LICENSE file.
