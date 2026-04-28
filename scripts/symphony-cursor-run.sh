#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SYMPHONY_PROMPT_FILE:-}" || ! -f "$SYMPHONY_PROMPT_FILE" ]]; then
	echo "SYMPHONY_PROMPT_FILE must point to the rendered Symphony prompt" >&2
	exit 2
fi

repo_root="${SYMPHONY_TARGET_REPO_ROOT:-${SYMPHONY_REPO_ROOT:-}}"
base_branch="${SYMPHONY_BASE_BRANCH:-main}"
branch_prefix="${SYMPHONY_BRANCH_PREFIX:-symphony}"
repo_env_file="${SYMPHONY_REPO_ENV_FILE:-.env.local}"

if [[ -z "$repo_root" || ! -d "$repo_root/.git" ]]; then
	echo "SYMPHONY_TARGET_REPO_ROOT must point to the target git repository" >&2
	exit 2
fi

if ! command -v cursor-agent >/dev/null 2>&1; then
	echo "cursor-agent must be installed and available on PATH" >&2
	exit 127
fi

issue_identifier="${SYMPHONY_ISSUE_IDENTIFIER:-symphony-issue}"
branch_slug="$(printf '%s' "$issue_identifier" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')"
branch_name="${branch_prefix}-${branch_slug%-}"
worktree_dir="$PWD/repo"

git -C "$repo_root" fetch origin "$base_branch" --quiet

if [[ ! -e "$worktree_dir/.git" ]]; then
	git -C "$repo_root" worktree prune >/dev/null
	if ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
		git -C "$repo_root" branch "$branch_name" "origin/$base_branch"
	fi
	git -C "$repo_root" worktree add "$worktree_dir" "$branch_name"
fi

if [[ "${SYMPHONY_LINK_NODE_MODULES:-true}" != "false" && -d "$repo_root/node_modules" && ! -e "$worktree_dir/node_modules" ]]; then
	ln -s "$repo_root/node_modules" "$worktree_dir/node_modules"
fi

if [[ -n "$repo_env_file" && -f "$repo_root/$repo_env_file" && ! -e "$worktree_dir/$repo_env_file" ]]; then
	ln -s "$repo_root/$repo_env_file" "$worktree_dir/$repo_env_file"
fi

if command -v gt >/dev/null 2>&1; then
	(cd "$worktree_dir" && gt sync) || true
fi

cursor_args=(-p "$(cat "$SYMPHONY_PROMPT_FILE")" --output-format text)
if [[ -n "${CURSOR_AGENT_MODEL:-}" ]]; then
	cursor_args+=(--model "$CURSOR_AGENT_MODEL")
fi

(cd "$worktree_dir" && cursor-agent "${cursor_args[@]}")

if command -v gh >/dev/null 2>&1; then
	pr_number="$(cd "$worktree_dir" && gh pr view --json number --jq '.number' 2>/dev/null || true)"
	if [[ -n "$pr_number" ]]; then
		(cd "$worktree_dir" && gh pr ready "$pr_number" >/dev/null 2>&1) || true
		echo "Marked PR #$pr_number ready for review."
	fi
fi
