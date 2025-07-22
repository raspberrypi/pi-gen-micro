#!/bin/sh
TIME_STR=$(wget -q -S -O /dev/null --no-verbose --continue http://downloads.raspberrypi.com 2>&1 | grep -i 'date:' | awk -F': ' '{print $2}')
if [ -n "$TIME_STR" ]; then
    date -s "$TIME_STR"
    echo "Time set to: $(date)"
else
    echo "Failed to get time from server."
fi
