# repo-template

A starting point for new repos with security checks already wired up. Replace this README after creating a repo from it.

## Create a repo

```bash
gh repo create my-repo --public --template thedownwardspiral/repo-template --clone
cd my-repo
.github/setup-repo.sh thedownwardspiral/my-repo
pre-commit install
```

Use `--private` instead of `--public` for a private repo. The workflows detect visibility on their own.

`setup-repo.sh` turns on Dependabot alerts and security updates, turns on private vulnerability reporting (public repos only), and applies the "Protect main" ruleset. The ruleset requires a PR to change `main`, blocks force pushes and deletion, and requires the security checks to pass. It needs no approvals, so a sole maintainer can still merge.

## What runs

`.github/workflows/security.yml` runs on every PR, on pushes to `main`, and weekly:

| Job | Public repo | Private repo | Checks |
| --- | --- | --- | --- |
| `gitleaks` | runs | runs | Secrets in commits; full history on the weekly run |
| `dependency-review` | runs (PRs) | skipped | PRs that add vulnerable dependencies |
| `codeql` | runs | skipped | Static analysis; languages are detected automatically |
| `semgrep` | skipped | runs | Static analysis (Semgrep CE) |
| `osv-scanner` | skipped | runs | Known vulnerabilities in dependency files |

Private repos on a personal account cannot use CodeQL, dependency review or GitHub secret scanning, so Semgrep CE and OSV-Scanner stand in for them. A skipped job counts as passing, so one ruleset works for both.

`zizmor.yml` lints the workflow files whenever `.github/` changes.

## After creating a repo

- **Dependencies:** add an entry for each package manager to `.github/dependabot.yml`. Commit lockfiles: OSV-Scanner checks only the versions written in the repo.
- **CodeQL:** detects Python, JavaScript/TypeScript, Ruby, Java/Kotlin and C#. Languages that need a build step (Go, C/C++, Swift) must be added to the `codeql` job by hand.
- **Secrets:** `pre-commit install` scans each commit locally with gitleaks before it is created. For a private repo this is the only check that runs before a secret reaches GitHub.

## Pinning

Every action is pinned to a commit SHA, and the Semgrep and OSV-Scanner images to digests. Dependabot updates the action pins. The image digests and the pre-commit hook must be bumped by hand (`pre-commit autoupdate --freeze` handles the hook).
