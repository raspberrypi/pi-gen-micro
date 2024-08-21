#!/usr/bin/env bash

# Set up some parameters for building!
KERNEL_VERSION_STR="6.6.31+rpt-rpi-v8"
KERNEL_BIT_SIZE=64
OUT_IMAGE_NAME="boot.img"

# Overwrite the defaults with that from the build.parameters file
source config

CONFIGURATION_FOLDER="${CONFIGURATION_ROOT}"$1

export OUT_DIR=$PWD/out_image
source ${CONFIGURATION_FOLDER}/build.parameters
source ${CONFIGURATION_FOLDER}/components.parameters

echo ${CONFIGURATION_FOLDER}
echo ${TARGET_DEVICE}

rm -rf build
rm initramfs
rm -rf $OUT_DIR
mkdir -p build
mkdir $OUT_DIR

export OUT_DIR=$PWD/out_image
rm -rf build
rm -f initramfs
rm -rf $OUT_DIR
mkdir -p build
mkdir $OUT_DIR

mkdir -p build/usr/bin
mkdir -p build/usr/lib
cd build
ln -s usr/bin bin
ln -s usr/lib lib
cd ..
export ROOTFS_DIR=$PWD/build
export DPKG_ROOT=$ROOTFS_DIR
export TOP="${PWD}"

sed "s%PWD%${PWD}%" cfg/apt.cfg > apt.cfg
sed --in-place "s%REALROOTREL%$(realpath -s --relative-to=$PWD /)/%" apt.cfg
export APT_CONFIG=$PWD/apt.cfg
# export DPKG_EXTRA_ARGS="--instdir=${DPKG_ROOT}"

KERNEL_VERSION_STR="6.6.31+rpt-rpi-v8"

apt_download() {
  apt-get install --download-only $@
}

# Can't use install until it's possible to chroot
apt_install() {
  apt-get install $@ --no-install-recommends
}

get_package_path() {
  # Not fully URL-encoded (no spec found)
  PKG_VERSION=$(apt-cache policy "$1" | grep -oP 'Candidate: \K.*' | sed 's/:/%3a/')
  echo "$(find apt/cache/archives/ -name ${1}_${PKG_VERSION}*)"
}

dpkg_unpack() {
  apt_download $1
  dpkg ${DPKG_EXTRA_ARGS} --no-triggers --unpack $(get_package_path $1)
}

dpkg_install() {
  apt_download $1
  dpkg ${DPKG_EXTRA_ARGS} --install $(get_package_path $1)
}

apt-get update
mkdir -p build/var/lib/dpkg
touch build/var/lib/dpkg/lock-frontend

# Download, patch, install libc6-udeb
apt_download libc6-udeb
PACKAGE_PATH="$(get_package_path libc6-udeb)"
EXTRACT_DIR="$(mktemp --directory --tmpdir deb-extract.XXX)"
dpkg-deb --raw-extract "${PACKAGE_PATH}" "${EXTRACT_DIR}"
rm "${PACKAGE_PATH}"
LIBC_VERSION="$(grep -oP '^Version:\s*\K.*' ${EXTRACT_DIR}/DEBIAN/control)"
sed --in-place "/^Provides:/s/libc6,/libc6 (= ${LIBC_VERSION}),/" "${EXTRACT_DIR}/DEBIAN/control"
echo "Replaces: libc6 (= ${LIBC_VERSION})
Conflicts: libc6 (= ${LIBC_VERSION})" >> "${EXTRACT_DIR}/DEBIAN/control"
dpkg-deb --build "${EXTRACT_DIR}" "${PACKAGE_PATH}"
rm -rf "${EXTRACT_DIR}"
dpkg ${DPKG_EXTRA_ARGS} --install "${PACKAGE_PATH}"

dpkg_install busybox

pushd build
cd bin
ln -s busybox sh
ln -s mawk awk
echo '#!/bin/sh' > update-alternatives
echo 'return 0' >> update-alternatives
chmod +x update-alternatives
cp update-alternatives dpkg-trigger
popd

# awk is Pre-Depends of base-files (unfortunately)
dpkg_install mawk

# Just unpack base-files for now (can't postinst without base-passwd)
dpkg_unpack base-files

chroot build /bin/busybox --install -s

# Need to properly install base-passwd before base-files can be completed
apt_download libpcre2-8-0 libselinux1 libdebconfclient0 base-passwd
dpkg_install libpcre2-8-0
dpkg_install libselinux1
dpkg_install libdebconfclient0
dpkg_install base-passwd

# Allow root login without password (and use busybox shell)
sed --in-place '/^root/ {s/\*//; s/bash/sh/}' build/etc/passwd

dpkg_install base-files

# Manually move the dpkg excludes file into the rootfs
cp cfg/dpkg.cfg.d/excludes /etc/dpkg/dpkg.cfg.d/excludes

# Manually move the dpkg excludes file into the rootfs
cp cfg/dpkg.cfg.d/excludes /etc/dpkg/dpkg.cfg.d/excludes

# 'mount' will be installed by systemd below, ensure util-linux dep can be met
dpkg_unpack util-linux-extra
rm -rf build/etc/init.d
apt-get --fix-broken install
# We *should* now have a working system for apt.
# Try to install cryptsetup-bin (+deps) (libgcc-s1 required for pthread_exit)
apt_install cryptsetup-bin libgcc-s1
apt_install android-libsparse
apt_install android-libbase
apt_install android-liblog
apt_install zlib1g
apt_install android-libcutils
apt_install libfdisk1
apt_install liburing2
apt_install openssl

# Tiny debconf for libpam0g (systemd dep)
apt_install cdebconf-udeb cdebconf-text-udeb
sed --in-place 's/newt/text/g' build/etc/cdebconf.conf
if [ ${SSH} = 1 ]
then
  echo "Installing SSH!"
  apt_install dropbear-bin
fi

# TODO: postinst failure, fstrim settings using deb-systemd-helper
apt_install util-linux

# Install systemd and symlinks
cp build/bin/update-alternatives build/bin/dpkg-maintscript-helper
cp build/bin/update-alternatives build/bin/dpkg
apt_install systemd-sysv
rm build/bin/dpkg-maintscript-helper
rm build/bin/dpkg

IFS=', ' read -r -a array <<< "$(cat ${CONFIGURATION_FOLDER}/packages.list | tr '\n' ', ')"
echo ${array}

for package in "${array[@]}"
do
   echo "Installing $package"
   #dpkg ${DPKG_EXTRA_ARGS} --install $package
   apt_install $package
done

pushd ${CONFIGURATION_FOLDER}
./installer_scripts.list
popd

apt_install kmod

if [ ${UDEV} = 1 ]
then
  echo "Installing UDEV!"
  # libc-bin required for passwd postinst
  apt_install libc-bin

  # Setup passwd (udev dep)
  cp build/bin/update-alternatives build/bin/dpkg-maintscript-helper
  apt_install passwd
  rm build/bin/dpkg-maintscript-helper

  # Install perl-base, addgroup dep (used by udev postinst)
  apt_install perl-base

  # Setup udev
  dpkg_unpack udev
  rm -rf build/etc/init.d
  apt-get --fix-broken install
fi

if [ ${NETWORK} = 1 ]
then
  if [ ${UDEV} = 1 ]
  then
    echo "Installing & Enabling networking"
    cp prebuilts/20-wired.network build/etc/systemd/network/20-wired.network
    ln -s /lib/systemd/system/systemd-networkd.service build/etc/systemd/system/dbus-org.freedesktop.network1.service
    ln -s /lib/systemd/system/systemd-networkd.service build/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
    ln -s /lib/systemd/system/systemd-networkd.socket build/systemd/system/sockets.target.wants/systemd-networkd.socket
    ln -s /lib/systemd/system/systemd-network-generator.service build/etc/systemd/system/sysinit.target.wants/systemd-network-generator.service
    ln -s /lib/systemd/system/systemd-networkd-wait-online.service build/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
  else
    echo "--------------- ERROR - Network cannot be installed without UDEV Support. This component will not work! --------------------"
  fi
fi


# Symlink to regular /sbin/init
# ln -s /sbin/init build/init

if [ ${AUTOLOGIN} = 1 ]
then
  # Ensure getty on tty1 is autologin
  mkdir -p build/etc/systemd/system/getty@tty1.service.d
  echo "[Service]
  ExecStart=
  ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin root %I \$TERM
  TTYVTDisallocate=no
  " > build/etc/systemd/system/getty@tty1.service.d/autologin.conf

  # getty-static.service starts tty2-tty6 if dbus / logind are not available
  # Override this behaviour
  mkdir -p build/etc/systemd/system/getty-static.service.d
  echo "[Service]
  ExecStart=
  ExecStart=/bin/true
  " > build/etc/systemd/system/getty-static.service.d/override.conf

  # serial-getty shouldn't wait for device unit (no udev) and should autologin as
  # root
  sed '
  /^BindsTo/d
  /^After=/s/dev-%i\.device\s*//
  s/\(--keep-baud\)/--noclear --autologin root \1/' \
    build/usr/lib/systemd/system/serial-getty@.service \
    > build/etc/systemd/system/serial-getty@.service
fi
# Ensure compressed modules can be loaded (busybox implementation of modprobe
# is insufficient)
dpkg_unpack kmod
rm -rf build/etc/init.d
apt-get --fix-broken install

### CUSTOM CHANGES ARE MADE HERE
#
### CUSTOM CHANGES ARE MADE HERE

# Boot firmare

apt_download raspi-firmware
RASPI_FIRMWARE_TMPDIR=$(mktemp -d)
cd "${RASPI_FIRMWARE_TMPDIR}"
ar -x $(find ${TOP}/apt/cache/archives/ -name raspi-firmware* | sort | tail -1)
tar xvf data.tar.xz ./
mv ./usr/lib/raspi-firmware/* ${DPKG_ROOT}/boot/
cd -
rm -rf "${RASPI_FIRMWARE_TMPDIR}"

# Find kernel
KERNEL_META=linux-image-rpi-v8
apt_download $KERNEL
KERNEL_PACKAGE=$(apt-cache depends $KERNEL_META | grep -oP 'Depends: \K.*')
KERNEL_VERSION_STR=${KERNEL_PACKAGE#linux-image-}

# TODO: This leaves apt in a broken state, see what we can do here.
dpkg_unpack ${KERNEL_PACKAGE}

# Manually form-up the kernel and bootfs
mkdir -p ${OUT_DIR}/overlays
# mv ${DPKG_ROOT}/boot/vmlinuz-${KERNEL_VERSION_STR} ${OUT_DIR}/zImage
mv ${DPKG_ROOT}/usr/lib/linux-image-${KERNEL_VERSION_STR}/broadcom/*.dtb ${OUT_DIR}/
mv ${DPKG_ROOT}/usr/lib/linux-image-${KERNEL_VERSION_STR}/overlays/*.dtb* ${OUT_DIR}/overlays/
mv ${DPKG_ROOT}/usr/lib/linux-image-${KERNEL_VERSION_STR}/overlays/README ${OUT_DIR}/overlays/
mv ${DPKG_ROOT}/boot/* ${OUT_DIR}/

mkdir build/data/
cp prebuilts/config.txt ${OUT_DIR}/config.txt
cp prebuilts/cmdline.txt ${OUT_DIR}/cmdline.txt
# apt_install debconf

dpkg_unpack linux-image-${KERNEL_VERSION_STR}

# # Manually form-up the kernel and bootfs
# mkdir -p ${OUT_DIR}/overlays
mv ${DPKG_ROOT}/boot/vmlinuz-${KERNEL_VERSION_STR} ${OUT_DIR}/kernel8.img
# mv ${DPKG_ROOT}/usr/lib/linux-image-${KERNEL_VERSION_STR}/broadcom/*.dtb ${OUT_DIR}/
# mv ${DPKG_ROOT}/usr/lib/linux-image-${KERNEL_VERSION_STR}/overlays/*.dtb* ${OUT_DIR}/overlays/
# mv ${DPKG_ROOT}/usr/lib/linux-image-${KERNEL_VERSION_STR}/overlays/README ${OUT_DIR}/overlays/
# mv ${DPKG_ROOT}/boot/* ${OUT_DIR}/
# # Install Systemd by building into build folder
# /mnt/install_systemd.sh

#cd components
#./install_package.sh https://github.com/systemd/systemd.git
#cd ..

cp -r packages/built/* build/
cp -r packages/built/lib/* build/usr/lib/
cp -r packages/built/bin/* build/usr/bin/
# Copy init
cp prebuilts/init build/init
# ln build/usr/sbin /sbin
cd build/sbin
rm init

ln -s /usr/lib/systemd/systemd init
cd ..
ln -s /bin/udevadm /lib/systemd/systemd-udevd
cd ..

mkdir build/data/
cp prebuilts/config.txt ${OUT_DIR}/config.txt
cp prebuilts/cmdline.txt ${OUT_DIR}/cmdline.txt
cp prebuilts/cryptkey-fetch build/bin/
cp prebuilts/vcmailbox build/bin/
cp prebuilts/vcgencmd build/bin/
mkdir build/usr/local/bin
cp prebuilts/rpi-otp-private-key build/usr/local/bin

mkdir build/usr/share/udhcpc/
cp prebuilts/network.script build/usr/share/udhcpc/network.script




# Copy staged modules
# pushd /mnt/src/debian/systemd-252.26/
# sudo ./build_and_copy.sh
# popd

# cp -r staged_build/* build

# Copy modules.dep
# cp -r prebuilts/lib/. build/lib/
# cp -r prebuilts/usr build/
# cp -r prebuilts/etc/* build/etc/

# rm build/usr/lib/systemd/system/systemd-firstboot.service
# rm build/usr/lib/systemd/system/sysinit.target.wants/systemd-firstboot.service
# cp prebuilts/getty@.service build/usr/lib/systemd/system/getty@.service
# cp prebuilts/serial-getty@.service build/usr/lib/systemd/system/serial-getty@.service
# cp prebuilts/serial-getty@.service build/etc/systemd/system/serial-getty@.service
cp prebuilts/vcmailbox build/sbin/vcmailbox
cp prebuilts/vcgenmd build/sbin/vcgenmd

## Fix up systemd-modules-load
cp prebuilts/load_modules.sh build/usr/local/bin/load_modules
cp prebuilts/systemd-modules-load.service build/etc/systemd/system/systemd-modules-load.service


echo "SSH VARIABLE WAS $SSH"

if [ ${SSH} = 1 ]
then
  echo "Installing SSH!"
  mkdir -p build/root/.ssh
  echo $(cat prebuilts/authorized_keys) > build/root/.ssh/authorized_keys
  chmod 0600 build/root/.ssh/authorized_keys
  mkdir build/dev/pts
fi
echo $(cat prebuilts/authorized_keys) > build/root/.ssh/authorized_keys
chmod 0600 build/root/.ssh/authorized_keys
mkdir build/dev/pts

sed --in-place 's/bash/sh/g' build/etc/passwd
echo "systemd-journal:x:104:
systemd-network:x:105:
systemd-resolve:x:106:
systemd-timesync:x:107:
kvm:*:1023" >> build/etc/group

# Package initramfs
cd build
find . -print0 | cpio --null -ov --format=newc > ../initramfs.cpio 2>/dev/null
cd ..
zstd --no-progress --rm -15 initramfs.cpio -o ${OUT_DIR}/rootfs.cpio.zst

echo "Making boot img"
echo "Out directory = ${OUT_DIR}"
mkdir -p ${OUT_DIR}
make-boot-image -d ${OUT_DIR}/ -o ${OUT_IMAGE_NAME} -a ${KERNEL_BIT_SIZE}
