#!/usr/bin/env bash
#
# Assemble OpenCore based EFI folder.

# Write safe shell scripts
set -euf -o pipefail

# Set locale
export LC_ALL="en_US.UTF-8"

# Extend PATH to always use Coreutils supplied utilities first.
export PATH="/opt/local/libexec/gnubin:${PATH}"

# Directories
readonly BASE_DIR="$(dirname "$(realpath "$0")")"
readonly BASE_EFI_DIR="${BASE_DIR}/EFI"
readonly BASE_OC_DIR="${BASE_EFI_DIR}/OC"
readonly TMP_DIR="$(mktemp -d)"

# Keep environment clean
trap 'run-on-trap $?' EXIT SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM
run-on-trap() {
  echo "Removing temporary directory '${TMP_DIR}'..."
  rm -rf "${TMP_DIR}"
  if [[ $1 -ne 0 ]]; then
    echo "Removing EFI directory '${BASE_EFI_DIR}'..."
    rm -fr "${BASE_EFI_DIR}"
  fi
}

# Package versions. Set desired versions here.
readonly OPENCORE_VERSION="0.6.5"
readonly KEXT_APPLEALC_VERSION="1.5.6"
readonly KEXT_INTELMAUSI_VERSION="1.0.5"
readonly KEXT_LILU_VERSION="1.5.0"
readonly KEXT_VIRTUALSMC_VERSION="1.1.9"
readonly KEXT_WHATEVERGREEN_VERSION="1.4.6"

# Installation settings
# Any non-zero value turns on local file copy, instead of downloading.
readonly LOCAL_RUN=${LOCAL_RUN:-0}
# Use release or debug variant
readonly OC_PKG_VARIANT=${OC_PKG_VARIANT:-RELEASE}

# Download locations
#
# Packages
# Base URL
readonly OC_BASE_URL="https://github.com/acidanthera"
# Package names
readonly PKG_OC="OpenCore-${OPENCORE_VERSION}-${OC_PKG_VARIANT}"
readonly PKG_OC_BINDATA="master"
readonly PKG_KEXT_APPLEALC="AppleALC-${KEXT_APPLEALC_VERSION}-${OC_PKG_VARIANT}"
readonly PKG_KEXT_INTELMAUSI="IntelMausi-${KEXT_INTELMAUSI_VERSION}-${OC_PKG_VARIANT}"
readonly PKG_KEXT_LILU="Lilu-${KEXT_LILU_VERSION}-${OC_PKG_VARIANT}"
readonly PKG_KEXT_VIRTUALSMC="VirtualSMC-${KEXT_VIRTUALSMC_VERSION}-${OC_PKG_VARIANT}"
readonly PKG_KEXT_WHATEVERGREEN="WhateverGreen-${KEXT_WHATEVERGREEN_VERSION}-${OC_PKG_VARIANT}"
# Download package list
declare -ar PKG_DOWNLOAD_LIST=(
  # OpenCore
  "${OC_BASE_URL}/OpenCorePkg/releases/download/${OPENCORE_VERSION}/${PKG_OC}.zip"
  # OpenCore binary data
  "${OC_BASE_URL}/OcBinaryData/archive/${PKG_OC_BINDATA}.zip"
  # Kext
  "${OC_BASE_URL}/AppleALC/releases/download/${KEXT_APPLEALC_VERSION}/${PKG_KEXT_APPLEALC}.zip"
  "${OC_BASE_URL}/IntelMausi/releases/download/${KEXT_INTELMAUSI_VERSION}/${PKG_KEXT_INTELMAUSI}.zip"
  "${OC_BASE_URL}/Lilu/releases/download/${KEXT_LILU_VERSION}/${PKG_KEXT_LILU}.zip"
  "${OC_BASE_URL}/VirtualSMC/releases/download/${KEXT_VIRTUALSMC_VERSION}/${PKG_KEXT_VIRTUALSMC}.zip"
  "${OC_BASE_URL}/WhateverGreen/releases/download/${KEXT_WHATEVERGREEN_VERSION}/${PKG_KEXT_WHATEVERGREEN}.zip"
)
# Package list
declare -ar PKG_LIST=(
  # OpenCore
  "$PKG_OC"
  "$PKG_OC_BINDATA"
  # Kext
  "$PKG_KEXT_APPLEALC"
  "$PKG_KEXT_INTELMAUSI"
  "$PKG_KEXT_LILU"
  "$PKG_KEXT_VIRTUALSMC"
  "$PKG_KEXT_WHATEVERGREEN"
)
# Configuration
#
# GitHub repository content base URL
readonly GH_REPO_CONTENT_BASE_URL="https://raw.githubusercontent.com/vovinacci/OpenCore-ASUS-ROG-MAXIMUS-XI-HERO/master"
# ACPI SSDT
declare -ar ACPI_SSDT_DOWNLOAD_LIST=(
  "${GH_REPO_CONTENT_BASE_URL}/ACPI/SSDT-AWAC.aml"
  "${GH_REPO_CONTENT_BASE_URL}/ACPI/SSDT-EC-USBX.aml"
  "${GH_REPO_CONTENT_BASE_URL}/ACPI/SSDT-PLUG.aml"
  "${GH_REPO_CONTENT_BASE_URL}/ACPI/SSDT-PMC.aml"
)
# Additional Kexts
declare -Ar arr EXTRA_KEXTS_DOWNLOAD_LIST=(
  [USBMap.zip]="${GH_REPO_CONTENT_BASE_URL}/Kexts/USBMap.kext/Contents/Info.plist"
)
# OpenCore configuration
readonly OC_CONFIG_PLIST="${GH_REPO_CONTENT_BASE_URL}/OC/config.plist"

## Functions
# Print error message and exit
# Arguments:
#   Error message
fail() {
  (echo >&2 "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [FATAL]: $*")
  exit 1
}

# Perform sanity checks prior doing anything and print
# Globals:
#   LOCAL_RUN
#   OC_PKG_VARIANT
__preflight_checks() {
  # Check if OC_PKG_VARIANT is set correctly
  [[ $OC_PKG_VARIANT =~ ^(DEBUG|RELEASE)$ ]] ||
    fail "Unsupported OpenCore package variant \"${OC_PKG_VARIANT}\"." \
      "OC_PKG_VARIANT should be set to \"DEBUG\" or \"RELEASE\"."
  echo "OpenCore package variant: \"${OC_PKG_VARIANT}\"."
  # Check if local run is preferred
  [[ $LOCAL_RUN == 0 ]] ||
    echo "Local run: Don't download Kexts and config.plist."
}

# Download all ACPI SSDT to 'ACPI' directory in TMP_DIR
# Globals:
#   ACPI_SSDT_DOWNLOAD_LIST
#   TMP_DIR
download_acpi_ssdt() {
  echo "Downloading ACPI SSDTs..."
  mkdir -p "${TMP_DIR}/ACPI"
  for i in "${ACPI_SSDT_DOWNLOAD_LIST[@]}"; do
    wget -nv -c -P "${TMP_DIR}/ACPI/" "$i"
  done
}

# Download extra Kexts to 'Kexts' directory in TMP_DIR
# Globals:
#   EXTRA_KEXTS_DOWNLOAD_LIST
#   TMP_DIR
download_extra_kexts() {
  if [[ $LOCAL_RUN == 0 ]]; then
    echo "Downloading extra Kexts..."
    for k in "${!EXTRA_KEXTS_DOWNLOAD_LIST[@]}"; do
      wget -nv -c --cut-dirs=5 -nH -P "${TMP_DIR}/Kexts/${k}" -r -np "${EXTRA_KEXTS_DOWNLOAD_LIST[$k]}"
    done
  else
    echo "Copying extra Kexts..."
    cp -rv "${BASE_DIR}/Kexts/" "${TMP_DIR}/"
  fi
}

# Download OpenCore 'config.plist' to TMP_DIR
# Globals:
#   BASE_DIR
#   OC_CONFIG_PLIST
#   TMP_DIR
download_oc_config() {
  if [[ $LOCAL_RUN == 0 ]]; then
    echo "Downloading config.plist..."
    wget -nv -c -P "${TMP_DIR}/" "${OC_CONFIG_PLIST}"
  else
    echo "Copying config.plist..."
    cp -v "${BASE_DIR}/OC/config.plist" "${TMP_DIR}/"
  fi
}

# Download all required packages to TMP_DIR
# Globals:
#   PKG_DOWNLOAD_LIST
#   TMP_DIR
download_pkg() {
  echo "Downloading packages..."
  for i in "${PKG_DOWNLOAD_LIST[@]}"; do
    wget -nv -c -P "${TMP_DIR}" "$i"
  done
}

# Unarchive all downloaded packages in TMP_DIR and delete archives
# Globals:
#   PKG_LIST
#   TMP_DIR
unarchive_pkg() {
  echo "Unarchiving packages..."
  pushd "${TMP_DIR}" >/dev/null || fail "Cannot 'pushd ${TMP_DIR}'"
  for i in "${PKG_LIST[@]}"; do
    unzip -q "${i}.zip" -d "${i}"
  done
  popd >/dev/null
}

# Create EFI directory structure
# Globals:
#   BASE_EFI_DIR
#   BASE_OC_DIR
create_efi_dirs() {
  echo "Deleting EFI directory..."
  rm -rfv "${BASE_EFI_DIR}"
  echo "Creating EFI directory structure..."
  mkdir -pv "${BASE_EFI_DIR}"
  mkdir -pv "${BASE_EFI_DIR}"/BOOT
  mkdir -pv "${BASE_OC_DIR}"
  mkdir -pv "${BASE_OC_DIR}"/{ACPI,Bootstrap,Drivers,Kexts,Resources,Tools}
  mkdir -pv "${BASE_OC_DIR}"/Resources/{Audio,Font,Image,Label}
}

# Copy OpenCore binaries to 'EFI' directory
# Globals:
#   BASE_EFI_DIR
#   BASE_OC_DIR
#   PKG_OC
#   TMP_DIR
copy_oc_bin() {
  echo "Copying OpenCore binaries to EFI directories..."
  cp -v "${TMP_DIR}/${PKG_OC}/X64/EFI/BOOT/BOOTx64.efi" "${BASE_EFI_DIR}"/BOOT/
  cp -v "${TMP_DIR}/${PKG_OC}/X64/EFI/OC/OpenCore.efi" "${BASE_OC_DIR}"/
  cp -v "${TMP_DIR}/${PKG_OC}/X64/EFI/OC/Bootstrap/Bootstrap.efi" "${BASE_OC_DIR}"/Bootstrap/
  cp -v "${TMP_DIR}/${PKG_OC}/X64/EFI/OC/Tools/"{OpenControl.efi,OpenShell.efi,ResetSystem.efi} "${BASE_OC_DIR}"/Tools/
}

# Copy OpenCore configuration template to 'EFI' directory
# Globals:
#   BASE_OC_DIR
#   TMP_DIR
copy_oc_config() {
  echo "Copying OpenCore configuration template..."
  cp -v "${TMP_DIR}/config.plist" "${BASE_OC_DIR}"/
}

# Copy ACPI SSDT to 'EFI/ACPI' directory
# Globals:
#   BASE_OC_DIR
#   TMP_DIR
copy_acpi_ssdt() {
  echo "Copying ACPI SSTDs to EFI/ACPI directory..."
  cp -rv "${TMP_DIR}/ACPI"/{SSDT-AWAC.aml,SSDT-EC-USBX.aml,SSDT-PLUG.aml,SSDT-PMC.aml} "${BASE_OC_DIR}"/ACPI
}

# Copy OpenCore drivers to 'EFI/Drivers' directory
# Globals:
#   BASE_OC_DIR
#   PKG_OC
#   PKG_OC_BINDATA
#   TMP_DIR
copy_oc_drivers() {
  echo "Copying OpenCore drivers to EFI/Drivers directory..."
  cp -v "${TMP_DIR}/${PKG_OC}/X64/EFI/OC/Drivers/"{OpenCanopy.efi,OpenRuntime.efi} "${BASE_OC_DIR}"/Drivers/
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Drivers/HfsPlus.efi" "${BASE_OC_DIR}"/Drivers/
}

# Copy Kexts to EFI directory
# Globals:
#   BASE_OC_DIR
#   PKG_KEXT_APPLEALC
#   PKG_KEXT_INTELMAUSI
#   PKG_KEXT_LILU
#   PKG_KEXT_VIRTUALSMC
#   PKG_KEXT_WHATEVERGREEN
#   TMP_DIR
copy_kexts() {
  echo "Copying Kexts to EFI/Kexts directory..."
  cp -vr "${TMP_DIR}/Kexts" "${BASE_OC_DIR}"/
  cp -vr "${TMP_DIR}/${PKG_KEXT_APPLEALC}"/AppleALC.kext "${BASE_OC_DIR}"/Kexts/
  cp -vr "${TMP_DIR}/${PKG_KEXT_INTELMAUSI}"/IntelMausi.kext "${BASE_OC_DIR}"/Kexts/
  cp -vr "${TMP_DIR}/${PKG_KEXT_LILU}"/Lilu.kext "${BASE_OC_DIR}"/Kexts/
  cp -vr "${TMP_DIR}/${PKG_KEXT_VIRTUALSMC}"/Kexts/{SMCProcessor.kext,SMCSuperIO.kext,VirtualSMC.kext} "${BASE_OC_DIR}"/Kexts/
  cp -vr "${TMP_DIR}/${PKG_KEXT_WHATEVERGREEN}"/WhateverGreen.kext "${BASE_OC_DIR}"/Kexts/
}

# Copy OpenCore resource files to 'EFI/Resources/{Audio,Font,Image,Label}' directories
# Globals:
#   BASE_OC_DIR
#   PKG_OC_BINDATA
#   TMP_DIR
copy_oc_resources() {
  echo "Copying OpenCore resource files to EFI/Resources directories..."
  # Enable globbing for file copy
  set +f
  # Copy files
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Resources/Audio/"{AXEFIAudio_Beep.mp3,AXEFIAudio_Click.mp3,AXEFIAudio_VoiceOver_Boot.mp3} \
    "${BASE_OC_DIR}"/Resources/Audio/
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Resources/Audio/OCEFIAudio_VoiceOver_Boot.mp3" "${BASE_OC_DIR}"/Resources/Audio/
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Resources/Audio/"AXEFIAudio_en_*.mp3 "${BASE_OC_DIR}"/Resources/Audio/
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Resources/Audio/"OCEFIAudio_en_*.mp3 "${BASE_OC_DIR}"/Resources/Audio/
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Resources/Font/"* "${BASE_OC_DIR}"/Resources/Font/
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Resources/Image/"* "${BASE_OC_DIR}"/Resources/Image/
  cp -v "${TMP_DIR}/${PKG_OC_BINDATA}/OcBinaryData-master/Resources/Label/"* "${BASE_OC_DIR}"/Resources/Label/
  # Disable globbing back
  set -f
}

## Start the ball
__preflight_checks
# Download all required data
download_acpi_ssdt
download_extra_kexts
download_oc_config
download_pkg
unarchive_pkg
# Create EFI folder
create_efi_dirs
copy_oc_bin
copy_oc_config
copy_acpi_ssdt
copy_oc_drivers
copy_kexts
copy_oc_resources

# EOF
