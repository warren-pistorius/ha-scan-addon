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
cd /usr/lib/scanservjs
exec node ./server/server.js
