Never run git commands: add, commit, push, pull, merge, rebase, checkout, branch, stash, or PR creation. The human does all git.

Before editing, confirm `frontend/pubspec.yaml` and `backend/api/main.py` exist in the current directory. If either is missing, stop. Quote the repo path; it may contain spaces.

Only edit folders your task names. Ownership is in `CONTEXT.md`.

Never install SDKs, tools, or packages inside the repo. Do not create `.tools/` or download Flutter, Dart, or Python into the repo.

Never add dependencies to `pubspec.yaml` or `requirements.txt` unless the task explicitly allows it.

Never weaken or delete a test to make it pass.

If tests cannot run because of network access or a missing tool, say so. Never claim they passed unless they did.

Finish with the files changed, what changed in each, and how to run or test. State assumptions.
