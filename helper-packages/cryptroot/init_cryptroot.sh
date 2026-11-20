#!/bin/sh

set -e

# Device to unlock (partition)
CRYPT_DEVICE="${1:-/dev/mmcblk0p2}"

# Extract base device name (remove partition)
BASE_DEVICE="$CRYPT_DEVICE"
if echo "$BASE_DEVICE" | grep -q "mmcblk"; then
    # MMC: /dev/mmcblk0p2 -> /dev/mmcblk0
    BASE_DEVICE="$(echo "$CRYPT_DEVICE" | sed 's/p[0-9]*$//')"
elif echo "$BASE_DEVICE" | grep -q "nvme"; then
    # NVMe: /dev/nvme0n1p2 -> /dev/nvme0n1
    BASE_DEVICE="$(echo "$CRYPT_DEVICE" | sed 's/p[0-9]*$//')"
else
    # SATA/SCSI: /dev/sda2 -> /dev/sda
    BASE_DEVICE="$(echo "$CRYPT_DEVICE" | sed 's/[0-9]*$//')"
fi

# Ensure device-mapper is available before cryptsetup touches
# /dev/mapper/control. Opening the control node does not trigger the kernel's
# auto-load, so dm_mod must be loaded explicitly; modprobe dm-crypt pulls it in
# via the recorded dependency.
modprobe dm-crypt

# Devices from releases that wrote an ed25519 seed to OTP were formatted with
# the raw OTP key. rpifwcrypto HMACs that seed without complaint, so it yields
# a key that cannot open them: fall back on a failed unlock, not just no key.
try_unlock() {
    [ -n "$1" ] && printf '%s' "$1" | /sbin/cryptsetup luksOpen "$CRYPT_DEVICE" cryptroot
}

UNLOCKED=""
if command -v cryptkey-rpifwcrypto >/dev/null 2>&1; then
    KEY="$(/usr/bin/cryptkey-rpifwcrypto "$BASE_DEVICE" 2>/dev/null)" || KEY=""
    try_unlock "$KEY" && UNLOCKED=1
fi

if [ -z "$UNLOCKED" ] && command -v cryptkey-fetch >/dev/null 2>&1; then
    # cryptkey-fetch prints a key even when the OTP is blank, so honour its status
    KEY="$(/usr/bin/cryptkey-fetch 2>/dev/null)" || KEY=""
    try_unlock "$KEY" && UNLOCKED=1
fi
unset KEY

if [ -z "$UNLOCKED" ]; then
    echo "ERROR: Failed to unlock $CRYPT_DEVICE with keys from rpifwcrypto or OTP" >&2
    exit 1
fi

# Mount the decrypted root at the conventional initrd mountpoint. systemd's
# initrd-switch-root.service will pivot here once initrd-root-fs.target is
# reached; we deliberately do not call `systemctl switch-root` ourselves.
mkdir -p /sysroot
/usr/bin/busybox mount /dev/mapper/cryptroot /sysroot

# Mount the firmware/boot partition under the soon-to-be real root. This is
# the same partition the firmware loaded us from; the running OS expects it
# at /boot/firmware.
BOOT_PARTITION="$(echo "$CRYPT_DEVICE" | sed 's/[0-9]*$//')1"
mkdir -p /sysroot/boot/firmware
/usr/bin/busybox mount "$BOOT_PARTITION" /sysroot/boot/firmware
