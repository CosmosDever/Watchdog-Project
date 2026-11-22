"""Resolve QEMU (and friends) from the MSYS2 ucrt64 package index, download, hash-check, extract.

Each package's SHA-256 comes from the signed repo database; we verify every file against it.
Usage:  python -I fetch_qemu.py <downloads_dir> <output_dir> [root_pkg ...]
Default roots: the QEMU emulator and the SPICE remote-viewer.
"""
import hashlib
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.request

REPO = "https://repo.msys2.org/mingw/ucrt64/"
DEFAULT_ROOTS = ["mingw-w64-ucrt-x86_64-qemu", "mingw-w64-ucrt-x86_64-virt-viewer"]
MAX_DOWNLOAD = 2_500_000_000
TAR = r"C:\Windows\System32\tar.exe"


def parse(text):
    fields, key = {}, None
    for line in text.splitlines():
        if line.startswith("%") and line.endswith("%"):
            key = line.strip("%")
            fields[key] = []
        elif line and key:
            fields[key].append(line)
    return fields


def bare(dep):
    return re.split(r"[<>=]", dep, 1)[0].strip()


def load(db_path):
    packages, provides = {}, {}
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([TAR, "-xf", str(db_path), "-C", tmp], check=True)
        for desc in pathlib.Path(tmp).glob("*/desc"):
            item = parse(desc.read_text(encoding="utf-8"))
            name = item["NAME"][0]
            packages[name] = item
            provides.setdefault(name, name)
            for value in item.get("PROVIDES", []):
                provides.setdefault(bare(value), name)
    return packages, provides


def closure(packages, provides, roots):
    seen, stack, missing = {}, list(roots), []
    while stack:
        wanted = bare(stack.pop())
        name = provides.get(wanted)
        if not name:
            missing.append(wanted)
        elif name not in seen:
            seen[name] = packages[name]
            stack.extend(packages[name].get("DEPENDS", []))
    return seen, missing


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    downloads, output = map(pathlib.Path, sys.argv[1:3])
    roots = sys.argv[3:] or DEFAULT_ROOTS
    downloads.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)

    db = downloads / "ucrt64.db"
    if not db.exists():
        urllib.request.urlretrieve(REPO + "ucrt64.db", db)
    packages, provides = load(db)
    selected, missing = closure(packages, provides, roots)
    if missing:
        sys.exit(f"Unresolved dependencies: {sorted(set(missing))}")
    total = sum(int(p["CSIZE"][0]) for p in selected.values())
    print(f"{len(selected)} packages, {total / 1e6:.0f} MB", flush=True)
    if total > MAX_DOWNLOAD:
        sys.exit("Download is larger than the safety limit.")

    for item in sorted(selected.values(), key=lambda p: p["NAME"][0]):
        filename, expected = item["FILENAME"][0], item["SHA256SUM"][0]
        target = downloads / filename
        if not target.exists() or sha256(target) != expected:
            urllib.request.urlretrieve(REPO + filename, target)
        if sha256(target) != expected:
            target.unlink()
            sys.exit(f"HASH MISMATCH: {filename}")
        subprocess.run([TAR, "-xf", str(target), "-C", str(output), "--exclude=.*"],
                       capture_output=True, text=True)
    print("OK: packages verified and extracted", flush=True)


if __name__ == "__main__":
    main()
