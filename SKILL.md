---
name: opencode
description: Offload heavy-duty implementation work to an opencode build agent as a background worker, routing each task to the appropriate available model, while Claude stays the orchestrator and reviewer. Use when the user types /opencode, asks to delegate/offload/route work to opencode, or when a task is a large mechanical lift—big refactors, bulk migrations, wide test fixes, boilerplate-heavy features—that is better executed by a second agent while you supervise.
---

# OpenCode Offload — route heavy work to an opencode build agent

You are the **orchestrator and reviewer**. OpenCode is the **background worker**. Select its model
for the task, write a precise brief, launch opencode non-interactively, keep working or wait, then
review and verify what it produced. You own final quality — never present opencode's output to the
user unreviewed.

## When to offload (and when not to)

Offload when the task is **heavy but well-specified**: large refactors or renames across many
files, bulk migrations (API, framework, syntax), generating boilerplate-heavy features from a
clear spec, fixing a long list of similar test failures or lint errors, or any task the user
explicitly asks to send to opencode.

Keep it yourself when the task is small (faster to just do it), requires conversation context
or user judgment mid-flight, is design/architecture work, or touches secrets and credentials.

## Size the offload: one run or several?

Decide this **before** writing any brief. A monolithic brief covering many concerns is the
main way delegation fails: the worker has to juggle everything at once and requirements at
the edges get dropped. Delegation works best when each worker gets one bounded concern with
a clean, self-contained context window.

Split into multiple runs only when the subtasks are:

- **File-disjoint** — no two subtasks edit the same files. If you can't partition the paths
  cleanly, don't parallelize: run sequentially via resume, or keep it as one brief.
- **Independently verifiable** — each subtask has its own definition-of-done command that
  passes without the other subtasks' work in place.
- **Interface-stable** — any shared API, type, or schema the subtasks touch is already
  settled. If one subtask *defines* an interface another consumes, run the definer first
  (or write the interface yourself), then fan out the consumers.

Don't split below the size where brief overhead outweighs the work — "rename in 3 files" is
one brief, not three. Two to four concurrent workers is the practical ceiling: you review
every run (step 6), and past that your review becomes the bottleneck and the quality gate
thins.

Scope each sub-brief to its own slice: only the goal, file paths, and conventions that
subtask needs — and list the *other* subtasks' territory explicitly under **Out of scope**.
That keeps each worker's context clean and stops two runs from wandering into the same
files. Launch mechanics for multiple runs are in step 8.

## 1. Preflight (once per session)

```bash
opencode models        # prints all models across configured providers
opencode --version
```

- `opencode` not found → point the user at <https://opencode.ai>; install via
  `curl -fsSL https://opencode.ai/install | bash` or `npm install -g opencode-ai`
- No providers configured → tell the user to run `opencode auth login` (interactive; you
  cannot do it for them)

## 2. Select the worker model

Honor an explicit model request from the user. Otherwise honor `OPENCODE_ROUTER_MODEL` when set;
it is the user's configured default. If neither chooses, omit `-m` and let opencode use its own
default.

Models use the `provider/model` format (e.g. `anthropic/claude-sonnet-4`, `opencode/gpt-5.4`,
`pioneer/Qwen/Qwen3-235B`). Custom providers configured via `opencode auth login` appear
alongside built-in ones. **Never invent a model ID.** `opencode models` is the only source of
truth — treat its output as the allowlist.

Reasoning effort is controlled via `--variant` (provider-specific, e.g. `high`, `max`,
`minimal`). Default is provider-dependent; omit to use the provider's default.

## 3. Write the brief

OpenCode starts **cold** — it sees none of your conversation. The brief must be self-contained.
Write it to a temp file (multi-line, no shell-quoting pain) using this shape:

```markdown
# Task
<one-paragraph goal, stated as an outcome>

# Context
- Repo root: <path>. Key files/dirs: <paths with one-line roles>
- Relevant conventions: <build tool, test command, style rules that matter>

# Requirements
- <numbered, testable requirements>

# Definition of done
- <e.g. `npm test` passes; `grep -r oldApi src/` returns nothing>

# Out of scope
- Do NOT commit, push, or create branches.
- Do NOT touch: <paths>
```

Rules: include concrete file paths (opencode can read them itself — point, don't paste whole
files); state the verification command; never include secrets, tokens, or `.env` contents.

## 4. Launch

Use the wrapper script (in `scripts/` next to this SKILL.md). Run it **in the background**
(`run_in_background: true`) so you can keep working:

```bash
<skill-dir>/scripts/run-opencode.sh -C /path/to/repo -m anthropic/claude-sonnet-4 -l short-label - < /path/to/brief.md
```

| Flag | Default | Notes |
|---|---|---|
| `-C <dir>` | cwd | OpenCode's working directory |
| `-m <model>` | config default | `provider/model` format; must be a real ID from `opencode models` |
| `-v <variant>` | provider default | Reasoning effort, e.g. `high`, `max`, `minimal` |
| `-l <label>` | `run` | Names the run directory and session title |
| `--resume <id>` | — | Continue a previous session (step 7) |
| `--fork` | off | Fork the session on resume instead of continuing in place |
| `--agent <name>` | — | Use a specific opencode agent |
| `-f <file>` | — | Attach file(s) to the prompt; repeatable |
| `--no-auto` | off | Require permission approval instead of auto-approving |

The script prints `RUN_DIR`, containing `prompt.md`, `events.jsonl` (raw JSON events),
`last_message.txt` (opencode's final report), `meta.json` (terminal event), and
`session_id` (for resume).

## 5. While it runs

You'll be notified when the background task exits. Meanwhile, do other useful work. To check
progress without interrupting: `tail -5 "$RUN_DIR/events.jsonl"`. Don't poll in a tight loop.

## 6. Review and verify — you own this

When the run exits:

1. Read `last_message.txt` — opencode's own claim of what it did.
2. Inspect reality, not the claim: `git -C <repo> diff --stat`, then read the diff for the
   load-bearing files.
3. Run the definition-of-done checks yourself (tests, grep, build).
4. Small gaps → fix them yourself. Wrong direction or big misses → resume with a corrective
   follow-up (step 7) or revert and take over.
5. Report to the user: selected model, what was offloaded, what came back, what you verified,
   and what you fixed.

`meta.json` carries the terminal event. If it is an `error` type, the run failed — check
`stderr.log` in the run dir.

## 7. Follow-ups (resume)

Sessions are resumable with full memory of the prior run. The wrapper writes the session id to
`$RUN_DIR/session_id`:

```bash
<skill-dir>/scripts/run-opencode.sh -C /path/to/repo --resume "$(cat "$RUN_DIR/session_id")" -l fixup - <<'EOF'
The tests in tests/api_test.py still fail: <paste failure>. Fix them; everything else was correct.
EOF
```

Use `--fork` to branch a session instead of continuing in place — useful when you want to
explore two corrective paths from the same starting point.

## 8. Parallel offloads

For subtasks that pass the split criteria ("Size the offload" above), launch one run per
subtask — but give each its own checkout so writes never collide (`git worktree add`).
Never point two concurrent runs at the same working tree.

```bash
git -C /path/to/repo worktree add ../repo-auth -b oc/auth
<skill-dir>/scripts/run-opencode.sh -C /path/to/repo-auth -l auth - < /path/to/brief-auth.md
```

Give each run a distinct `-l` label so run directories stay tellable apart.

**Reintegrate deliberately — don't just merge everything at the end:**

1. Review each run individually first (step 6, per worktree). A bad run is cheapest to
   reject or resume *before* it's merged.
2. Merge accepted branches one at a time, dependency order first. After each merge, re-run
   that subtask's definition of done in the merged tree.
3. After the last merge, run the **combined** definition of done — full test suite, build,
   the greps from every brief. Subtasks that each passed alone can still break in
   integration; this check is yours, no worker ever saw the whole.
4. `git worktree remove` each checkout once merged or rejected.

## Failure modes

| Symptom | Fix |
|---|---|
| `opencode: command not found` | User installs from <https://opencode.ai> |
| No providers / 401 | User runs `opencode auth login` |
| Model rejected / not found | Re-check `opencode models`; IDs are `provider/model` |
| `meta.json` shows `error` type | Read `stderr.log` in the run dir |
| Empty `last_message.txt`, nonzero exit | Read `stderr.log` in the run dir |
| Result ignores constraints | Brief was ambiguous — resume with explicit corrections, don't relaunch cold |
| Merge conflicts between parallel runs | The split wasn't file-disjoint — merge one branch, then resume the other run against the merged tree instead of hand-resolving both |
