#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Replace the default busybox init with a custom /init script.
# Modelled on the reference net_install image: mount, udev, network, exec app.
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

# Device management via udev. mdev creates device nodes but not udev's
# ID_INPUT* properties, and libinput -- which Qt's linuxfb plugin uses --
# refuses any device that lacks them, so mdev alone leaves the image with no
# usable input at all. This is the installer's standalone udev (udev-udeb):
# same daemon and rules, but linked without libsystemd-shared, so it costs
# ~2.9 MB rather than ~8.4 MB. udevd also gives hotplug over netlink, so a
# keyboard or mouse plugged in after startup is picked up.
mkdir -p /run/udev
/usr/lib/systemd/systemd-udevd --daemon
udevadm trigger --action=add
udevadm settle --timeout=10

# Seed urandom
cat /proc/cpuinfo /sys/class/drm/*/edid > /dev/urandom 2>/dev/null

# Networking — udhcpc in background, resolv.conf set by default.script
mkdir -p /var/run
ifconfig lo 127.0.0.1 up
udhcpc -i end0 -s /usr/share/udhcpc/default.script -b -q 2>/dev/null &

# Set the clock before Imager starts. Nothing else here does -- there is no
# timesyncd or ntpd -- so a board with no RTC battery boots at 1970 or where
# its RTC stopped, and every HTTPS certificate is then "not yet valid". The
# Date header of a plain-HTTP reply needs no TLS to read. Waiting for it also
# holds Imager back until the lease is in, where it otherwise starts on a
# slow PHY's link-down and never looks again. Give up after 10 s with no
# carrier, so a board used offline is not kept waiting, and after 30 s in all.
n=0
while [ "$n" -lt 30 ]; do
    if [ "$n" -ge 10 ] && [ "$(cat /sys/class/net/end0/carrier 2>/dev/null)" != 1 ]; then
        break
    fi
    d=$(timeout 5 wget -q -S -O /dev/null http://downloads.raspberrypi.com/ 2>&1 \
        | sed -n 's/^ *[Dd]ate: //p' | head -1)
    # Guarded: date -s "" would set the clock to midnight, not fail.
    if [ -n "$d" ] && date -s "$d" >/dev/null 2>&1; then
        hwclock -w 2>/dev/null
        echo "Clock set from downloads.raspberrypi.com: $(date -u)"
        break
    fi
    sleep 1
    n=$((n + 1))
done

# Wait briefly for a keyboard or mouse. Testing for /dev/input/event0 is not
# enough: on Pi 5-class boards the gpio-keys power button (Bus=0019) claims
# event0 and appears long before USB enumerates, so the check passed instantly
# and the imager started with no usable input. Match the buses a keyboard or
# mouse actually arrives on -- USB, Bluetooth, I2C -- and never block forever,
# since udev and libinput will pick up anything that shows up later.
input_attached() {
    grep -qE '^I: Bus=(0003|0005|0018)' /proc/bus/input/devices 2>/dev/null
}
if ! input_attached; then
    echo ""
    echo "No input device detected."
    echo "Attach a mouse or keyboard to continue."
    echo ""
    n=0
    while [ "$n" -lt 100 ] && ! input_attached; do
        sleep 0.1
        n=$((n + 1))
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
