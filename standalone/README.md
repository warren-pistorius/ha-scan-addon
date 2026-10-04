# Standalone print + scan server (Proxmox LXC)

The same Brother DCP-1510 setup as the Home Assistant add-on, as a plain Debian 12 container
with the printer on USB: CUPS + brlaser shared over AirPrint / IPP Everywhere, Brother's brscan4
SANE backend, AirSane (eSCL / AirScan), scanservjs, and a small dashboard.

| Port | Service |
|------|---------|
| 80   | dashboard (`print-scan-dash`) |
| 631  | CUPS |
| 8080 | scanservjs |
| 8090 | AirSane |

## Container

Privileged, so the USB device nodes keep their host ownership and libusb can detach the
host's `usblp` driver. The whole USB tree is bind-mounted, so a replug (new device number)
needs no config change. Lines appended to `/etc/pve/lxc/<ctid>.conf`:

```
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
```

## Install

```sh
apt-get install -y --no-install-recommends cups cups-client cups-bsd cups-filters \
  printer-driver-brlaser avahi-daemon avahi-utils libnss-mdns sane-utils libsane1 usbutils \
  smbclient curl ca-certificates git build-essential cmake pkg-config libsane-dev libjpeg-dev \
  libpng-dev libavahi-client-dev libusb-1.0-0-dev nodejs imagemagick ghostscript \
  tesseract-ocr tesseract-ocr-eng python3

curl -fsSLO https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb
curl -fsSLO https://github.com/sbs20/scanservjs/releases/download/v3.3.0/scanservjs_3.3.0-1_all.deb
echo "d57a26fa6472651ac5c780a4057ae944361cfcaa7c0b6d07a7856e7ef6b15f75  scanservjs_3.3.0-1_all.deb" | sha256sum -c -
apt-get install -y ./brscan4-0.4.11-1.amd64.deb ./scanservjs_3.3.0-1_all.deb

git init /usr/local/src/AirSane && cd /usr/local/src/AirSane
git fetch --depth 1 https://github.com/SimulPiscator/AirSane.git f420e2c26961329382cd68d359d565a24ecb25c6
git checkout --detach FETCH_HEAD
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build && cmake --install build
```

Put the NAS credentials in `/etc/print-scan/nas.auth` (smbclient auth-file format), copy this
directory and `../scanserv/config.local.js` into the container, and run `standalone/install.sh`.

## Pieces

- `print-scan-usbwatch` polls sysfs for vendor `04f9` (containers get no udev events). On a
  change it grants the `scanner` group access to the device node, points the CUPS queue at the
  printer's real `usb://` URI, drops scanservjs' cached device list and restarts AirSane and
  scanservjs.
- `print-scan-check` reports services, queue, USB device, `scanimage -L`, NAS and ports.
- `dashboard/` is a stdlib Python server: printer status and queue, scanner state, recent scans
  on the NAS, and a print upload (`POST /api/print`, raw body, `X-Filename` header). It has no
  authentication, so keep it on the LAN or behind an access list.
