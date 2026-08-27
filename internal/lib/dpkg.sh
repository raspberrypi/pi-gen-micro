# shellcheck shell=bash
# Dpkg/apt helper functions
# Sourced by pi-gen-micro — not executable on its own.
# Expects: ROOTFS_DIR, DPKG_EXTRA_ARGS to be set by the caller.

# Packages already fetched during this run. apt-get install --download-only
# re-runs the whole solver (~16s once the build is emulated) even when the .deb
# is already in the archive cache, and callers routinely re-request a package
# that an earlier batch has just pulled in. Tracking this run's own downloads is
# safe in a way that testing the cache is not: a cached .deb may be a stale
# version left behind by an earlier build.
declare -A APT_FETCHED=()

apt_download() {
  local wanted=() pkg
  for pkg in "$@"; do
    [ -z "${APT_FETCHED[$pkg]:-}" ] || continue
    wanted+=("$pkg")
  done
  if [ "${#wanted[@]}" -eq 0 ]; then
    return 0
  fi
  fakeroot apt-get install --download-only "${wanted[@]}" 2>/dev/null
  for pkg in "${wanted[@]}"; do
    APT_FETCHED[$pkg]=1
  done
}

apt_install() {
  fakeroot apt-get install "$@" --no-install-recommends 2>/dev/null
}

get_package_path() {
  local pkg_name="$1"
  local matches=()
  mapfile -t matches < <(ls -t "apt_cache/archives/${pkg_name}"_*.deb \
                               "apt_cache/archives/${pkg_name}"_*.udeb 2>/dev/null)
  # Callers always apt_download first, so the archive is already cached and
  # asking apt to recompute its filename costs a full cache parse -- ~5s per
  # call once the build is emulated -- to learn what we already know. Take the
  # shortcut only when it is unambiguous: with no match, or several versions
  # where guessing wrong would install a stale package, defer to apt.
  if [ "${#matches[@]}" -eq 1 ]; then
    echo -n "${matches[0]}"
  else
    echo -n "apt_cache/archives/"
    apt-get download "$pkg_name" --print-uris | awk '{print $2}'
  fi
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
