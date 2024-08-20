#!/bin/sh

/sbin/insmod /lib/modules/$(uname -r)/kernel/drivers/md/dm-mod.ko.xz
/sbin/insmod /lib/modules/$(uname -r)/kernel/drivers/md/dm-crypt.ko.xz
/sbin/insmod /lib/modules/$(uname -r)/kernel/crypto/af_alg.ko.xz
/sbin/insmod /lib/modules/$(uname -r)/kernel/crypto/algif_skcipher.ko.xz
/sbin/insmod /lib/modules/$(uname -r)/kernel/lib/crypto/libaes.ko.xz
/sbin/insmod /lib/modules/$(uname -r)/kernel/crypto/aes_generic.ko.xz
/sbin/insmod /lib/modules/$(uname -r)/kernel/arch/arm64/crypto/aes-arm64.ko.xz

PRIVATE_KEY=$(/usr/local/bin/rpi-otp-private-key -b | base64 -w0)
echo -n $PRIVATE_KEY > /data/fastboot.key
printf "${PRIVATE_KEY}\r\n" >> /data/private.key

/usr/bin/cryptkey-fetch | /sbin/cryptsetup luksOpen --key-file=/data/fastboot.key /dev/mmcblk0p2 cryptroot

/bin/busybox mount /dev/mapper/cryptroot /mnt

/bin/busybox mount /dev/mmcblk0p1 /mnt/boot/firmware

systemctl switch-root /mnt /usr/sbin/init
