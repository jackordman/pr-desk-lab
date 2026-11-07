# pr-desk-lab

PRs in every state [PR Desk](https://github.com/jackordman/pr-menubar) shows, so its sections can be checked without waiting for real ones. Run PR Desk with `--lab` to point it at this repo only.

`main` matches cn and smartcare: one approval required, approval of the latest push required, stale approvals not dismissed.

The `bot` workflow acts as a second person (`github-actions[bot]`): it opens PRs, requests a review, approves, requests changes and pushes after a review. CI states are commit statuses set straight through the API.

`./scenarios.sh` closes every open PR, deletes the lab branches and builds the set again.

Not covered: mentions and new comments. They need a second human, and PR Desk ignores bot comments.
