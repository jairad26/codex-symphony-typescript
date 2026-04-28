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

if ! command -v opencode >/dev/null 2>&1; then
	echo "opencode must be installed and available on PATH" >&2
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

opencode_args=(run --dir "$worktree_dir" --format "${OPENCODE_FORMAT:-default}" --title "${SYMPHONY_ISSUE_IDENTIFIER:-Symphony run}")
if [[ "${OPENCODE_SKIP_PERMISSIONS:-true}" != "false" ]]; then
	opencode_args+=(--dangerously-skip-permissions)
fi
if [[ -n "${OPENCODE_MODEL:-}" ]]; then
	opencode_args+=(--model "$OPENCODE_MODEL")
fi
if [[ -n "${OPENCODE_AGENT:-}" ]]; then
	opencode_args+=(--agent "$OPENCODE_AGENT")
fi

opencode "${opencode_args[@]}" "$(cat "$SYMPHONY_PROMPT_FILE")"
