#!/bin/sh

set -e

/usr/bin/cryptkey-fetch | /sbin/cryptsetup luksOpen /dev/mmcblk0p2 cryptroot

/usr/bin/busybox mount /dev/mapper/cryptroot /mnt

/usr/bin/busybox mount /dev/mmcblk0p1 /mnt/boot/firmware

systemctl switch-root /mnt /usr/sbin/init
