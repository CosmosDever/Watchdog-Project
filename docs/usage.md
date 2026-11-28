# Daily use

## Start

Plug in the drive and from its root run:

- Windows: `.\hodo-run.bat` (in PowerShell) or double-click it.
- macOS: `bash /Volumes/HODOPHYLAX/hodo-run.command` from any folder, or right-click the file → Open.

`hodo-run` checks the machine, asks whether to also start the local AI, then opens Kali.
You can also start pieces alone with the `Start ...` launchers.

## First time inside Kali (run once)

The guest install runs **inside Kali one time** — the host cannot write into the running
VM's own disk, so the setup has to execute in the guest. After this one time it is
automatic: a login hook refreshes the agent, its commands, and the rules from the drive on
every terminal, so you never run setup again, even after the project updates.

Log in as `kali` / `kali`, open a terminal, and run:

```bash
passwd                                                                                      # change the default password
curl -fsS -o /tmp/d.sh tftp://10.0.2.2/setup-desktop.sh && bash /tmp/d.sh && sudo reboot     # two-way clipboard + screen resize
curl -fsS -o /tmp/s.sh tftp://10.0.2.2/setup-ai.sh && bash /tmp/s.sh                          # install the Hodophylax agent + auto-update hook
```

The `10.0.2.2` files are served from the drive by QEMU whenever the VM runs, so these always
work. Start the AI launcher on the host first if you want the local model reachable.

> Want zero typing even on the first boot? The provisioner can inject this with
> `virt-customize --firstboot` at build time (needs libguestfs on the build machine). It is
> not enabled by default — this one-time in-guest run is the simplest, most portable path.

### Apple Silicon first install

Mac uses the `kali-arm64` installer. After choosing **Install** the main window stays black.
In the QEMU menu bar choose **View > serial0** to see the installer. If it returns to the
installer menu after finishing, close the QEMU window and run `hodo-run` again. The
launcher then boots the installed disk without the ISO.

### Clipboard on Mac

Copy and paste work both ways in GUI mode after the one-time `setup-desktop.sh` step above
and a Kali reboot. Use Command+C on the Mac and Ctrl+Shift+V in a Kali terminal, or Ctrl+Shift+C
in Kali and Command+V on the Mac.

## Share data between Windows and Mac

Windows runs Kali `amd64` and Apple Silicon runs Kali `arm64`, so each keeps its own OS disk.
Work files live on one shared disk, `shared/data.qcow2`, mounted at `/data`. The launcher
attaches it automatically. Run this **once inside each Kali VM** after starting it with
`hodo-run`:

```bash
curl -fsS -o /tmp/data.sh tftp://10.0.2.2/setup-data.sh && bash /tmp/data.sh
```

`~/engagement` then points to `/data/engagement`. Existing engagement files are copied without
overwriting, and the old folder is kept as `~/engagement.local-backup-<time>`.

- Keep architecture-specific programs out of `/data`; install tools separately in each VM.
- Only one VM can use the shared disk at a time. Shut Kali down before moving the drive.

## Run an engagement

```bash
new-engagement acme-web                 # makes ~/engagement/acme-web/ with scope.md + report/
nano ~/engagement/acme-web/scope.md     # fill in authorization and in-scope targets
cd ~/engagement/acme-web && hodo  # start the agent from inside the job folder
```

Tell the agent what to do within scope, e.g. "read ./scope.md and run the full engagement".
It works only on the targets in `scope.md`. For a web target it first runs `web-recon <url>`
— a helper that fingerprints the app and pulls the real `/api` and `/rest` routes out of the
JavaScript bundles (single-page apps hide them there), saving a map to `report/recon_map.md`
so the agent does not have to guess endpoints. You can run `web-recon <url>` yourself too.

## Troubleshooting

**The agent seems frozen / nothing happens.** Check the `start-llm` window. With a model
served through the tool-call proxy it prints a line per request, e.g.
`[toolshim] POST ... stream=True tools=11` then `[toolshim] backend 200 in 5.8s, ...`.
If you see those, it is working — a local model is just slow on the first, long turn. If the
GPU sits at 0% in Task Manager while VRAM is still used, generation already finished; the
proxy keeps the connection alive with keepalives so the agent no longer hangs waiting.

**`request (… tokens) exceeds the available context size (16384 tokens)`.** The conversation
plus tool schemas outgrew the model's context window. Either raise it or trim:

- Start the model with a bigger window (a quantized KV cache keeps it inside 8 GB VRAM):
  `./launcher/start-llm.ps1 -ContextSize 32768` (this is now the default) or `-ContextSize 49152`.
- In the agent, run `/compact` or `/new` periodically, and split long work into shorter
  sessions instead of one endless thread.
- Cloud models (Claude) have far larger context and avoid this entirely.

**The agent chats instead of acting, or suggests wrong commands.** Small local 7–9B models
are weak at driving tools. Prefer **Qwen** over WhiteRabbitNeo for the agent loop (Qwen emits
native tool calls), be directive ("Proceed. Run step 1 now."), and for real multi-step work
use a cloud model via [docs/configure.md](configure.md). WhiteRabbitNeo is better as a
security-knowledge model you ask specific questions, not as the driver.

## Shut down safely

The drive is exFAT (no journaling), so always:

1. `sudo poweroff` inside Kali (or type `S` in the launcher window).
2. Stop the AI window.
3. Eject the drive before unplugging: double-click **`Eject Drive.bat`** (Windows) or
   **`Eject Drive.command`** (macOS) at the drive root, or eject from the OS. These flush
   pending writes and safely remove the drive; if one reports it could not eject, a Kali or AI
   window is still open — close it and run the eject launcher again.
