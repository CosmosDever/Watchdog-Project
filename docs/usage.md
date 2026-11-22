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

## Shut down safely

The drive is exFAT (no journaling), so always:

1. `sudo poweroff` inside Kali (or type `S` in the launcher window).
2. Stop the AI window.
3. Eject the drive from the OS before unplugging.
