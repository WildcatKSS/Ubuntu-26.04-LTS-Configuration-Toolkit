#!/usr/bin/env bash
# MODULE: 02-partitions
# DESC: LVM detection and (with confirmation) creation of vg0 with hardened LVs
# DEPENDS: 01-base-config
# IDEMPOTENT: yes
# DESTRUCTIVE: yes

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# Expected logical volumes (name:size)
EXPECTED_LVS=(
    "lv_root:25G"
    "lv_swap:4G"
    "lv_home:5G"
    "lv_tmp:5G"
    "lv_var:25G"
    "lv_var_tmp:3G"
    "lv_var_log:10G"
    "lv_var_log_audit:5G"
)

# --- Phase 1: detect ---
log_info "Inspecting current disk layout"
if command -v lsblk >/dev/null 2>&1; then
    lsblk -e7 | sed 's/^/  /'
fi

if command -v vgs >/dev/null 2>&1 && vgs vg0 >/dev/null 2>&1; then
    log_info "Volume group vg0 already present — verifying expected LVs"
    missing_lv=()
    for entry in "${EXPECTED_LVS[@]}"; do
        lv="${entry%%:*}"
        if ! lvs "vg0/$lv" >/dev/null 2>&1; then
            missing_lv+=("$lv")
        fi
    done
    if [ "${#missing_lv[@]}" -gt 0 ]; then
        log_error "vg0 exists but is incomplete (missing LVs: ${missing_lv[*]})"
        log_error "Manual recovery required — refusing to auto-fix a partial layout"
        exit 1
    fi
    log_info "vg0 layout verified — skipping creation"
    log_info "Partitions module complete (no changes)"
    exit 0
fi

# --- Phase 2: confirm + create ---
if [ "${SKIP_PARTITIONS:-false}" = "true" ]; then
    log_info "SKIP_PARTITIONS=true — skipping partition creation"
    exit 0
fi

if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would prompt to create LVM vg0 on $DISK_DEVICE with 8 LVs"
    exit 0
fi

if [ ! -b "$DISK_DEVICE" ]; then
    log_error "DISK_DEVICE is not a block device: $DISK_DEVICE"
    exit 1
fi

# Size validation: need ~95 GB
disk_bytes="$(blockdev --getsize64 "$DISK_DEVICE")"
required_bytes=$(( 95 * 1024 * 1024 * 1024 ))
if [ "$disk_bytes" -lt "$required_bytes" ]; then
    log_error "Disk $DISK_DEVICE is too small: $((disk_bytes / 1024 / 1024))MB (need ~95GB)"
    exit 1
fi

if ! system_confirm "Create LVM vg0 on $DISK_DEVICE? This will ERASE ALL DATA. Continue?" no; then
    log_info "User declined partition creation — skipping"
    exit 0
fi

# Encrypted swap choice (single decision point — flag stored for script 06)
swap_flag="$TOOLKIT_TEMP_DIR/.swap_encrypted"
if [ -n "${SWAP_ENCRYPT:-}" ]; then
    case "$SWAP_ENCRYPT" in
        true|yes|1) echo "yes" > "$swap_flag"; log_info "Swap encryption: yes (env)" ;;
        *)          rm -f "$swap_flag"; log_info "Swap encryption: no (env)" ;;
    esac
elif system_confirm "Encrypt swap?" yes; then
    echo "yes" > "$swap_flag"
    log_info "Swap encryption: yes — will be configured in script 06 (cryptsetup)"
else
    rm -f "$swap_flag"
    log_info "Swap encryption: no"
fi

pkg_install lvm2 parted dosfstools e2fsprogs

log_info "Partitioning $DISK_DEVICE (GPT, EFI + /boot + LVM)"
parted -s "$DISK_DEVICE" mklabel gpt
parted -s "$DISK_DEVICE" mkpart EFI fat32 1MiB 513MiB
parted -s "$DISK_DEVICE" set 1 esp on
parted -s "$DISK_DEVICE" mkpart BOOT ext4 513MiB 1537MiB
parted -s "$DISK_DEVICE" mkpart LVM 1537MiB 100%
parted -s "$DISK_DEVICE" set 3 lvm on

partprobe "$DISK_DEVICE"
sleep 2

# Determine partition naming (e.g. /dev/sda1 vs /dev/nvme0n1p1)
case "$DISK_DEVICE" in
    *[0-9]) PART_PREFIX="${DISK_DEVICE}p" ;;
    *)      PART_PREFIX="${DISK_DEVICE}"  ;;
esac

EFI_PART="${PART_PREFIX}1"
BOOT_PART="${PART_PREFIX}2"
LVM_PART="${PART_PREFIX}3"

mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$BOOT_PART"

log_info "Creating LVM PV/VG/LVs"
pvcreate -ff -y "$LVM_PART"
vgcreate vg0 "$LVM_PART"

for entry in "${EXPECTED_LVS[@]}"; do
    lv="${entry%%:*}"
    size="${entry##*:}"
    lvcreate -L "$size" -n "$lv" vg0
done

# Format LVs
mkfs.ext4 -F /dev/vg0/lv_root
mkfs.ext4 -F /dev/vg0/lv_home
mkfs.ext4 -F /dev/vg0/lv_tmp
mkfs.ext4 -F /dev/vg0/lv_var
mkfs.ext4 -F /dev/vg0/lv_var_tmp
mkfs.ext4 -F /dev/vg0/lv_var_log
mkfs.ext4 -F /dev/vg0/lv_var_log_audit
mkswap /dev/vg0/lv_swap

log_info "Updating /etc/fstab"
fstab_backup="/etc/fstab.toolkit-$(date +%s).bak"
cp /etc/fstab "$fstab_backup"
log_info "fstab backup: $fstab_backup"

# fstab entries (UUIDs would be more robust; using device paths for clarity)
cat >>/etc/fstab <<EOF
# --- toolkit additions ---
$EFI_PART                    /boot/efi      vfat   defaults                       0 2
$BOOT_PART                   /boot          ext4   defaults                       0 2
/dev/vg0/lv_root             /              ext4   defaults                       0 1
/dev/vg0/lv_home             /home          ext4   defaults,nodev,nosuid          0 2
/dev/vg0/lv_tmp              /tmp           ext4   defaults,nodev,nosuid,noexec   0 2
/dev/vg0/lv_var              /var           ext4   defaults,nodev,nosuid          0 2
/dev/vg0/lv_var_tmp          /var/tmp       ext4   defaults,nodev,nosuid,noexec   0 2
/dev/vg0/lv_var_log          /var/log       ext4   defaults,nodev,nosuid,noexec   0 2
/dev/vg0/lv_var_log_audit    /var/log/audit ext4   defaults,nodev,nosuid,noexec   0 2
/dev/vg0/lv_swap             none           swap   sw                             0 0
EOF

# vm.swappiness
cat >/etc/sysctl.d/99-swappiness.conf <<'EOF'
vm.swappiness = 1
EOF
sysctl -p /etc/sysctl.d/99-swappiness.conf >/dev/null

mkdir -p /boot/efi /home /tmp /var /var/tmp /var/log /var/log/audit
mount -a
swapon /dev/vg0/lv_swap || log_warn "swapon failed (will retry after encryption in script 06)"

log_info "Partitions complete — vg0 created with all LVs and mounted"
