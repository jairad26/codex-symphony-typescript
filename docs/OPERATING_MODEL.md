# Operating Model

Codex Symphony is meant to make agent runs boring and inspectable.

## Lifecycle

1. Poll Linear for active issues in one project.
2. Filter by assignee, state, blockers, and concurrency.
3. Move the issue to a dispatch state when configured.
4. Create a workspace and target-repo worktree.
5. Render the issue prompt.
6. Run `codex exec`.
7. Stream logs and state to the local server.
8. If a PR exists, mark it ready and optionally move Linear to review.
9. Stop before merge.

## What Symphony Knows

Symphony knows what it directly observes:

- Linear issue fields and state.
- Local workspace paths.
- Child process status.
- Child output and approximate running token activity.
- PR URL when the wrapper can read one with `gh`.

Symphony does not claim merge completion unless you add a separate merge monitor. That is intentional; PR-opened and merged are different facts.

## Recommended Rollout

Start narrow:

- One Linear project.
- One assignee.
- A small active-state set.
- Low concurrency.
- No merge automation.

Then widen only after several quiet runs.
