# Daily use

## Start

Plug in the drive and from its root run:

- Windows: `.\watchdog-run.bat` (in PowerShell) or double-click it.
- macOS: `cd /Volumes/WATCHDOG && bash watchdog-run.command`, or right-click the file → Open.

`watchdog-run` checks the machine, asks whether to also start the local AI, then opens Kali.
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
curl -fsS -o /tmp/s.sh tftp://10.0.2.2/setup-ai.sh && bash /tmp/s.sh                          # install the Watchdog agent + auto-update hook
```

The `10.0.2.2` files are served from the drive by QEMU whenever the VM runs, so these always
work. Start the AI launcher on the host first if you want the local model reachable.

> Want zero typing even on the first boot? The provisioner can inject this with
> `virt-customize --firstboot` at build time (needs libguestfs on the build machine). It is
> not enabled by default — this one-time in-guest run is the simplest, most portable path.

## Run an engagement

```bash
new-engagement acme-web                 # makes ~/engagement/acme-web/ with scope.md + report/
nano ~/engagement/acme-web/scope.md     # fill in authorization and in-scope targets
cd ~/engagement/acme-web && watchdog-ai  # start the agent from inside the job folder
```

Tell the agent what to do within scope, e.g. "test the targets in scope.md step by step and
save findings under report/". It explains each command and asks before touching the network.

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
3. Eject the drive from the OS before unplugging.
