#!/bin/bash
#
# Copyright (C) 2017-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

# patchelf 0.9 breaks the GNSS HALs on --set-soname
export PATCHELF_VERSION=0_17_2

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d ${MY_DIR} ]]; then MY_DIR="${PWD}"; fi

LINEAGE_ROOT="${MY_DIR}"/../../..

HELPER="${LINEAGE_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
	echo "Unable to find helper script at ${HELPER}"
	exit 1
fi
source "${HELPER}"

function add_needed_if_missing {
	"$PATCHELF" --print-needed "$2" | grep -Fxq "$1" || "$PATCHELF" --add-needed "$1" "$2"
}

function blob_fixup {
	case "$1" in
	vendor/lib64/libOpenCv.camera.samsung.so)
		add_needed_if_missing libcomparetf2_shim.so "$2"
		;;
	vendor/lib64/hw/vendor.samsung.hardware.gnss@2.0-impl.so)
		"$PATCHELF" --remove-needed libhwbinder.so "$2"
		;;
	vendor/lib64/libkeymaster_helper_vendor.so)
		add_needed_if_missing libshim_keymaster.so "$2"
		;;
	vendor/lib/lib_SamsungRec_07010.so | vendor/lib/lib_SoundAlive_SRC384_ver320.so)
		add_needed_if_missing libc++.so "$2"
		;;
	vendor/lib64/libhifills.so)
		grep -q libunwindstack.so "$2" || "$PATCHELF" --add-needed "libunwindstack.so" "$2"
		grep -q libdemangle.so "$2" || "$PATCHELF" --add-needed "libdemangle.so" "$2"
		;;
	vendor/lib*/hw/camera.exynos7904.so)
		"$PATCHELF" --replace-needed "libcamera_client.so" "libcamera_metadata_helper.so" "$2"
		;;
	vendor/lib*/libexynoscamera.so | vendor/lib*/libexynoscamera3.so)
		"$PATCHELF" --remove-needed "libcamera_client.so" "$2"
		add_needed_if_missing libcamera_metadata_helper.so "$2"
		if [[ "$1" == */libexynoscamera.so ]]; then
			add_needed_if_missing libgui.so "$2"
		else
			"$PATCHELF" --remove-needed "libgui.so" "$2"
			add_needed_if_missing libshim_fdsan.so "$2"
			# S5K5E9: fill the size tables the HAL reads for camera 2 (ultra-wide)
			"$SIGSCAN" -p "60 0E 83 3D 69 A2 31 39 A1 04 00 54" -P "60 0E 83 3D 69 A2 31 39 B4 04 00 34" -f "$2"
		fi
		;;
	vendor/lib*/libsensorlistener.so)
		grep -q libshim_sensorndkbridge.so "$2" || "$PATCHELF" --add-needed "libshim_sensorndkbridge.so" "$2"
		;;
	vendor/bin/hw/rild | vendor/lib*/libsec-ril*.so)
		"$PATCHELF" --replace-needed libril.so libril-samsung.so "$2"
		;;
        vendor/lib/libaudio_soundtrigger.so | vendor/lib/libaudioroute.universal7904.so | vendor/lib/soundfx/libaudioeffectoffload.so)
		"$PATCHELF" --replace-needed libtinyalsa.so libtinyalsa.universal7904.so "$2"
		;;
	vendor/lib/hw/audio.primary.exynos7904.so)
		"$PATCHELF" --replace-needed libaudioroute.so libaudioroute.universal7904.so "$2"
		"$PATCHELF" --replace-needed libtinyalsa.so libtinyalsa.universal7904.so "$2"
		grep -q libshim_audioparams.so "$2" || "$PATCHELF" --add-needed libshim_audioparams.so "$2"
		sed -i 's/str_parms_get_str/str_parms_get_mod/g' "$2"
		;;
	vendor/lib/libwvhidl.so | vendor/lib/mediadrm/libwvdrmengine.so)
		"$PATCHELF" --replace-needed "libprotobuf-cpp-lite-3.9.1.so" "libprotobuf-cpp-full-3.9.1.so" "$2"
		grep -q libcrypto_shim.so "$2" || "$PATCHELF" --add-needed libcrypto_shim.so "$2"
		;;
	esac
}

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_TARGET=
SECTION=
KANG=

while [ "${#}" -gt 0 ]; do
	case "${1}" in
	--only-common)
		ONLY_COMMON=true
		;;
	--only-target)
		ONLY_TARGET=true
		;;
	-n | --no-cleanup)
		CLEAN_VENDOR=false
		;;
	-k | --kang)
		KANG="--kang"
		;;
	-s | --section)
		SECTION="${2}"
		shift
		CLEAN_VENDOR=false
		;;
	*)
		SRC="${1}"
		;;
	esac
	shift
done

if [ -z "${SRC}" ]; then
	SRC="adb"
fi

# Initialize the helper for common device
if [ -z "${ONLY_TARGET}" ]; then
	# Initialize the helper for common device
	setup_vendor "${DEVICE_COMMON}" "${VENDOR}" "${LINEAGE_ROOT}" true "${CLEAN_VENDOR}"

	extract "${MY_DIR}/proprietary-files.txt" "${SRC}" \
		"${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../${DEVICE}/proprietary-files.txt" ]; then
	# Reinitialize the helper for device
	source "${MY_DIR}/../${DEVICE}/extract-files.sh"
	setup_vendor "${DEVICE}" "${VENDOR}" "${LINEAGE_ROOT}" false "${CLEAN_VENDOR}"

	extract "${MY_DIR}/../${DEVICE}/proprietary-files.txt" "${SRC}" \
		"${KANG}" --section "${SECTION}"
fi

"${MY_DIR}/setup-makefiles.sh"
