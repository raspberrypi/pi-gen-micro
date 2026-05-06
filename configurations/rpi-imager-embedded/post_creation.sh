#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Replace the default busybox init with a custom /init script.
# Modelled on the reference net_install image: mount, mdev, network, exec app.
# ---------------------------------------------------------------------------

rm -f build/init
cat > build/init << 'INIT_EOF'
#!/bin/sh

# Mount pseudo-filesystems
mount -t proc proc /proc
mount -o remount,rw,noatime /
mount -t sysfs sysfs /sys
mount -t devtmpfs dev /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

# Load kernel modules
if [ -x /usr/local/bin/load_modules ]; then
    /usr/local/bin/load_modules
fi

# Device hotplug via busybox mdev
echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s

# Seed urandom
cat /proc/cpuinfo /sys/class/drm/*/edid > /dev/urandom 2>/dev/null

# Networking — udhcpc in background, resolv.conf set by default.script
mkdir -p /var/run
ifconfig lo 127.0.0.1 up
udhcpc -i end0 -s /usr/share/udhcpc/default.script -b -q 2>/dev/null &

# Wait for an input device (mouse/keyboard) before launching the imager
if [ ! -e /dev/input/event0 ]; then
    echo ""
    echo "No input device detected."
    echo "Attach a mouse or keyboard to continue."
    echo ""
    until [ -e /dev/input/event0 ]; do
        sleep 0.1
    done
fi

echo "Starting rpi-imager-embedded"
/bin/rpi-imager-embedded 2>/tmp/debug
sync
reboot -f
INIT_EOF
chmod +x build/init

# ---------------------------------------------------------------------------
# Misc cleanup — items that survive the delete.list pass
# ---------------------------------------------------------------------------
rm -rf build/usr/share/doc
rm -rf build/usr/share/libwacom
rm -rf build/var/lib/dpkg/info
