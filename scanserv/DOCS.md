# Brother Scanner

Web scanning for a USB Brother scanner (tested target: DCP-1510) plugged into the
Home Assistant host. It runs [scanservjs](https://github.com/sbs20/scanservjs) on top
of SANE with the open-source [brscan](https://github.com/peloycosta/brscan) backend,
so no proprietary Brother binaries are needed and it works on aarch64 (Raspberry Pi).

## Use

Open **Scanner** in the Home Assistant sidebar. Pick a mode and resolution, press
**Scan**, then download the PDF or JPEG from the file list.

Scans are saved to `/share/scans` on the Home Assistant host. With the Samba add-on
they appear under `\\<home-assistant>\share\scans`.

## Sharing the USB device with the CUPS printer add-on

The DCP-1510 exposes the printer and the scanner as separate USB interfaces, so the
CUPS add-on and this add-on can run side by side. Avoid printing and scanning at the
same moment.

## Options

| option | default | meaning |
|---|---|---|
| `output_dir` | `/share/scans` | where finished scans are stored (must be under `/share`) |
| `ocr_lang` | `eng` | Tesseract language for the OCR output formats (only `eng` is installed) |
| `debug` | `false` | verbose SANE/brother backend logging in the add-on log |
| `nas_copy` | `false` | also copy every finished scan to a Samba (SMB) share |
| `nas_share` | `//192.168.68.95/warren` | the share, as `//host/share` |
| `nas_path` | `documents/scans` | folder inside the share; created if missing |
| `nas_username` | `warren` | Samba login |
| `nas_password` | (empty) | Samba password; stored only in the add-on options |

## Copy to a NAS (optional)

Turn on `nas_copy` and fill in `nas_password` (and the other `nas_*` options if they
differ). Each finished scan is still saved to `output_dir` first, then copied to the
share with `smbclient`. A failed copy is written to the add-on log and does not fail
the scan; the add-on log also says at startup whether the share was reachable.

## Direct LAN access (optional)

The web UI is only reachable through Home Assistant by default. To open it without a
Home Assistant login, set a host port for `8080/tcp` under **Network**. scanservjs has
no authentication, so anyone on the LAN can then scan and delete scans.

## Troubleshooting

- *No scanner in the list*: check the add-on log for the `lsusb` and `scanimage -L`
  output, then restart the add-on. Unplugging and replugging the USB cable also resets
  the scanner.
- Turn on `debug` and restart to get the backend trace.
