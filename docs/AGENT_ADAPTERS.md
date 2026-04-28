# Agent Adapters

Symphony supervises one configured child command per issue. The adapter controls
how Symphony interprets that command's stdout/stderr.

```yaml
agent_runtime:
  provider: codex
  command: bash "$SYMPHONY_HOME/scripts/symphony-codex-run.sh"
  event_format: codex-json
  turn_timeout_ms: 3600000
  stall_timeout_ms: 300000
```

## Providers

- `codex`: default. Parses `codex exec --json` JSONL events and token counts.
- `opencode`: OpenCode CLI supervision through `opencode run`.
- `claude-code`: Claude Code headless supervision through `claude -p`.
- `cursor-cli`: generic CLI supervision for Cursor Agent CLI commands.
- `generic-cli`: any command that can read `SYMPHONY_PROMPT_FILE`.

`opencode`, `claude-code`, `cursor-cli`, and `generic-cli` currently use
`event_format: plain`, which means Symphony tracks process output, timestamps,
retries, workpads, and dashboard state, but only estimates token activity from
observed text when no native token events are available.

## Cursor Agent CLI

Cursor's headless CLI uses `cursor-agent -p "<prompt>"` for non-interactive
runs, with `--output-format text` for script-friendly output. Symphony includes a
small wrapper that creates the target worktree, reads `SYMPHONY_PROMPT_FILE`,
and invokes Cursor from inside that worktree:

```yaml
agent_runtime:
  provider: cursor-cli
  command: bash "$SYMPHONY_HOME/scripts/symphony-cursor-run.sh"
  event_format: plain
```

Set `CURSOR_AGENT_MODEL` in the environment to pass `--model` to
`cursor-agent`.

## OpenCode CLI

OpenCode supports non-interactive runs with `opencode run "<prompt>"`. Symphony
includes a wrapper that creates the target worktree, reads `SYMPHONY_PROMPT_FILE`,
and invokes OpenCode from that worktree:

```yaml
agent_runtime:
  provider: opencode
  command: bash "$SYMPHONY_HOME/scripts/symphony-opencode-run.sh"
  event_format: plain
```

Optional environment knobs:

- `OPENCODE_MODEL`: passed as `--model`.
- `OPENCODE_AGENT`: passed as `--agent`.
- `OPENCODE_FORMAT`: passed as `--format` (`default` unless set).
- `OPENCODE_SKIP_PERMISSIONS=false`: disables the default
  `--dangerously-skip-permissions` automation flag.

## Claude Code

Claude Code supports headless runs with `claude -p "<query>"` and
`--output-format text`. Symphony includes a wrapper that creates the target
worktree, reads `SYMPHONY_PROMPT_FILE`, and invokes Claude Code from that
worktree:

```yaml
agent_runtime:
  provider: claude-code
  command: bash "$SYMPHONY_HOME/scripts/symphony-claude-run.sh"
  event_format: plain
```

Optional environment knobs:

- `CLAUDE_CODE_MODEL`: passed as `--model`.
- `CLAUDE_CODE_OUTPUT_FORMAT`: passed as `--output-format` (`text` unless set).
- `CLAUDE_CODE_PERMISSION_MODE`: passed as `--permission-mode` (`acceptEdits`
  unless set).

## Environment Contract

Every adapter command receives:

- `SYMPHONY_PROMPT_FILE`: rendered prompt path.
- `SYMPHONY_HOME`: this Symphony checkout.
- `SYMPHONY_AGENT_PROVIDER`: configured provider.
- `SYMPHONY_AGENT_EVENT_FORMAT`: configured event format.
- `SYMPHONY_TARGET_REPO_ROOT`: target repository root.
- `SYMPHONY_BASE_BRANCH`: target base branch.
- `SYMPHONY_ISSUE_ID` and `SYMPHONY_ISSUE_IDENTIFIER`: current Linear issue.
- `LINEAR_API_KEY`: resolved Linear key when configured.

## Example Generic Command

For a CLI that can read a prompt file directly:

```yaml
agent_runtime:
  provider: generic-cli
  command: my-agent run --workspace "$SYMPHONY_WORKSPACE" --prompt-file "$SYMPHONY_PROMPT_FILE"
  event_format: plain
```

For richer token accounting or structured step events, add a provider parser in
`scripts/symphony.js` and set `event_format` accordingly.
