#!/usr/bin/env bash

# Deps:
#  - bash
#  - curl (with etags support)
#  - grep-dctrl (from dctrl-tools)
#  - basename (from coreutils)
#  - sha256sum (from coreutils)
#  - gunzip (from gzip)

set -e

# TODO: debconf or configuration file? command line option?
REPOSITORY="${REPOSITORY:-ftp.uk.debian.org/debian}"
RELEASE="${RELEASE:-bookworm}"
ARCH="${ARCH:-arm64}"
REQUESTED_PACKAGE="${1:-libc6-udeb}"

PACKAGES_GZ_FILE="Packages.gz"
#PACKAGES_GZ_ETAG_FILE="${PACKAGES_GZ_FILE}.etag"
PACKAGES_GZ_URL="${REPOSITORY}/dists/${RELEASE}/main/debian-installer/binary-${ARCH}/${PACKAGES_GZ_FILE}"
# Make use of etags to avoid repeatedly downloading a potentially unchanged file
rm -f $PACKAGES_GZ_FILE
wget $PACKAGES_GZ_URL -q

# curl \
#	--etag-compare ${PACKAGES_GZ_ETAG_FILE} \
#	--etag-save ${PACKAGES_GZ_ETAG_FILE} \
#	${PACKAGES_GZ_URL} \
#	-o ${PACKAGES_GZ_FILE} \
#	2> /dev/null

#PACKAGES_GZ_ETAG="$(< ${PACKAGES_GZ_ETAG_FILE})"
#PACKAGES_GZ_ETAG="${PACKAGES_GZ_ETAG%\"}"
#PACKAGES_GZ_ETAG="${PACKAGES_GZ_ETAG#\"}"

# Extract the downloaded file, use the etag as a suffix to create a unique file
# as other scripts may make use of this in future.
# This should also potentially be a temporary file
PACKAGES_FILE="Packages"

gunzip --to-stdout ${PACKAGES_GZ_FILE} > ${PACKAGES_FILE}


# e.g. get_dctrl_field Packages raspberrypi-kernel [Filename|SHA256|etc.]
function get_dctrl_field() {
	grep-dctrl \
		--field=Package \
		--exact-match "${2}" \
		--no-field-names \
		--show-field="${3}" \
		${1}
}

# Extract information for requested package
VERSION="$(get_dctrl_field ${PACKAGES_FILE} ${REQUESTED_PACKAGE} Version)"
#if [ ! -f ${REQUESTED_PACKAGE_INFO_FILE} ]
#then
#fi
PACKAGE_URL="$(grep-dctrl --field=Package --exact-match ${REQUESTED_PACKAGE} ${PACKAGES_FILE} --show-field Filename -n)"
wget "${REPOSITORY}/${PACKAGE_URL}" -O "packages/${REQUESTED_PACKAGE}_${VERSION}.udeb"  -q


## Cleanup
rm "${PACKAGES_GZ_FILE}"
echo "packages/${REQUESTED_PACKAGE}_${VERSION}.udeb"
#REQUESTED_PACKAGE_PARTIAL_URL="$(get_dctrl_field ${REQUESTED_PACKAGE_INFO_FILE} ${REQUESTED_PACKAGE} Filename)"
#REQUESTED_PACKAGE_URL="${REPOSITORY}/${REQUESTED_PACKAGE_PARTIAL_URL}"
#REQUESTED_PACKAGE_FILE="$(basename ${REQUESTED_PACKAGE_PARTIAL_URL})"
#>&2 echo "Aquiring package version ${REQUESTED_PACKAGE_VERSION}"
#if [ ! -f ${REQUESTED_PACKAGE_FILE} ]
#then
#	curl \
#		${REQUESTED_PACKAGE_URL} \
#		-o ${REQUESTED_PACKAGE_FILE} \
#		2> /dev/null
#fi
#
#REQUESTED_PACKAGE_SHA256SUM="$(get_dctrl_field ${REQUESTED_PACKAGE_INFO_FILE} ${REQUESTED_PACKAGE} SHA256)"
#REQUESTED_PACKAGE_CSUM_FILE="${REQUESTED_PACKAGE_FILE}.sha256"
#echo "${REQUESTED_PACKAGE_SHA256SUM} ${REQUESTED_PACKAGE_FILE}" > ${REQUESTED_PACKAGE_CSUM_FILE}
#>&2 echo -n "Verifying package checksum: "
#>&2 sha256sum --check "${REQUESTED_PACKAGE_CSUM_FILE}"

#echo "${REQUESTED_PACKAGE_FILE}"

