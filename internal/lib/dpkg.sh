# Dpkg/apt helper functions
# Sourced by pi-gen-micro — not executable on its own.
# Expects: ROOTFS_DIR, DPKG_EXTRA_ARGS to be set by the caller.

apt_download() {
  fakeroot apt-get install --download-only "$@" 2>/dev/null
}

apt_install() {
  fakeroot apt-get install "$@" --no-install-recommends 2>/dev/null
}

get_package_path() {
  local pkg_name="$1"
  echo -n "apt_cache/archives/"
  apt-get download "$pkg_name" --print-uris | awk '{print $2}'
}

dpkg_unpack() {
  apt_download "$1"
  set -o noglob
  # shellcheck disable=SC2086
  fakeroot \
    dpkg \
      --instdir="$ROOTFS_DIR" \
      --admindir="$PWD/dpkg_admin" \
      --log="$PWD/dpkg_admin/dpkg.log" \
      --force-script-chrootless \
      ${DPKG_EXTRA_ARGS} \
      --no-triggers \
      --unpack "$(get_package_path $1)"
  set +o noglob
}

dpkg_install() {
  apt_download "$1"
  set -o noglob
  # shellcheck disable=SC2086
  fakeroot \
    dpkg \
      --instdir="$ROOTFS_DIR" \
      --admindir="$PWD/dpkg_admin" \
      --log="$PWD/dpkg_admin/dpkg.log" \
      --force-script-chrootless \
      ${DPKG_EXTRA_ARGS} \
      --install "$(get_package_path $1)"
  set +o noglob
}

# Download, patch, and install a udeb as a substitute for a regular package
install_udeb_substitute() {
  local udeb_package="$1"
  local base_package="${udeb_package%-udeb}"

  apt_download "$udeb_package"
  PACKAGE_PATH="$(get_package_path "$udeb_package")"
  EXTRACT_DIR="$(mktemp --directory --tmpdir deb-extract.XXX)"
  dpkg-deb --raw-extract "${PACKAGE_PATH}" "${EXTRACT_DIR}"
  rm "${PACKAGE_PATH}"

  PACKAGE_VERSION="$(grep -oP '^Version:\s*\K.*' "${EXTRACT_DIR}"/DEBIAN/control)"

  # Check if Provides: line exists
  if ! grep -q "^Provides:" "${EXTRACT_DIR}/DEBIAN/control"; then
    # If not, add it before the first line
    sed -i "1iProvides: ${base_package} (= ${PACKAGE_VERSION}), ${base_package}:arm64" "${EXTRACT_DIR}/DEBIAN/control"
  else
    # If it exists, modify it
    sed --in-place "/^Provides:/s/${base_package},/${base_package} (= ${PACKAGE_VERSION}), ${base_package}:arm64,/" "${EXTRACT_DIR}/DEBIAN/control"
  fi

  echo "Replaces: ${base_package} (= ${PACKAGE_VERSION})
Conflicts: ${base_package} (= ${PACKAGE_VERSION})" >> "${EXTRACT_DIR}/DEBIAN/control"

  dpkg-deb --root-owner-group --build "${EXTRACT_DIR}" "${PACKAGE_PATH}"
  rm -rf "${EXTRACT_DIR}"

  set -o noglob
  # shellcheck disable=SC2086
  fakeroot \
    dpkg \
      --instdir="$ROOTFS_DIR" \
      --admindir="$PWD/dpkg_admin" \
      --log="$PWD/dpkg_admin/dpkg.log" \
      --force-script-chrootless \
      ${DPKG_EXTRA_ARGS} \
      --install "${PACKAGE_PATH}"
  set +o noglob
}
