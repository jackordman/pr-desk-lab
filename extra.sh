#!/usr/bin/env bash
# Adds a wider spread of PRs on top of the base lab: repeats of every state, big and long ones,
# deep and branching stacks, more bot PRs. Additive, no reset. scenarios.sh runs it last.
set -euo pipefail
cd "$(dirname "$0")"
R=jackordman/pr-desk-lab
ME=$(gh api user -q .login)

ci() { gh api repos/$R/statuses/"$(git rev-parse "origin/$1")" -f state="$2" -f context=ci >/dev/null; }
num() { gh pr view -R $R "$1" --json number -q .number; }

# mine <branch> <base> <title> [--draft] [lines]. Commits only its own file.
mine() {
    git switch -q -c "$1" "$2"
    if [ -n "${5:-}" ]; then seq 1 "$5" | sed "s/^/$1 line /" > "$1.txt"; else echo "$3" > "$1.txt"; fi
    git add "$1.txt" && git commit -q -m "$3" && git push -q -u origin "$1"
    gh pr create -R $R --base "$2" --head "$1" --title "$3" --body "Lab scenario." ${4:-} >/dev/null
    git switch -q main
}

bot() {
    local before id
    before=$(gh run list -R $R --workflow bot.yml -L 1 --json databaseId -q '.[0].databaseId // 0')
    gh workflow run -R $R bot.yml "$@" >/dev/null
    id=$before
    while [ "$id" = "$before" ]; do sleep 3; id=$(gh run list -R $R --workflow bot.yml -L 1 --json databaseId -q '.[0].databaseId // 0'); done
    gh run watch -R $R "$id" --exit-status >/dev/null
}

git fetch -q origin && git switch -q main && git pull -q --ff-only

echo "More of my PRs"
mine big-diff main "Big diff: vendor a whole library" "" 2400
mine long-title main "A deliberately long title to see how truncation behaves when the PR title keeps going well past the width of the panel"
mine wait-2 main "Waiting for review, second one"
mine wait-3 main "Waiting for review, third one"
mine running-2 main "CI still running, second one"
mine running-3 main "CI still running, third one"
mine approved-ci-fail main "Approved, but CI failing"
mine ready-2 main "Approved and ready, second one"
mine ready-3 main "Approved and ready, third one"
git switch -q -c everything-wrong main && sed -i '' 's/line three/line three, edited on the branch/' shared.txt
git add shared.txt && git commit -q -m "Everything wrong at once" && git push -q -u origin everything-wrong
gh pr create -R $R --base main --head everything-wrong --title "Everything wrong at once: changes, conflicts and failing CI" --body "Lab scenario." >/dev/null
git switch -q -c approved-conflict main && sed -i '' 's/line one/line one, edited on the branch/' shared.txt
git add shared.txt && git commit -q -m "Approved, but conflicts" && git push -q -u origin approved-conflict
gh pr create -R $R --base main --head approved-conflict --title "Approved, but conflicts with main" --body "Lab scenario." >/dev/null
git switch -q main
mine draft-2 main "Draft, CI failing" --draft
mine draft-3 main "Draft, still sketching" --draft
mine draft-4 main "Draft with a big diff" --draft 900

echo "Stacks"
mine deep-1 main "Deep stack 1 of 4"
mine deep-2 deep-1 "Deep stack 2 of 4, approved"
mine deep-3 deep-2 "Deep stack 3 of 4, CI failing"
mine deep-4 deep-3 "Deep stack 4 of 4, draft" --draft
mine fork-root main "Branching stack root"
mine fork-a fork-root "Branching stack, left child"
mine fork-b fork-root "Branching stack, right child, CI failing"
mine quiet-1 main "All-quiet stack root"
mine quiet-2 quiet-1 "All-quiet stack child"

echo "Bot PRs"
bot -f action=open -f branch=bot-review-2 -f title="Needs your review, CI passing" -f reviewer="$ME"
bot -f action=open -f branch=bot-review-3 -f title="Needs your review, CI failing" -f reviewer="$ME"
bot -f action=open -f branch=bot-review-4 -f title="Needs your review, CI still running" -f reviewer="$ME"
bot -f action=open -f branch=bot-rerequest -f title="Re-requested after you commented" -f reviewer="$ME"
bot -f action=open -f branch=bot-ready-2 -f title="You approved, ready to merge, second one"
bot -f action=open -f branch=bot-ready-3 -f title="You approved, ready to merge, third one"
bot -f action=open -f branch=bot-stale-2 -f title="Your approval went stale, second one"
bot -f action=open -f branch=bot-changes-2 -f title="You requested changes, second one"

echo "Moving main forward a few commits"
sed -i '' 's/line three/line three, edited on main/' shared.txt
sed -i '' 's/line one/line one, edited on main/' shared.txt
git add shared.txt && git commit -q -m "Advance main, conflicting edits" && git push -q origin main
for i in 1 2 3 4; do echo "main $i" >> main-log.txt; git add main-log.txt; git commit -q -m "Advance main $i"; done
git push -q origin main

echo "Reviews"
bot -f action=changes -f pr="$(num everything-wrong)"
bot -f action=approve -f pr="$(num approved-ci-fail)"
bot -f action=approve -f pr="$(num approved-conflict)"
bot -f action=approve -f pr="$(num ready-2)"
bot -f action=approve -f pr="$(num ready-3)"
bot -f action=approve -f pr="$(num deep-2)"
gh pr review -R $R "$(num bot-rerequest)" --comment -b "Lab: a question first." >/dev/null
gh api -X POST repos/$R/pulls/"$(num bot-rerequest)"/requested_reviewers -f "reviewers[]=$ME" >/dev/null || echo "  (re-request refused, skipping)"
gh pr review -R $R "$(num bot-ready-2)" --approve -b "Lab approval." >/dev/null
gh pr review -R $R "$(num bot-ready-3)" --approve -b "Lab approval." >/dev/null
gh pr review -R $R "$(num bot-stale-2)" --approve -b "Lab approval." >/dev/null
gh pr review -R $R "$(num bot-changes-2)" --request-changes -b "Lab: please change this." >/dev/null
bot -f action=push -f branch=bot-stale-2

echo "CI"
git fetch -q origin
for b in big-diff long-title wait-2 wait-3 ready-2 ready-3 approved-conflict draft-3 deep-1 deep-2 fork-root fork-a \
         quiet-1 quiet-2 bot-review-2 bot-rerequest bot-ready-2 bot-ready-3 bot-stale-2 bot-changes-2; do ci "$b" success; done
for b in approved-ci-fail everything-wrong draft-2 deep-3 fork-b bot-review-3; do ci "$b" failure; done
for b in running-2 running-3 bot-review-4; do ci "$b" pending; done
echo "Done"
