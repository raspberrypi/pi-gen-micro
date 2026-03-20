# Systemd init path
# Sourced by pi-gen-micro — not executable on its own.
# Expects: dpkg.sh functions, PREBUILTS_DIR, CONFIGURATION_FOLDER, UDEV, AUTOLOGIN, SSH, NETWORK

install_init_packages() {
  # TODO: postinst failure, fstrim settings using deb-systemd-helper
  apt_install util-linux

  apt_install systemd-sysv
  # Symlink to regular /sbin/init (systemd-sysv provides /sbin/init)
  ln -s /sbin/init build/init
}

configure_init_services() {
  # getty-static.service starts tty2-tty6 if dbus / logind are not available
  mkdir -p build/etc/systemd/system/getty-static.service.d
  echo "[Service]
ExecStart=
ExecStart=/bin/true
" > build/etc/systemd/system/getty-static.service.d/override.conf

  # serial-getty waits for device unit (using udev) by default, disable this if
  # udev is not used. Always make a copy of serial-getty@.service in 'etc'.
  if [ "${UDEV}" = 1 ]; then
    cp build/usr/lib/systemd/system/serial-getty@.service \
      build/etc/systemd/system/serial-getty@.service
  else
    sed '
    /^BindsTo/d
    /^After=/s/dev-%i\.device\s*//' \
      build/usr/lib/systemd/system/serial-getty@.service \
      > build/etc/systemd/system/serial-getty@.service
  fi

  if [ "${AUTOLOGIN}" = 1 ]; then
    mkdir -p build/etc/systemd/system/getty@tty1.service.d
    # shellcheck disable=SC2028
    echo "[Service]
  ExecStart=
  ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin root %I \$TERM
  TTYVTDisallocate=no
  " > build/etc/systemd/system/getty@tty1.service.d/autologin.conf

    sed --in-place '
    s/\(--keep-baud\)/--noclear --autologin root \1/' \
      build/etc/systemd/system/serial-getty@.service
  fi
}

configure_init_modules() {
  cp "${PREBUILTS_DIR}"/load_modules.sh build/usr/local/bin/load_modules
  cp "${PREBUILTS_DIR}"/systemd-modules-load.service build/etc/systemd/system/systemd-modules-load.service
}

install_networking() {
  echo "Installing & Enabling networking"
  apt_install systemd-timesyncd
  cp "${PREBUILTS_DIR}"/20-wired.network build/etc/systemd/network/20-wired.network
  mkdir -p build/var/lib/systemd/timesync/
  cp "${PREBUILTS_DIR}"/timesyncd.conf build/etc/systemd/timesyncd.conf

  # Adjust timesyncd to wait for network
  sed -i "s/After=systemd-sysusers.service/After=systemd-sysusers.service, network-online.target/" ./build/usr/lib/systemd/system/systemd-timesyncd.service
  sed -i "s/Wants=time-set.target/Wants=network-online.target/" build/usr/lib/systemd/system/systemd-timesyncd.service
  sed -i "s/Before=time-set.target sysinit.target shutdown.target//" build/usr/lib/systemd/system/systemd-timesyncd.service

  # Enable networkd and resolved
  mkdir -p build/etc/systemd/system
  ln -s /lib/systemd/system/systemd-networkd.service build/etc/systemd/system/dbus-org.freedesktop.network1.service
  mkdir -p build/etc/systemd/system/multi-user.target.wants
  ln -s /lib/systemd/system/systemd-networkd.service build/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
  ln -s /lib/systemd/system/systemd-resolved.service build/etc/systemd/system/multi-user.target.wants/systemd-resolved.service

  echo "nameserver 8.8.8.8
nameserver 8.8.4.4
" > build/etc/resolv.conf

  # ca-certificates are not installed into the correct directory by default
  # Importing the required certificates from the Host machine
  mkdir -p build/etc/ssl/certs/
  cp -r /etc/ssl/certs/* build/etc/ssl/certs/
  cp /etc/ca-certificates.conf build/etc/ca-certificates.conf

  mkdir -p build/etc/systemd/system/sockets.target.wants
  ln -s /lib/systemd/system/systemd-networkd.socket build/etc/systemd/system/sockets.target.wants/systemd-networkd.socket
  mkdir -p build/etc/systemd/system/sysinit.target.wants
  ln -s /lib/systemd/system/systemd-network-generator.service build/etc/systemd/system/sysinit.target.wants/systemd-network-generator.service
  mkdir -p build/etc/systemd/system/network-online.target.wants
  ln -s /lib/systemd/system/systemd-networkd-wait-online.service build/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
}

configure_init_ssh() {
  # systemd handles SSH service via the .service file in the deb package
  :
}
