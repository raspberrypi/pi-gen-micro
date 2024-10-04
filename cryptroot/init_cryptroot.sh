#!/bin/sh

set -e

/sbin/insmod /lib/modules/"$(uname -r)"/kernel/drivers/md/dm-mod.ko.xz
/sbin/insmod /lib/modules/"$(uname -r)"/kernel/drivers/md/dm-crypt.ko.xz
/sbin/insmod /lib/modules/"$(uname -r)"/kernel/crypto/af_alg.ko.xz
/sbin/insmod /lib/modules/"$(uname -r)"/kernel/crypto/algif_skcipher.ko.xz
/sbin/insmod /lib/modules/"$(uname -r)"/kernel/lib/crypto/libaes.ko.xz
/sbin/insmod /lib/modules/"$(uname -r)"/kernel/crypto/aes_generic.ko.xz
/sbin/insmod /lib/modules/"$(uname -r)"/kernel/arch/arm64/crypto/aes-arm64.ko.xz

/usr/bin/cryptkey-fetch | /sbin/cryptsetup luksOpen /dev/mmcblk0p2 cryptroot

/usr/bin/busybox mount /dev/mapper/cryptroot /mnt

/usr/bin/busybox mount /dev/mmcblk0p1 /mnt/boot/firmware

systemctl switch-root /mnt /usr/sbin/init
