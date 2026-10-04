#!/usr/bin/with-contenv bashio
set -e

OUTPUT_DIR="$(bashio::config 'output_dir' || true)"
[[ -z "${OUTPUT_DIR}" || "${OUTPUT_DIR}" == "null" ]] && OUTPUT_DIR=/share/scans
OCR_LANG="$(bashio::config 'ocr_lang' || true)"
[[ -z "${OCR_LANG}" || "${OCR_LANG}" == "null" ]] && OCR_LANG=eng
export SCANSERV_OUTPUT_DIR="${OUTPUT_DIR}" OCR_LANG
mkdir -p "${OUTPUT_DIR}"

if bashio::config.true 'debug'; then
    export SANE_DEBUG_BROTHER=30
    export SANE_DEBUG_DLL=5
fi

# Device ids embed the USB bus/device number, which changes on replug.
rm -f /var/lib/scanservjs/devices.json

bashio::log.info "USB devices visible to the add-on:"
lsusb || bashio::log.warning "lsusb failed"

bashio::log.info "SANE devices:"
scanimage -L || bashio::log.warning "scanimage -L failed"

bashio::log.info "Scans are saved to ${OUTPUT_DIR}"

if bashio::config.true 'nas_copy'; then
    NAS_SHARE="$(bashio::config 'nas_share')"
    NAS_PATH="$(bashio::config 'nas_path' || true)"
    [[ "${NAS_PATH}" == "null" ]] && NAS_PATH=""
    NAS_PATH="${NAS_PATH#/}"
    NAS_PATH="${NAS_PATH%/}"
    NAS_USER="$(bashio::config 'nas_username' || true)"
    NAS_PASS="$(bashio::config 'nas_password' || true)"
    if [[ -z "${NAS_USER}" || "${NAS_USER}" == "null" || -z "${NAS_PASS}" || "${NAS_PASS}" == "null" ]]; then
        bashio::log.warning "nas_copy is on but nas_username/nas_password are not set; NAS copy disabled"
    else
        NAS_AUTH=/tmp/nas.auth
        (umask 077 && printf 'username=%s\npassword=%s\n' "${NAS_USER}" "${NAS_PASS}" > "${NAS_AUTH}")
        unset NAS_PASS
        # smbclient mkdir is not recursive: create each level, ignoring ones that exist.
        dir=""
        IFS='/' read -ra parts <<< "${NAS_PATH}"
        for part in "${parts[@]}"; do
            [[ -z "${part}" ]] && continue
            dir="${dir:+${dir}/}${part}"
            smbclient "${NAS_SHARE}" -A "${NAS_AUTH}" -c "mkdir \"${dir}\"" > /dev/null 2>&1 || true
        done
        if smbclient "${NAS_SHARE}" -A "${NAS_AUTH}" -D "${NAS_PATH:-/}" -c 'ls' > /dev/null 2>&1; then
            bashio::log.info "Scans are also copied to ${NAS_SHARE}/${NAS_PATH}"
        else
            bashio::log.warning "Cannot reach ${NAS_SHARE}/${NAS_PATH} now; each scan will still try to copy"
        fi
        export SCANSERV_NAS_SHARE="${NAS_SHARE}" SCANSERV_NAS_PATH="${NAS_PATH}" SCANSERV_NAS_AUTH="${NAS_AUTH}"
    fi
fi

cd /usr/lib/scanservjs
exec node ./server/server.js
