# shellcheck shell=bash
# Device target table: maps target name -> dtbs, overlays, and firmware
# Sourced by pi-gen-micro — not executable on its own.
# Expects: KPKG_EXTRACT, KERNEL_VERSION_STR, OUT_DIR to be set by the caller.

# A BCM2837 part has two device trees in the kernel package: bcm2710-<board>.dtb
# and bcm2837-<board>.dtb. The firmware composes the name it asks for as
# bcm<chip>-rpi-<board>.dtb, and picks 2710 over 2837 when arm_64bit=1 -- which
# every configuration here sets. So the bcm2837-* files are 32-bit-only and are
# never loaded; copying one is the same as copying nothing. raspi-firmware's
# kernel hook shows the same split: it installs bcm27*.dtb into /boot/firmware
# and a working 64-bit image carries no bcm2837-* device tree at all.

# ---------------------------------------------------------------------------
# Firmware selection
# ---------------------------------------------------------------------------
#
# raspi-firmware carries five variants of each start/fixup pair. The camera and
# debug ones need start_x=1 or start_debug=1, which no configuration here sets,
# and the recovery pair belongs to a different boot mode. That leaves plain and
# cutdown -- and which of those a boot ROM asks for is a property of the
# configuration's config.txt, not of the target:
#
#   fastboot, miller      gpu_mem=16, no override      every board: cutdown
#   rpi-imager-embedded   gpu_mem_512=16, no gpu_mem    512MB: cutdown, else plain
#   no low gpu_mem at all                              every board: plain
#
# Shipping a variant nothing can select is weight that gets signed, cached and
# pushed to every device for nothing. Shipping one short of what the boot ROM
# asks for is a board that never boots: f26afd5 assumed a fallback to the plain
# firmware that the boot ROM does not have, and rpi-sb-provisioner 2.3.3 shipped
# that (#352, #353). Neither is a judgement call, so read the answer out of the
# config.txt going into the image and fail the build if the two disagree.
#
# gpu_mem is the *only* way to select the cutdown firmware. start_file and
# fixup_file cannot name it -- the config.txt documentation is explicit that a
# board told to load start*cd.elf that way fails to boot -- so this deliberately
# writes nothing into config.txt and leaves the selection to gpu_mem, which is
# already there. verify_firmware_selection() rejects such a pin if one is ever
# added by hand.

# SoCs whose firmware this image carries, set by install_soc_firmware.
INSTALLED_FIRMWARE_SOCS=""

# The start/fixup pair for a SoC, by variant.
firmware_names() {
  case "$1/$2" in
    283x/plain)   echo "start.elf fixup.dat" ;;
    283x/cutdown) echo "start_cd.elf fixup_cd.dat" ;;
    2711/plain)   echo "start4.elf fixup4.dat" ;;
    2711/cutdown) echo "start4cd.elf fixup4cd.dat" ;;
    *) echo "Error: no firmware names for SoC '$1' variant '$2'" >&2 ; return 1 ;;
  esac
}

# Which variants this image's config.txt can make a boot ROM ask for.
# Echoes: cutdown | plain | both
firmware_variant() {
  local cfg="${OUT_DIR}/config.txt" reachable value low=0 high=0

  # Every gpu_mem a board could end up with. A gpu_mem before the first
  # conditional filter applies to all of them, and 64 is the firmware's own
  # default when there is none; a gpu_mem_256/512/1024 line replaces it on
  # boards with that much RAM, and a gpu_mem behind a filter on the boards that
  # filter names -- so each of those is reachable for some boards, not all.
  reachable="$(awk '
    /^[[:space:]]*\[/                            { filtered = 1 }
    /^[[:space:]]*gpu_mem=[0-9]+/                 { sub(/^[^=]*=/, "")
                                                    if (filtered) print $0 + 0
                                                    else { base = $0 + 0; seen = 1 } }
    /^[[:space:]]*gpu_mem_(256|512|1024)=[0-9]+/  { sub(/^[^=]*=/, ""); print $0 + 0 }
    END                                           { print (seen ? base : 64) }
  ' "${cfg}")"

  for value in ${reachable}; do
    if [ "${value}" -le 16 ]; then low=1; else high=1; fi
  done

  if   [ "${low}" = 1 ] && [ "${high}" = 1 ]; then echo both
  elif [ "${low}" = 1 ];                      then echo cutdown
  else                                             echo plain
  fi
}

# Copies the start/fixup pair(s) a boot ROM for $1 can be asked for.
install_soc_firmware() {
  local soc="$1" variant name
  local -a names=()
  variant="$(firmware_variant)"

  if [ "${variant}" = both ]; then
    read -ra names <<< "$(firmware_names "${soc}" plain) $(firmware_names "${soc}" cutdown)"
  else
    read -ra names <<< "$(firmware_names "${soc}" "${variant}")"
  fi
  for name in "${names[@]}"; do
    cp "raspi-firmware/${name}" "${OUT_DIR}"/
  done

  case " ${INSTALLED_FIRMWARE_SOCS} " in
    *" ${soc} "*) ;;
    *) INSTALLED_FIRMWARE_SOCS="${INSTALLED_FIRMWARE_SOCS}${soc} " ;;
  esac
}

# Firmware the BCM2835/6/7 boot ROM (Pi 0-3) loads. bootcode.bin is the second
# stage itself, so it ships whatever the gpu_mem arithmetic says.
install_bcm283x_firmware() {
  cp raspi-firmware/bootcode.bin "${OUT_DIR}"/
  cp raspi-firmware/LICENCE.broadcom "${OUT_DIR}"/
  install_soc_firmware 283x
}

# Firmware the BCM2711 boot ROM (Pi 4 family) loads. There is deliberately no
# BCM2712 helper: Pi 5 and CM5 take their firmware from EEPROM and ask for no
# start file at all, which is why a pi5-family image is never given one to look
# for.
install_bcm2711_firmware() {
  cp raspi-firmware/LICENCE.broadcom "${OUT_DIR}"/
  install_soc_firmware 2711
}

# Fails the build if the image does not carry the firmware its own config.txt
# will make a boot ROM ask for, or carries a start file nothing can select.
# This is the check 2.3.3 went out without: the file list lives here, the
# gpu_mem that selects from it lives in the configuration, and nothing compared
# the two.
verify_firmware_selection() {
  local cfg="${OUT_DIR}/config.txt" variant soc name wanted="" rc=0

  [ -n "${INSTALLED_FIRMWARE_SOCS}" ] || return 0
  variant="$(firmware_variant)"

  for soc in ${INSTALLED_FIRMWARE_SOCS}; do
    if [ "${variant}" = both ]; then
      wanted="${wanted} $(firmware_names "${soc}" plain) $(firmware_names "${soc}" cutdown)"
    else
      wanted="${wanted} $(firmware_names "${soc}" "${variant}")"
    fi
  done

  # A start_file or fixup_file naming a cutdown variant is a documented
  # non-boot: gpu_mem=16 is the only way to select that firmware. Catch it here
  # rather than on a board that goes quiet.
  while read -r name; do
    [ -n "${name}" ] || continue
    case "${name}" in
      *cd.elf | *_cd.dat | *cd.dat)
        echo "Error: config.txt pins ${name}; cutdown firmware cannot be selected by start_file/fixup_file and the board will not boot -- use gpu_mem=16" >&2
        rc=1
        ;;
    esac
    # Anything it does name outright has to be there, whichever variant the
    # gpu_mem arithmetic landed on.
    wanted="${wanted} ${name}"
  done < <(sed -nE 's/^[[:space:]]*(start|fixup)_file=[[:space:]]*([^[:space:]#]+).*/\2/p' "${cfg}")

  for name in ${wanted}; do
    if [ ! -f "${OUT_DIR}/${name}" ]; then
      echo "Error: config.txt asks for ${name}, which this image does not carry" >&2
      rc=1
    fi
  done

  for name in "${OUT_DIR}"/start*.elf "${OUT_DIR}"/fixup*.dat; do
    [ -e "${name}" ] || continue
    name="$(basename "${name}")"
    case " ${wanted} " in
      *" ${name} "*) ;;
      *) echo "Error: ${name} ships but nothing in config.txt can select it" >&2 ; rc=1 ;;
    esac
  done

  if [ "${rc}" -eq 0 ]; then
    echo "Firmware selection: ${variant}, for ${INSTALLED_FIRMWARE_SOCS% }"
  fi
  return "${rc}"
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
      pi3-family) out+=(pi3 cm3 02W cm0) ;;
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
      ;;
    cm3)
      install_bcm283x_firmware
      cp "$kimg"/broadcom/bcm2710-rpi-cm3.dtb "${OUT_DIR}"/
      ;;
    02W)
      install_bcm283x_firmware
      cp "$kimg"/broadcom/bcm2710-rpi-zero-2-w.dtb "${OUT_DIR}"/
      cp "$kimg"/broadcom/bcm2710-rpi-zero-2.dtb "${OUT_DIR}"/
      ;;
    cm0)
      install_bcm283x_firmware
      cp "$kimg"/broadcom/bcm2710-rpi-cm0.dtb "${OUT_DIR}"/
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
