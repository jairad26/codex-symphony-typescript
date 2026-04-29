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

issue_identifier="${SYMPHONY_ISSUE_IDENTIFIER:-symphony-issue}"
branch_slug="$(printf '%s' "$issue_identifier" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')"
branch_name="${branch_prefix}-${branch_slug%-}"
worktree_dir="$PWD/repo"
output_file="$PWD/codex-last-message.md"

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

codex_bin="${CODEX_BIN:-}"
if [[ -z "$codex_bin" ]]; then
	codex_bin="$(command -v codex || true)"
fi
if [[ -z "$codex_bin" ]]; then
	for candidate in "$HOME"/.local/bin/codex "$HOME"/.nvm/versions/node/*/bin/codex /opt/homebrew/bin/codex /usr/local/bin/codex; do
		if [[ -x "$candidate" ]]; then
			codex_bin="$candidate"
			break
		fi
	done
fi
if [[ -z "$codex_bin" || ! -x "$codex_bin" ]]; then
	echo "codex CLI not found. Install codex, set CODEX_BIN, or start Symphony with codex on PATH." >&2
	echo "PATH=$PATH" >&2
	exit 127
fi

"$codex_bin" exec \
	--cd "$worktree_dir" \
	--disable fast_mode \
	--dangerously-bypass-approvals-and-sandbox \
	--json \
	--output-last-message "$output_file" \
	- <"$SYMPHONY_PROMPT_FILE"

if command -v gh >/dev/null 2>&1; then
	pr_number="$(cd "$worktree_dir" && gh pr view --json number --jq '.number' 2>/dev/null || true)"
	if [[ -n "$pr_number" ]]; then
		(cd "$worktree_dir" && gh pr ready "$pr_number" >/dev/null 2>&1) || true
		echo "Marked PR #$pr_number ready for review."
		pr_url="$(cd "$worktree_dir" && gh pr view "$pr_number" --json url --jq '.url' 2>/dev/null || true)"
		if [[ -n "${LINEAR_API_KEY:-}" && -n "${SYMPHONY_ISSUE_ID:-}" && -n "${SYMPHONY_LINEAR_IN_REVIEW_STATE_ID:-}" ]]; then
			LINEAR_PR_NUMBER="$pr_number" LINEAR_PR_URL="$pr_url" node <<'NODE'
const endpoint = process.env.SYMPHONY_LINEAR_ENDPOINT || "https://api.linear.app/graphql";
const issueId = process.env.SYMPHONY_ISSUE_ID;
const stateId = process.env.SYMPHONY_LINEAR_IN_REVIEW_STATE_ID;
const prNumber = process.env.LINEAR_PR_NUMBER;
const prUrl = process.env.LINEAR_PR_URL;
const apiKey = process.env.LINEAR_API_KEY;

async function post(query, variables) {
	const response = await fetch(endpoint, {
		method: "POST",
		headers: { "content-type": "application/json", authorization: apiKey },
		body: JSON.stringify({ query, variables })
	});
	if (!response.ok) {
		throw new Error(`Linear API returned ${response.status}`);
	}
	const payload = await response.json();
	if (payload.errors?.length) {
		throw new Error(payload.errors.map((error) => error.message).join("; "));
	}
	return payload.data;
}

(async () => {
	await post(
		`mutation SymphonyIssueUpdate($id: String!, $input: IssueUpdateInput!) {
			issueUpdate(id: $id, input: $input) { success }
		}`,
		{ id: issueId, input: { stateId } }
	);
	if (prUrl) {
		await post(
			`mutation SymphonyCommentCreate($input: CommentCreateInput!) {
				commentCreate(input: $input) { success }
			}`,
			{ input: { issueId, body: `Symphony opened PR #${prNumber}: ${prUrl}\n\nStatus: ready for review.` } }
		);
	}
	console.log(`Moved Linear issue ${issueId} to In Review${prUrl ? ` and commented ${prUrl}` : ""}.`);
})().catch((error) => {
	console.error(`Linear PR-open transition failed: ${error.message}`);
	process.exitCode = 0;
});
NODE
		fi
	fi
fi
