# Home Assistant add-on: Brother Scanner

A Home Assistant add-on repository with one add-on, `scanserv/`: web scanning
(scanservjs + SANE) for USB Brother scanners using the open-source brscan backend.
It is built for `aarch64` and `amd64`.

## Install

1. Settings → Add-ons → Add-on Store → ⋮ → Repositories → add this repository's URL.
2. Install **Brother Scanner**, start it, and turn on **Show in sidebar**.

See [scanserv/DOCS.md](scanserv/DOCS.md) for details.

## Pinned upstreams

- brscan: `peloycosta/brscan` @ `f49d1e56b342ca66534d2be1924f678a974281c6` (built from source)
- scanservjs: `v3.3.0` release `.deb` (sha256 verified at build time)
