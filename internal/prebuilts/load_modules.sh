#!/bin/sh
#
# Load the modules named in modules-load.d, for images with no systemd.
# Mirrors systemd-modules-load(8): each .conf holds one module per line, with
# blank lines and #-comments ignored. systemd images use systemd's own native
# implementation instead, so this is only installed for busybox init.

for dir in /etc/modules-load.d /run/modules-load.d \
           /usr/local/lib/modules-load.d /usr/lib/modules-load.d; do
    [ -d "$dir" ] || continue
    for conf in "$dir"/*.conf; do
        [ -f "$conf" ] || continue
        while read -r module _; do
            case "$module" in
                ''|\#*) continue ;;
            esac
            modprobe "$module" || echo "load_modules: $module failed" >&2
        done < "$conf"
    done
done
