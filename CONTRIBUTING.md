# Contributing

1. Read `PLAN.md` (scope, art direction, card table) and `ARCHITECTURE.md` (binding conventions)
   first.
2. Keep each change PR-sized and scoped to one card or feature. Do not refactor unrelated code in
   the same PR.
3. Run the checks listed in `ARCHITECTURE.md` and include the exact commands and results in the
   PR description. Visual or level changes must attach rendered captures from `tools/capture/`.
4. Never commit secrets, API keys, `.godot/` caches, `.worktrees/` or local editor settings.
5. New third-party assets must be CC0 and credited in `assets/CREDITS.md`. Generated assets must
   be declared in `assets/manifest.yaml`, with their spend logged in `assets/meshy-ledger.jsonl`.
6. Use Conventional Commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`).
