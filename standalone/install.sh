#!/bin/bash
# Configures a Debian 12 container as a print + scan server for a USB Brother DCP-1510.
# Expects the packages, brscan4, scanservjs and AirSane to be installed already (see README.md).
# Safe to re-run.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
QUEUE=Brother_DCP_1510

install -d -m 0755 /etc/print-scan /opt/print-scan/dashboard
install -m 0644 "$SRC/print-scan.default" /etc/default/print-scan

getent group nasread >/dev/null || groupadd --system nasread
id printdash >/dev/null 2>&1 || useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin printdash
usermod -aG nasread scanservjs
[[ -f /etc/print-scan/nas.auth ]] && chown root:nasread /etc/print-scan/nas.auth && chmod 0640 /etc/print-scan/nas.auth

# CUPS: shared on the LAN, advertised over DNS-SD for AirPrint / IPP Everywhere.
cupsctl --share-printers --remote-any --remote-admin
grep -q '^ServerAlias \*' /etc/cups/cupsd.conf || sed -i '1i ServerAlias *' /etc/cups/cupsd.conf
systemctl restart cups
if ! lpstat -p "$QUEUE" >/dev/null 2>&1; then
    # Placeholder URI; print-scan-usbwatch swaps in the real one (with serial) on first plug-in.
    lpadmin -p "$QUEUE" -E -v 'usb://Brother/DCP-1510%20series' \
        -m drv:///brlaser.drv/br1510.ppd -D 'Brother DCP-1510' -L "Jamine's office" \
        -o printer-is-shared=true -o PageSize=A4 -o printer-error-policy=retry-job
fi
lpadmin -d "$QUEUE"
cupsenable "$QUEUE"
cupsaccept "$QUEUE"

# SANE: only the Brother backend, so device probing stays fast.
printf 'brother4\n' > /etc/sane.d/dll.conf
rm -f /etc/sane.d/dll.d/*

# scanservjs: A4 clamp + NAS copy hooks.
install -m 0644 "$SRC/../scanserv/config.local.js" /etc/scanservjs/config.local.js
install -d /etc/systemd/system/scanservjs.service.d
install -m 0644 "$SRC/systemd/scanservjs-override.conf" /etc/systemd/system/scanservjs.service.d/print-scan.conf

# AirSane.
install -d /etc/airsane
install -m 0644 "$SRC/airsane-options.conf" /etc/airsane/options.conf

# Watcher, health check, dashboard.
install -m 0755 "$SRC/print-scan-usbwatch" /usr/local/sbin/print-scan-usbwatch
install -m 0755 "$SRC/print-scan-check" /usr/local/bin/print-scan-check
install -m 0644 "$SRC/dashboard/server.py" "$SRC/dashboard/index.html" /opt/print-scan/dashboard/
install -m 0644 "$SRC/systemd/print-scan-usbwatch.service" "$SRC/systemd/print-scan-dash.service" /etc/systemd/system/

# The NAS folder may not exist yet; smbclient mkdir fails harmlessly when it does.
. /etc/default/print-scan
if [[ -r "$SCANSERV_NAS_AUTH" ]]; then
    smbclient "$SCANSERV_NAS_SHARE" -A "$SCANSERV_NAS_AUTH" -c "mkdir \"$SCANSERV_NAS_PATH\"" >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl enable --now avahi-daemon cups airsaned scanservjs print-scan-usbwatch print-scan-dash
systemctl restart airsaned scanservjs print-scan-usbwatch print-scan-dash
echo "install done"
