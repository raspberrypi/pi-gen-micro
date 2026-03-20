# Device target table: maps target name -> dtbs, overlays, and firmware
# Sourced by pi-gen-micro — not executable on its own.
# Expects: KPKG_EXTRACT, KERNEL_VERSION_STR, OUT_DIR to be set by the caller.

install_device_files() {
  local target="$1"
  local kimg="${KPKG_EXTRACT}/usr/lib/linux-image-${KERNEL_VERSION_STR}"

  case "$target" in
    cm5)
      cp "$kimg"/broadcom/bcm2712-rpi-cm5-cm4io.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2712-rpi-cm5-cm5io.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2712-rpi-cm5l-cm4io.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2712-rpi-cm5l-cm5io.dtb "${OUT_DIR}"/
      install_pi5_overlays
      ;;
    500)
      cp "$kimg"/broadcom/bcm2712-rpi-500.dtb "${OUT_DIR}"/
      install_pi5_overlays
      ;;
    pi5)
      cp "$kimg"/broadcom/bcm2712d0-rpi-5-b.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2712-d-rpi-5-b.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2712-rpi-5-b.dtb "${OUT_DIR}"/
      install_pi5_overlays
      ;;
    cm4)
      cp raspi-firmware/start4.elf "${OUT_DIR}"/
      cp raspi-firmware/fixup4.dat "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2711-rpi-cm4.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2711-rpi-cm4s.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2711-rpi-cm4-io.dtb "${OUT_DIR}"/
      install_pi4_overlays
      ;;
    400)
      cp raspi-firmware/start4.elf "${OUT_DIR}"/
      cp raspi-firmware/fixup4.dat "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2711-rpi-400.dtb "${OUT_DIR}"/
      install_pi4_overlays
      ;;
    pi4)
      cp raspi-firmware/start4*.elf "${OUT_DIR}"/
      cp raspi-firmware/fixup4*.dat "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2711-rpi-4-b.dtb "${OUT_DIR}"/
      install_pi4_overlays
      ;;
    pi3)
      cp raspi-firmware/* "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2710-rpi-3-b-plus.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2710-rpi-3-b.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-3-a-plus.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-3-b.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-3-b-plus.dtb "${OUT_DIR}"/
      ;;
    cm3)
      cp raspi-firmware/* "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2710-rpi-cm3.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-cm3-io3.dtb "${OUT_DIR}"/
      ;;
    02W)
      cp raspi-firmware/* "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-zero-2-w.dtb "${OUT_DIR}"/
      ;;
    *)
      echo "Warning: Unknown target device '${target}', skipping" >&2
      ;;
  esac
}

install_pi5_overlays() {
  local kimg="${KPKG_EXTRACT}/usr/lib/linux-image-${KERNEL_VERSION_STR}"
  cp "$kimg"/overlays/vc4-kms-v3d-pi5.dtbo "${OUT_DIR}"/overlays/
  cp "$kimg"/overlays/disable-bt-pi5.dtbo "${OUT_DIR}"/overlays/
  cp "$kimg"/overlays/disable-wifi-pi5.dtbo "${OUT_DIR}"/overlays/
  cp "$kimg"/overlays/bcm2712d0.dtbo "${OUT_DIR}"/overlays/
}

install_pi4_overlays() {
  local kimg="${KPKG_EXTRACT}/usr/lib/linux-image-${KERNEL_VERSION_STR}"
  cp "$kimg"/overlays/vc4-kms-v3d-pi4.dtbo "${OUT_DIR}"/overlays/
}
