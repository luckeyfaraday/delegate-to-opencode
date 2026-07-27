# delegate-to-opencode

A [Claude Code](https://claude.com/claude-code) skill for orchestrating the **OpenCode CLI** as a
background build agent. Claude stays the orchestrator and reviewer; opencode does the heavy
lifting; you get a reviewable diff.

It ships two things:

- **`SKILL.md`** — the operating manual the orchestrating agent reads: when to offload, how to
  split a task into cleanly-scoped subtasks, how to write a self-contained brief, how to launch,
  and how to verify and reintegrate what came back.
- **`scripts/run-opencode.sh`** — a wrapper around `opencode run` that makes headless runs
  loggable and resumable.

Works with any agent that can read a skill and run a shell command — Claude Code, Codex, or a
plain terminal.

## What the wrapper handles

- **Auto-permissions.** Runs use `--auto` so opencode is not asked to confirm tool calls.
  Pass `--no-auto` to require approval instead.
- **Deterministic resume.** The session ID is captured from the JSON event stream and written
  to `$RUN_DIR/session_id`, so follow-ups work even if you didn't note the ID. Pass `--resume`
  to continue a session, or `--resume` + `--fork` to branch it.
- **Clean JSON.** Raw output is filtered to NDJSON in `events.jsonl`; the final assistant
  message is reconstructed into `last_message.txt`.
- **Briefs via stdin.** Prompts go through stdin, so multi-line briefs need no shell quoting.
- **Run artifacts.** Every run leaves a directory behind rather than scrolling past you.

## Install

Requires [`opencode`](https://opencode.ai) (configured via `opencode auth login`), `bash`,
and `jq`.

```bash
git clone https://github.com/luckeyfaraday/delegate-to-opencode.git
ln -s "$PWD/delegate-to-opencode" ~/.claude/skills/opencode
```

Then verify:

```bash
opencode models        # prints all models across configured providers
~/.claude/skills/opencode/scripts/run-opencode.sh --help
```

## Usage

The agent normally drives this, but the wrapper stands alone:

```bash
# Offload a task; brief comes from stdin, run lands in $RUN_DIR
./scripts/run-opencode.sh -C ~/code/myrepo -m anthropic/claude-sonnet-4 -l migrate - < brief.md

# Follow up on the same session, with full memory of the prior run
./scripts/run-opencode.sh -C ~/code/myrepo --resume "$(cat $RUN_DIR/session_id)" - <<< 'Tests still fail: ...'

# Fork a session to explore a different fix
./scripts/run-opencode.sh -C ~/code/myrepo --resume "$(cat $RUN_DIR/session_id)" --fork - <<< 'Try a different approach: ...'
```

### Options

| Flag | Default | Notes |
|---|---|---|
| `-C <dir>` | cwd | OpenCode's working directory |
| `-m <model>` | config default | `provider/model` format; must be a real ID from `opencode models` |
| `-v <variant>` | provider default | Reasoning effort, e.g. `high`, `max`, `minimal` |
| `-l <label>` | `run` | Names the run directory and session title |
| `--resume <id>` | — | Continue a previous session |
| `--fork` | off | Fork the session on resume |
| `--agent <name>` | — | Use a specific opencode agent |
| `-f <file>` | — | Attach file(s) to the prompt; repeatable |
| `--no-auto` | off | Require permission approval instead of auto-approving |

Environment: `OPENCODE_ROUTER_MODEL`, `OPENCODE_ROUTER_VARIANT`, `OPENCODE_ROUTER_RUNS`
(run-directory root, default `$TMPDIR/opencode-router`).

### Run artifacts

```
$RUN_DIR/
  prompt.md          the brief as sent
  events.jsonl       NDJSON event stream
  last_message.txt   opencode's final report, reconstructed from the stream
  meta.json          terminal event (end / error)
  session_id         for --resume
  stderr.log         diagnostics when a run exits non-zero
  raw.log            unprocessed output
```

## Caveats

- Runs use `--auto` by default — opencode is not asked to confirm tool calls. Use `--no-auto`
  if you need approval gates.
- Model IDs use `provider/model` format and vary by configured providers. `opencode models`
  is the source of truth.
- Concurrent runs need separate checkouts (`git worktree add`). Never point two runs at one tree.

## License

MIT — see [LICENSE](LICENSE).
