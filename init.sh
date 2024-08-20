#!/usr/bin/env bash

source config

mkdir -p ${CONFIGURATION_ROOT}
cp -r configurations /etc/pi-gen-micro
chown pi -R ${CONFIGURATION_ROOT}

