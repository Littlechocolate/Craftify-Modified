---
trigger: always_on
description: Update RELEASE_CHANGELOG.md before pushing to GitHub and poll GitHub Actions compilation status every 1 minute until completion.
---

# GitHub Push & Release Guard Rule

Whenever accessing GitHub data or pushing code changes to GitHub (`origin main`):
1. **Always Use `gh` CLI**: Never invoke direct GitHub API endpoints via `curl` or extract tokens from credentials. Always directly generate and run `gh` CLI commands (e.g., `gh repo view`, `gh issue list`, `gh pr create`, `gh run list`, `gh run view`, `gh release view`).
2. **Update Release Changelog**: Always update [`RELEASE_CHANGELOG.md`](file:///Users/shift8/Documents/Antigravity/Craftify/RELEASE_CHANGELOG.md) with a concise Chinese summary of the modifications made in the current push so that the GitHub Actions Release body (`Generate Release Notes` in [`.github/workflows/build-ipa.yml`](file:///Users/shift8/Documents/Antigravity/Craftify/.github/workflows/build-ipa.yml)) includes the latest change summary.
3. **1-Minute Compilation Status Guard**: Immediately after `git push`, schedule a 1-minute recurring cron (`CronExpression: "* * * * *"`, `IsDaemon: false`) using the `schedule` tool to check the GitHub Actions workflow run status for the pushed commit every 1 minute using `gh run list --branch main -L 1`.
   - Once the workflow completes with `success` / `completed`, cancel the cron task via `manage_task(Action: "kill")` and report the successful build and release link (via `gh release view`) to the user.
   - If the workflow fails, inspect the failed job logs directly via `gh run view <id> --log-failed`, fix the compiler/build issue immediately, push again, and continue monitoring until it succeeds.
