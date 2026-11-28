# Building a Hodophylax drive

You need a USB SSD (≈400 GB+) and 30–60 minutes for the first download.

## 1. Prepare an exFAT drive

Format the drive (or a partition) as **exFAT** with the label `HODOPHYLAX`. exFAT is
read/write on both Windows and macOS.

- Windows: Disk Management, or `Format-Volume -DriveLetter X -FileSystem exFAT -NewFileSystemLabel HODOPHYLAX`.
- macOS: Disk Utility → Erase → Format: ExFAT, Name: HODOPHYLAX.

> Formatting erases the target. Double-check the drive. Hodophylax never formats for you.

## 2. Copy the files

Copy the contents of this repo's **`drive/`** folder to the **root** of the drive. The root
should then contain `hodo-run.bat`, `hodo-run.command`, and the `launcher/`,
`setup/`, `config/`, and `llm/` folders.

To change the guest OS or the models, edit `config/hodophylax.json` on the drive now (defaults
to Kali amd64 + Qwen3.5-9B and WhiteRabbitNeo). See [configure.md](configure.md).

## 3. Download the heavy parts

Plug the drive into a machine and run **`hodo-run`** from its root. The first time, it
sees the drive is empty and **offers to download and verify Kali, the runtimes, and the
models** — say yes. Or run the provisioner directly:

```powershell
# Windows — needs Python installed (for the QEMU step). Everything else is fetched for you.
.\setup\provision.ps1
```

```bash
# macOS / Linux — then run `brew install qemu` once (the launcher offers it).
bash setup/provision-mac.sh
```

Every download is checked against a known SHA-256; a mismatch aborts.

## 4. Use it

Run `hodo-run` again and follow [usage.md](usage.md), including the one-time in-guest
setup on Kali's first boot.

## Status

The provisioner is new and Windows-first. It reuses the exact, verified download URLs and
hashes from a working build, but a fresh end-to-end provision has not been run in CI yet —
review it and watch the first run. The launcher scripts and the tool-call proxy are tested.
