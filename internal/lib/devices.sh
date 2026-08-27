# shellcheck shell=bash
# Device target table: maps target name -> dtbs, overlays, and firmware
# Sourced by pi-gen-micro — not executable on its own.
# Expects: KPKG_EXTRACT, KERNEL_VERSION_STR, OUT_DIR to be set by the caller.

# Firmware the BCM2835/6/7 boot ROM (Pi 0-3) loads. Named rather than globbed:
# raspi-firmware's camera, debug and cutdown variants need start_x=1,
# start_debug=1 or a low gpu_mem, none of which any configuration here sets.
install_bcm283x_firmware() {
  cp raspi-firmware/bootcode.bin "${OUT_DIR}"/
  cp raspi-firmware/start.elf "${OUT_DIR}"/
  cp raspi-firmware/fixup.dat "${OUT_DIR}"/
  cp raspi-firmware/LICENCE.broadcom "${OUT_DIR}"/
}

# Firmware the BCM2711 boot ROM (Pi 4 family) loads.
install_bcm2711_firmware() {
  cp raspi-firmware/start4.elf "${OUT_DIR}"/
  cp raspi-firmware/fixup4.dat "${OUT_DIR}"/
  cp raspi-firmware/LICENCE.broadcom "${OUT_DIR}"/
}

# Device families, by the SoC whose firmware and DTBs they share. A provisioning
# station is pinned to one family by rpi-sb-provisioner's RPI_DEVICE_FAMILY, so
# building per family drops a fastboot image from ~51MB to ~27MB.
expand_device_families() {
  local out=() target
  for target in "$@"; do
    case "$target" in
      pi5-family) out+=(cm5 pi5 500) ;;
      pi4-family) out+=(cm4 400 pi4) ;;
      pi3-family) out+=(pi3 cm3 02W) ;;
      *)          out+=("$target") ;;
    esac
  done
  printf '%s\n' "${out[@]}"
}

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
      install_bcm2711_firmware
      cp "$kimg"/broadcom/bcm2711-rpi-cm4.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2711-rpi-cm4s.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2711-rpi-cm4-io.dtb "${OUT_DIR}"/
      install_pi4_overlays
      ;;
    400)
      install_bcm2711_firmware
      cp "$kimg"/broadcom/bcm2711-rpi-400.dtb "${OUT_DIR}"/
      install_pi4_overlays
      ;;
    pi4)
      install_bcm2711_firmware
      cp "$kimg"/broadcom/bcm2711-rpi-4-b.dtb "${OUT_DIR}"/
      install_pi4_overlays
      ;;
    pi3)
      install_bcm283x_firmware
      cp "$kimg"/broadcom/bcm2710-rpi-3-b-plus.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2710-rpi-3-b.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-3-a-plus.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-3-b.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-3-b-plus.dtb "${OUT_DIR}"/
      ;;
    cm3)
      install_bcm283x_firmware
      cp "$kimg"/broadcom/bcm2710-rpi-cm3.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2837-rpi-cm3-io3.dtb "${OUT_DIR}"/
      ;;
    02W)
      install_bcm283x_firmware
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
