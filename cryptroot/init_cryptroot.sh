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

# Try rpifwcrypto first (key slot 1), fall back to OTP if it fails
KEY=""
if command -v cryptkey-rpifwcrypto >/dev/null 2>&1; then
    # Try to get key from rpi-fw-crypto key slot 1
    KEY="$(/usr/bin/cryptkey-rpifwcrypto "$BASE_DEVICE" 2>/dev/null)" || true
fi

if [ -z "$KEY" ] && command -v cryptkey-fetch >/dev/null 2>&1; then
    # Fall back to OTP key (doesn't need device argument)
    KEY="$(/usr/bin/cryptkey-fetch 2>/dev/null)" || true
fi

if [ -z "$KEY" ]; then
    echo "ERROR: Failed to fetch cryptographic key from both rpifwcrypto and OTP" >&2
    exit 1
fi

# Unlock the LUKS container
printf '%s' "$KEY" | /sbin/cryptsetup luksOpen "$CRYPT_DEVICE" cryptroot

# Mount the root filesystem
/usr/bin/busybox mount /dev/mapper/cryptroot /mnt

# Mount boot partition (adjust partition number as needed)
BOOT_PARTITION="$(echo "$CRYPT_DEVICE" | sed 's/[0-9]*$//')1"
/usr/bin/busybox mount "$BOOT_PARTITION" /mnt/boot/firmware

# Pivot to the unlocked root
systemctl switch-root /mnt /usr/sbin/init
