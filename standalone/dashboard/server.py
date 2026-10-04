#!/usr/bin/env python3
"""Small LAN dashboard for the print-scan container: printer, scanner, recent scans, print upload."""
import json
import os
import re
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

QUEUE = os.environ.get("PRINT_SCAN_QUEUE", "Brother_DCP_1510")
PORT = int(os.environ.get("PRINT_SCAN_DASH_PORT", "80"))
SCAN_DIR = Path(os.environ.get("SCANSERV_OUTPUT_DIR", "/var/lib/scanservjs/output"))
NAS_SHARE = os.environ.get("SCANSERV_NAS_SHARE", "")
NAS_PATH = os.environ.get("SCANSERV_NAS_PATH", "")
NAS_AUTH = os.environ.get("SCANSERV_NAS_AUTH", "/etc/print-scan/nas.auth")
MAX_UPLOAD = 50 * 1024 * 1024
STATIC = Path(__file__).resolve().parent

_cache = {}
_cache_lock = threading.Lock()


def run(args, timeout=15):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, "", str(e)


def cached(key, ttl, fn):
    now = time.monotonic()
    with _cache_lock:
        hit = _cache.get(key)
        if hit and now - hit[0] < ttl:
            return hit[1]
    value = fn()
    with _cache_lock:
        _cache[key] = (now, value)
    return value


def printer_status():
    code, out, _ = run(["lpstat", "-p", QUEUE])
    if code != 0:
        return {"name": QUEUE, "exists": False}
    lines = out.splitlines()
    first = lines[0] if lines else ""
    state = "idle" if " is idle" in first else "printing" if "now printing" in first else "disabled" if "disabled" in first else "unknown"
    message = " ".join(line.strip() for line in lines[1:] if line.strip())
    _, acc, _ = run(["lpstat", "-a", QUEUE])
    _, dev, _ = run(["lpstat", "-v", QUEUE])
    _, jobs_out, _ = run(["lpstat", "-o", QUEUE])
    jobs = []
    for line in jobs_out.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            jobs.append({"id": parts[0], "user": parts[1], "size": parts[2], "when": " ".join(parts[3:])})
    return {
        "name": QUEUE,
        "exists": True,
        "state": state,
        "summary": first,
        "detail": message,
        "accepting": "not accepting" not in acc,
        "device": dev.split(": ", 1)[1].strip() if ": " in dev else "",
        "jobs": jobs,
    }


def usb_devices():
    code, out, _ = run(["lsusb", "-d", "04f9:"])
    return [line.strip() for line in out.splitlines() if line.strip()] if code == 0 else []


def sane_devices():
    code, out, _ = run(["scanimage", "-L"], timeout=60)
    return [line.strip() for line in out.splitlines() if "brother" in line.lower()]


def last_scans(limit=5):
    try:
        files = [p for p in SCAN_DIR.iterdir() if p.is_file() and not p.name.startswith(".")]
    except OSError:
        return []
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return [{"name": p.name, "size": p.stat().st_size, "mtime": int(p.stat().st_mtime)} for p in files[:limit]]


SMB_LINE = re.compile(r"^\s{2}(.+?)\s+([A-Z]*)\s+(\d+)\s+(\w{3} \w{3}\s+\d+ \d\d:\d\d:\d\d \d{4})$")


def nas_scans(limit=10):
    if not NAS_SHARE:
        return {"configured": False}
    code, out, err = run(["smbclient", NAS_SHARE, "-A", NAS_AUTH, "-D", NAS_PATH or "/", "-c", "ls"], timeout=20)
    if code != 0:
        return {"configured": True, "ok": False, "error": (err or out).strip().splitlines()[-1:] or ["smbclient failed"],
                "location": f"{NAS_SHARE}/{NAS_PATH}"}
    files = []
    for line in out.splitlines():
        m = SMB_LINE.match(line)
        if not m or "D" in m.group(2) or m.group(1) in (".", ".."):
            continue
        try:
            ts = int(time.mktime(time.strptime(re.sub(r"\s+", " ", m.group(4)), "%a %b %d %H:%M:%S %Y")))
        except ValueError:
            ts = 0
        files.append({"name": m.group(1), "size": int(m.group(3)), "mtime": ts})
    files.sort(key=lambda f: f["mtime"], reverse=True)
    return {"configured": True, "ok": True, "files": files[:limit], "count": len(files), "location": f"{NAS_SHARE}/{NAS_PATH}"}


def status():
    usb = usb_devices()
    return {
        "time": int(time.time()),
        "printer": printer_status(),
        "usb": usb,
        "scanner": {"present": bool(usb), "sane": cached("sane", 60, sane_devices) if usb else [], "recent": last_scans()},
        "nas": cached("nas", 60, nas_scans),
    }


def safe_name(name):
    name = os.path.basename(name or "upload")
    return re.sub(r"[^A-Za-z0-9._ -]", "_", name)[:120] or "upload"


class Handler(BaseHTTPRequestHandler):
    server_version = "print-scan-dash"

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)

    def send_json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            data = (STATIC / "index.html").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif self.path == "/api/status":
            self.send_json(200, status())
        elif self.path == "/healthz":
            self.send_json(200, {"ok": True})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/print":
            self.send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_UPLOAD:
            self.send_json(413 if length > MAX_UPLOAD else 400, {"error": f"file must be 1 byte to {MAX_UPLOAD // 1048576} MB"})
            return
        name = safe_name(unquote(self.headers.get("X-Filename", "")))
        try:
            copies = max(1, min(int(self.headers.get("X-Copies", "1")), 20))
        except ValueError:
            copies = 1
        suffix = Path(name).suffix[:10]
        with tempfile.NamedTemporaryFile(prefix="print-", suffix=suffix, delete=True) as tmp:
            remaining = length
            while remaining:
                chunk = self.rfile.read(min(remaining, 1 << 16))
                if not chunk:
                    break
                tmp.write(chunk)
                remaining -= len(chunk)
            tmp.flush()
            if remaining:
                self.send_json(400, {"error": "upload truncated"})
                return
            code, out, err = run(["lp", "-d", QUEUE, "-n", str(copies), "-t", name, tmp.name], timeout=60)
        if code != 0:
            self.send_json(500, {"error": (err or out).strip() or "lp failed"})
            return
        m = re.search(r"request id is (\S+)", out)
        self.send_json(200, {"ok": True, "job": m.group(1) if m else out.strip(), "name": name, "copies": copies})


if __name__ == "__main__":
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
