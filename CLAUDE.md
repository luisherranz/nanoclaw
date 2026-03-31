# NanoClaw

Personal Claude assistant. See [README.md](README.md) for philosophy and setup. See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for architecture decisions.

## Quick Context

Single Node.js process with skill-based channel system. Channels (WhatsApp, Telegram, Slack, Discord, Gmail) are skills that self-register at startup. Messages route to Claude Agent SDK running in containers (Linux VMs). Each group has isolated filesystem and memory.

## Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Orchestrator: state, message loop, agent invocation |
| `src/channels/registry.ts` | Channel registry (self-registration at startup) |
| `src/ipc.ts` | IPC watcher and task processing |
| `src/router.ts` | Message formatting and outbound routing |
| `src/config.ts` | Trigger pattern, paths, intervals |
| `src/container-runner.ts` | Spawns agent containers with mounts |
| `src/task-scheduler.ts` | Runs scheduled tasks |
| `src/db.ts` | SQLite operations |
| `groups/{name}/CLAUDE.md` | Per-group memory (isolated) |
| `container/skills/` | Skills loaded inside agent containers (browser, status, formatting) |
| `container/agent-runner/src/lcm-store.ts` | LCM SQLite database (messages + summary DAG) |
| `container/agent-runner/src/lcm-helpers.ts` | LCM pure functions (context detection, proactive compaction, transcript parsing) |
| `container/agent-runner/src/lcm-summarize.ts` | LCM summarization (leaf + condensed summaries) |

## Secrets / Credentials / Proxy (OneCLI)

API keys, secret keys, OAuth tokens, and auth credentials are managed by the OneCLI gateway — which handles secret injection into containers at request time, so no keys or tokens are ever passed to containers directly. Run `onecli --help`.

**Exception: GitHub CLI (`gh`).** The OneCLI proxy injects auth headers into HTTPS requests, but `gh` checks for local credentials before making any network request. It won't reach the proxy. To work around this, `GH_TOKEN` is injected as an env var via `containerConfig.env` per group. Tokens are stored in the SQLite DB (`registered_groups.container_config`).

## Per-Group Container Configuration

Each group's `containerConfig` (stored in `registered_groups.container_config` as JSON) supports:

- **`additionalMounts`** — extra host paths mounted into the container at `/workspace/extra/{name}`. Validated against the mount allowlist at `~/.config/nanoclaw/mount-allowlist.json` (stored outside the project root so containers can't tamper with it).
- **`env`** — extra environment variables injected into the container (e.g. `GH_TOKEN`). Use this for credentials that tools need as env vars rather than HTTP headers.
- **`timeout`** — container timeout override in milliseconds.

Example `container_config` JSON:
```json
{
  "additionalMounts": [
    { "hostPath": "~/Code", "containerPath": "Code", "readonly": false }
  ],
  "env": { "GH_TOKEN": "github_pat_xxx" }
}
```

The mount allowlist (`~/.config/nanoclaw/mount-allowlist.json`) controls which host paths are allowed and whether read-write is permitted:
```json
{
  "allowedRoots": [
    { "path": "~/Code", "allowReadWrite": true, "description": "Dev projects" }
  ],
  "blockedPatterns": [],
  "nonMainReadOnly": true
}
```

`nonMainReadOnly: true` forces all non-main group mounts to read-only regardless of what they request.

## Lossless Context Management (LCM)

LCM preserves conversation history across context compaction. When conversations exceed the context window, LCM persists messages to a per-group SQLite database and builds a DAG of hierarchical summaries. See [docs/lcm-spec.md](docs/lcm-spec.md) for the full specification.

Key LCM environment variables (set via `containerConfig.env` or container defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `LCM_PROACTIVE_COMPACTION_THRESHOLD` | `75` | Context usage % triggering proactive compaction (0 = disabled) |
| `LCM_SUMMARY_MODEL` | `claude-haiku-4-5-20251001` | Model used for generating summaries |
| `LCM_CONTEXT_WINDOW_TOKENS` | `1000000` | Fallback context window size (auto-detected from SDK when possible) |
| `LCM_FRESHNESS_WINDOW` | `32` | Messages protected from compaction |

## Skills

Four types of skills exist in NanoClaw. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full taxonomy and guidelines.

- **Feature skills** — merge a `skill/*` branch to add capabilities (e.g. `/add-telegram`, `/add-slack`)
- **Utility skills** — ship code files alongside SKILL.md (e.g. `/claw`)
- **Operational skills** — instruction-only workflows, always on `main` (e.g. `/setup`, `/debug`)
- **Container skills** — loaded inside agent containers at runtime (`container/skills/`)

| Skill | When to Use |
|-------|-------------|
| `/setup` | First-time installation, authentication, service configuration |
| `/customize` | Adding channels, integrations, changing behavior |
| `/debug` | Container issues, logs, troubleshooting |
| `/update-nanoclaw` | Bring upstream NanoClaw updates into a customized install |
| `/init-onecli` | Install OneCLI Agent Vault and migrate `.env` credentials to it |
| `/qodo-pr-resolver` | Fetch and fix Qodo PR review issues interactively or in batch |
| `/get-qodo-rules` | Load org- and repo-level coding rules from Qodo before code tasks |

## Contributing

Before creating a PR, adding a skill, or preparing any contribution, you MUST read [CONTRIBUTING.md](CONTRIBUTING.md). It covers accepted change types, the four skill types and their guidelines, SKILL.md format rules, PR requirements, and the pre-submission checklist (searching for existing PRs/issues, testing, description format).

## Development

Run commands directly—don't tell the user to run them.

```bash
npm run dev          # Run with hot reload
npm run build        # Compile TypeScript
./container/build.sh # Rebuild agent container
```

Service management:
```bash
# macOS (launchd)
launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist
launchctl kickstart -k gui/$(id -u)/com.nanoclaw  # restart

# Linux (systemd)
systemctl --user start nanoclaw
systemctl --user stop nanoclaw
systemctl --user restart nanoclaw
```

## Troubleshooting

**WhatsApp not connecting after upgrade:** WhatsApp is now a separate skill, not bundled in core. Run `/add-whatsapp` (or `npx tsx scripts/apply-skill.ts .claude/skills/add-whatsapp && npm run build`) to install it. Existing auth credentials and groups are preserved.

## Container Build Cache

The container buildkit caches the build context aggressively. `--no-cache` alone does NOT invalidate COPY steps — the builder's volume retains stale files. To force a truly clean rebuild, prune the builder then re-run `./container/build.sh`.
