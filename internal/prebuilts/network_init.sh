#!/bin/sh
ifconfig lo 127.0.0.1 up
udhcpc -i end0 -s /usr/share/udhcpc/default.script -b -q
