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
