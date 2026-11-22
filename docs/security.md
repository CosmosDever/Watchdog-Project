# Responsible use

Watchdog packages real offensive-security tools and an AI that can run them. Use it only
where you are authorized.

## Rules of engagement

- Test only systems you own or have **written permission** to test. Keep the authorization
  reference in the engagement's `scope.md`.
- Each job lives in its own folder (`~/engagement/<name>/`) with its own `scope.md`. The
  agent is instructed to read that scope before any network activity and to stop if a
  target is missing or unclear.
- The harness asks before running network commands. Keep that confirmation on — a small
  local model can misjudge scope.
- No denial-of-service, no targeting third parties, no using this against production
  systems you were not engaged to test.

## Data handling

- The drive is **not encrypted** by default. Consider BitLocker-To-Go (Windows) or an
  encrypted volume for client data, and shut down the VM and eject before unplugging.
- Engagement folders, scope files, and findings are gitignored — never commit them.
- Cloud API models send prompts off your machine. Do not put client data or out-of-scope
  details in prompts to a cloud model; use the local model for anything sensitive.

## Models

Watchdog ships no model weights. Use open-weight models from reputable publishers and
verify their hashes. The authorization context in `AGENTS.md` keeps a normal model willing
to help with *authorized* lab work without removing its safety behavior. Choosing a model
is the operator's responsibility.
