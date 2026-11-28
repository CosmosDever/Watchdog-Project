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

## 4. First boot and daily use

Three parts — host, guest once, then work:

1. **Host:** run `hodo-run` from the drive root → it checks the machine, offers the local AI,
   and boots Kali.
2. **Guest (first boot, once per Kali VM):** log in as `kali` / `kali`, open a terminal, and
   run the single setup command:

   ```bash
   curl -fsS -o /tmp/setup.sh tftp://10.0.2.2/hodo-setup && bash /tmp/setup.sh
   ```

   It installs the agent (`hodo`, `target`), mounts the shared `/data` disk, sets up clipboard,
   and reboots. Run it once on the Windows (amd64) Kali and once on the Mac (arm64) Kali. Also
   run `passwd` to change the default password.
3. **Work:** `target <ip-or-url> <name>` scaffolds an engagement folder and opens the agent in
   it. Shut down safely with the **`Eject Drive`** launcher before unplugging.

See [usage.md](usage.md) for the Apple Silicon first-install note, the shared `/data` disk, and
troubleshooting.

## Status

The provisioner is new and Windows-first. It reuses the exact, verified download URLs and
hashes from a working build, but a fresh end-to-end provision has not been run in CI yet —
review it and watch the first run. The launcher scripts and the tool-call proxy are tested.
