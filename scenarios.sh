#!/usr/bin/env bash
# Rebuilds every lab PR from scratch. Safe to rerun.
set -euo pipefail
cd "$(dirname "$0")"
R=jackordman/pr-desk-lab
ME=$(gh api user -q .login)

# Repo settings: Actions may open and approve PRs, main protected like cn and smartcare.
gh api -X PUT repos/$R/actions/permissions/workflow -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true
gh api -X PUT repos/$R/branches/main/protection --input - >/dev/null <<'JSON'
{"required_status_checks": null, "enforce_admins": false, "restrictions": null,
 "required_pull_request_reviews": {"required_approving_review_count": 1, "require_last_push_approval": true, "dismiss_stale_reviews": false}}
JSON

echo "Resetting"
for n in $(gh pr list -R $R --state open --json number -q '.[].number'); do gh pr close -R $R "$n" >/dev/null; done
git fetch -q --prune origin
git switch -q main && git reset -q --hard origin/main
for b in $(git branch -r | grep -v -e HEAD -e 'origin/main$' | sed 's#origin/##'); do git push -q origin --delete "$b"; done
{ git branch | grep -v -e '^\* main$' -e '^  main$' | xargs git branch -q -D; } 2>/dev/null || true

ci() { gh api repos/$R/statuses/"$(git rev-parse "origin/$1")" -f state="$2" -f context=ci >/dev/null; }
num() { gh pr view -R $R "$1" --json number -q .number; }

# mine <branch> <base> <title> [--draft]
mine() {
    git switch -q -c "$1" "$2"
    echo "$3" > "$1.txt"
    git add -A && git commit -q -m "$3" && git push -q -u origin "$1"
    gh pr create -R $R --base "$2" --head "$1" --title "$3" --body "Lab scenario." ${4:-} >/dev/null
    git switch -q main
}

# Runs the bot workflow and waits for it to finish.
bot() {
    local before
    before=$(gh run list -R $R --workflow bot.yml -L 1 --json databaseId -q '.[0].databaseId // 0')
    gh workflow run -R $R bot.yml "$@" >/dev/null
    local id=$before
    while [ "$id" = "$before" ]; do sleep 3; id=$(gh run list -R $R --workflow bot.yml -L 1 --json databaseId -q '.[0].databaseId // 0'); done
    gh run watch -R $R "$id" --exit-status >/dev/null
}

echo "My PRs"
mine wait main "Waiting for review"
mine ci-fail main "CI failing"
mine ci-running main "CI still running"
git switch -q -c conflict main && sed -i '' 's/line two/line two, edited on the branch/' shared.txt
git commit -q -am "Conflicts with main" && git push -q -u origin conflict
gh pr create -R $R --base main --head conflict --title "Conflicts with main" --body "Lab scenario." >/dev/null
git switch -q main
mine changes main "Changes requested by the bot"
mine ready main "Approved and ready to merge"
mine draft main "A draft on its own" --draft

# Stack 1: root, approved middle, draft top that conflicts with the middle.
mine stack-root main "Stack root"
mine stack-mid stack-root "Stack middle, approved"
git switch -q -c stack-top stack-mid && echo "top's version" > stack-mid.txt
git commit -q -am "Stack top, draft with conflicts" && git push -q -u origin stack-top
gh pr create -R $R --base stack-mid --head stack-top --title "Stack top, draft with conflicts" --body "Lab scenario." --draft >/dev/null
git switch -q stack-mid && echo "middle's newer version" > stack-mid.txt && git commit -q -am "Change the middle under the top" && git push -q
git switch -q main

# Stack 2: quiet root with a failing child, so the collapsed root has to show it.
mine quiet-root main "Quiet root, failing child below"
mine failing-child quiet-root "Failing child"

echo "Bot PRs"
bot -f action=open -f branch=bot-review -f title="Needs your review" -f reviewer="$ME"
bot -f action=open -f branch=bot-ready -f title="You approved, ready to merge"
bot -f action=open -f branch=bot-stale -f title="Your approval went stale"
bot -f action=open -f branch=bot-ci-fail -f title="You approved, CI failing"
bot -f action=open -f branch=bot-changes -f title="You requested changes"

echo "Moving main so branches fall behind and one conflicts"
sed -i '' 's/line two/line two, edited on main/' shared.txt
git commit -q -am "Advance main" && git push -q origin main

echo "Reviews"
bot -f action=changes -f pr="$(num changes)"
bot -f action=approve -f pr="$(num ready)"
bot -f action=approve -f pr="$(num stack-mid)"
gh pr review -R $R "$(num bot-ready)" --approve -b "Lab approval." >/dev/null
gh pr review -R $R "$(num bot-stale)" --approve -b "Lab approval." >/dev/null
gh pr review -R $R "$(num bot-ci-fail)" --approve -b "Lab approval." >/dev/null
gh pr review -R $R "$(num bot-changes)" --request-changes -b "Lab: please change this." >/dev/null
bot -f action=push -f branch=bot-stale

echo "CI"
git fetch -q origin
for b in wait conflict changes ready draft stack-root stack-mid quiet-root bot-review bot-ready bot-stale bot-changes; do ci "$b" success; done
ci ci-fail failure
ci failing-child failure
ci bot-ci-fail failure
ci ci-running pending
echo "Done"
