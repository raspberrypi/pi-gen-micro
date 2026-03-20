#!/bin/sh

# LOCATIONS="/etc/modules-load.d/*.conf, /run/modules-load.d/*.conf, /usr/local/lib/modules-load.d/*.conf, /usr/lib/modules-load.d/*.conf, "
# IFS=', ' read -r -a locations <<< "$(echo $LOCATIONS)"

locs="path1 path2 path3 path4"
set -- $locs
for location in "/etc/modules-load.d/*.conf /run/modules-load.d/*.conf /usr/local/lib/modules-load.d/*.conf /usr/lib/modules-load.d/*.conf" ; do
    set -- $(cat $location | tr '\n' ' ')
    while [ -n "$1" ]; do
        echo "Modprobing $1"
        /sbin/modprobe $1
        shift
    done
done

sleep 2