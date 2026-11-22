# Configuring Watchdog

Everything is driven by `config/watchdog.json` on the drive. Edit it and re-run the
provisioner (`setup/provision.ps1` or `setup/provision-mac.sh`) to apply changes that
involve downloads.

## Choose your models

`models` is a list. Each entry is placed in `llm/models` on the drive and offered when you
start the AI.

```json
{ "name": "Qwen3.5-9B-Q4_K_M.gguf",
  "role": "agent",
  "url":  "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf",
  "sha256": "03b7...b7e8" }
```

- Keep models that fit your GPU. On 8 GB VRAM, a 7B–9B model at `Q4_K_M` is the sweet spot.
- `"tool_shim": true` — set this for a model that prints tool calls as plain JSON instead
  of structured `tool_calls` (WhiteRabbitNeo does this). The launcher then serves it through
  `toolshim.py` so the agent can actually call tools.
- Download only `.gguf` files from reputable publishers and keep the `sha256` — the
  provisioner refuses a file whose hash does not match.

You choose which model to load each time you start the AI; no re-provisioning needed to
switch between models already on the drive.

## Context window and VRAM

The local server runs with a **32768-token** context and a **q8_0 KV cache** by default. The
quantized KV cache roughly halves the memory the context uses, so a large window still fits an
8 GB card. Tune it when you start the model:

```powershell
./launcher/start-llm.ps1 -ContextSize 49152            # bigger window, more VRAM
./launcher/start-llm.ps1 -ContextSize 16384 -KvCache f16  # smaller window, full-precision cache
```

On macOS the same knobs are environment variables: `LLM_CONTEXT` and `LLM_KVCACHE`. If the
model fails to load, lower `-ContextSize`; if you hit "exceeds the available context size",
raise it (and see the troubleshooting notes in [usage.md](usage.md)).

## Use a cloud API (Claude, OpenAI, OpenRouter)

The local model is the default, but you can point the harness at a hosted model when you
want more capability. OpenCode supports these providers directly.

**Your API key never goes on the drive or into git.** Set it as an environment variable in
the Kali guest for the session, then pick the cloud model inside OpenCode.

Claude:

```bash
export ANTHROPIC_API_KEY=sk-ant-...        # set it in the Kali terminal, do not save it to a file on the drive
watchdog-ai                                # then: /models  → pick an Anthropic model
```

OpenAI or OpenRouter work the same way with `OPENAI_API_KEY` or `OPENROUTER_API_KEY`.

Notes:
- Cloud models leave your machine — do not send client data or anything out of scope to
  them. For sensitive engagements, stay on the local model.
- You can keep both: local for offline/private work, cloud when you want a stronger model.
  Switch with `/models` in OpenCode.

## Use a different guest OS

`os.type` is `qemu-image` (a prebuilt qcow2, like Kali's) or `iso-installer` (you install
once into a fresh disk, used for Apple Silicon arm64). Point `url` and `sha256` at any
Debian-based system that boots under QEMU — Parrot OS and Ubuntu both work. The launchers
are OS-agnostic; only the guest-side helper (`setup-ai.sh`) assumes `apt`.

## Use a different harness

`harness.name` defaults to `opencode`, the tested one. Any OpenAI-compatible terminal agent
(for example Aider) can point at the same `http://10.0.2.2:8080/v1` endpoint. Install it in
the guest and set its base URL; the rest of Watchdog does not change.

### HackingBuddyGPT as an alternative harness (advanced, needs internet once to install)

[HackingBuddyGPT](https://github.com/ipa-lab/hackingBuddyGPT) is a research pentest-agent
framework with purpose-built use-cases (`WebAPITesting`, `WebTestingWithShell`,
`PrivEscLinux`). It runs **inside Kali** and can point its LLM at either Watchdog's local model
or a cloud API. Install (Python 3.13+, requires network for the one-time `pip`):

```bash
git clone https://github.com/ipa-lab/hackingBuddyGPT && cd hackingBuddyGPT
python -m venv venv && source venv/bin/activate && pip install -e .
```

Point it at the **local** Watchdog model (OpenAI-compatible via the toolshim):

```bash
wintermute WebAPITesting \
  --llm.model=openai/local --llm.api_base=http://10.0.2.2:8080/v1 --llm.api_key=local
```

…or at a **cloud** model, e.g. `--llm.model=gpt-4o --llm.api_key=$OPENAI_API_KEY` (litellm
format; `anthropic/claude-...` with `ANTHROPIC_API_KEY` works too). Local-shell use-cases need
a tmux session first: `tmux new-session -s hb` then `--conn=local_shell --conn.tmux_session=hb`.
It writes JSONL traces under `logs/`. Keep it pointed only at in-scope targets.

> We looked at CAI (aliasrobotics/cai) too, but it was **archived in Aug 2026** and ships with
> telemetry on by default, so it is a poor fit for an offline/private drive. HackingBuddyGPT is
> the recommended alternative harness.
