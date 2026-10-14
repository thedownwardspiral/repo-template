#!/usr/bin/env bash
# Turns on the repo security settings, locks down GitHub Actions and applies
# the "Protect main" ruleset. Actions settings: GITHUB_TOKEN read-only by
# default, Actions cannot approve PRs, only GitHub-owned and allowlisted
# actions may run, and (public repos) fork PRs from every outside contributor
# wait for approval. Merged branches are deleted and PR branches can be
# updated from the PR page. Run once after creating a repo from this template:
#
#   .github/setup-repo.sh owner/name
#
# Safe to re-run: it updates the ruleset in place instead of adding another.
set -euo pipefail

repo=${1:?usage: setup-repo.sh owner/name}
dir=$(cd "$(dirname "$0")" && pwd)

# The ruleset requires the jobs in security.yml. Without that workflow the
# checks never report and every PR is blocked, so refuse instead.
if ! gh api "repos/$repo/contents/.github/workflows/security.yml" --silent 2>/dev/null; then
  echo "$repo has no .github/workflows/security.yml on its default branch; not applying the ruleset." >&2
  exit 1
fi

gh api -X PUT "repos/$repo/vulnerability-alerts" --silent
gh api -X PUT "repos/$repo/automated-security-fixes" --silent
echo "Dependabot alerts and security updates: on"

# The workflows already set `permissions: {}` and grant each job only what it
# needs; this covers any workflow added later that forgets to.
gh api -X PUT "repos/$repo/actions/permissions/workflow" --silent --input - <<'JSON'
{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}
JSON
echo "Read-only GITHUB_TOKEN by default, Actions cannot approve PRs: on"

# actions/* and github/* (checkout, dependency-review-action, codeql-action)
# are GitHub-owned. Semgrep and OSV-Scanner run via `docker run` in run: steps,
# so the allowlist does not apply to them. SHA pins already stop a tag being
# moved under us; this stops an unvetted action being added at all.
# Add any new third-party action to patterns_allowed, or its workflow fails.
gh api -X PUT "repos/$repo/actions/permissions" --silent --input - <<'JSON'
{"enabled": true, "allowed_actions": "selected"}
JSON
gh api -X PUT "repos/$repo/actions/permissions/selected-actions" --silent --input - <<'JSON'
{"github_owned_allowed": true, "verified_allowed": false, "patterns_allowed": ["gitleaks/gitleaks-action@*", "zizmorcore/zizmor-action@*"]}
JSON
echo "Actions allowlist (GitHub-owned, gitleaks, zizmor): on"

# The ruleset requires PR branches to be up to date with main;
# allow_update_branch adds the "Update branch" button so that is one click.
# Squash is the only merge method: linear history rejects merge commits, and
# required signatures reject rebase merges (GitHub does not sign the rebased
# commits). Squash merges made in the web UI are signed by GitHub.
gh api -X PATCH "repos/$repo" --silent --input - <<'JSON'
{"delete_branch_on_merge": true, "allow_update_branch": true,
 "allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false}
JSON
echo "Squash-only merges, delete merged branches, \"Update branch\" button: on"

# Secret scanning, push protection and private vulnerability reporting are
# free only for public repos; personal accounts cannot enable them on private ones.
# Compare against "public": an org's internal repos also report private=false.
if [ "$(gh api "repos/$repo" --jq .visibility)" = "public" ]; then
  gh api -X PATCH "repos/$repo" --silent --input - <<'JSON'
{"security_and_analysis": {"secret_scanning": {"status": "enabled"}, "secret_scanning_push_protection": {"status": "enabled"}}}
JSON
  echo "Secret scanning and push protection: on"
  gh api -X PUT "repos/$repo/private-vulnerability-reporting" --silent
  echo "Private vulnerability reporting: on"
  # Anyone can fork a public repo and open a PR whose workflow changes run
  # here, so hold every outside contributor's run until a maintainer approves.
  # The endpoint is newer than the rest; warn instead of failing if it is refused.
  if gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" --silent --input - 2>/dev/null <<'JSON'
{"approval_policy": "all_external_contributors"}
JSON
  then
    echo "Approval for fork PR workflows from all outside contributors: on"
  else
    echo "warning: could not set fork PR approval; set Settings → Actions → General → \"Approval for running fork pull request workflows\" to require approval for all external contributors by hand." >&2
  fi
fi

id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "Protect main") | .id')
if [ -n "$id" ]; then
  gh api -X PUT "repos/$repo/rulesets/$id" --input "$dir/rulesets/protect-main.json" --silent
  echo "Ruleset \"Protect main\": updated"
else
  gh api -X POST "repos/$repo/rulesets" --input "$dir/rulesets/protect-main.json" --silent
  echo "Ruleset \"Protect main\": created"
fi
