# Busybox init path
# Sourced by pi-gen-micro — not executable on its own.
# Expects: dpkg.sh functions, PREBUILTS_DIR, CONFIGURATION_FOLDER, UDEV, AUTOLOGIN, GETTY, SSH, NETWORK, NETWORK_BASIC

install_init_packages() {
  # busybox init: invoked as PID 1 it reads /etc/inittab
  ln -s /bin/busybox build/init
}

configure_init_services() {
  cp "${PREBUILTS_DIR}"/inittab build/etc/inittab
  mkdir -p build/etc/init.d/services.d
  cp "${PREBUILTS_DIR}"/rcS build/etc/init.d/rcS
  chmod +x build/etc/init.d/rcS

  # When GETTY=0, strip the console getty lines so no login prompt appears.
  if [ "${GETTY}" = 0 ]; then
    sed -i '/\/sbin\/getty/d' build/etc/inittab
    return
  fi

  if [ "${AUTOLOGIN}" = 1 ]; then
    sed -i 's|/sbin/getty 38400 tty1|/sbin/getty -n -l /bin/sh 38400 tty1|' build/etc/inittab
    sed -i 's|/sbin/getty -L serial0 115200 vt100|/sbin/getty -n -l /bin/sh -L serial0 115200 vt100|' build/etc/inittab
  fi
}

configure_init_modules() {
  cp "${PREBUILTS_DIR}"/load_modules.sh build/usr/local/bin/load_modules
  # rcS invokes load_modules directly — no .service file needed
}

install_networking() {
  echo "Installing networking (busybox)"
  mkdir -p build/usr/share/udhcpc
  cp "${PREBUILTS_DIR}"/network.script build/usr/share/udhcpc/default.script
  chmod +x build/usr/share/udhcpc/default.script
  mkdir -p build/etc/init.d
  cp "${PREBUILTS_DIR}"/network_init.sh build/etc/init.d/network
  chmod +x build/etc/init.d/network

  echo "nameserver 8.8.8.8
nameserver 8.8.4.4
" > build/etc/resolv.conf

  mkdir -p build/etc/ssl/certs/
  cp -r /etc/ssl/certs/* build/etc/ssl/certs/
  cp /etc/ca-certificates.conf build/etc/ca-certificates.conf
}

install_networking_basic() {
  # Minimal: link up + DHCP, no /etc/resolv.conf and no CA trust store copy.
  echo "Installing networking (busybox, basic)"
  mkdir -p build/usr/share/udhcpc
  cp "${PREBUILTS_DIR}"/network.script build/usr/share/udhcpc/default.script
  chmod +x build/usr/share/udhcpc/default.script
  mkdir -p build/etc/init.d
  cp "${PREBUILTS_DIR}"/network_init.sh build/etc/init.d/network
  chmod +x build/etc/init.d/network
}

configure_init_ssh() {
  mkdir -p build/etc/init.d/services.d
  printf '#!/bin/sh\nexec /usr/local/bin/ssh_service\n' > build/etc/init.d/services.d/ssh
  chmod +x build/etc/init.d/services.d/ssh
}
