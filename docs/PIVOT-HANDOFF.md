# Godot Pivot — Handoff Script

> I can edit docs and Godot files via MCPs but I can't reach your git repo or run `gh` commands. Run this on your machine to land the rearrangement and open the PR. Read it through before executing — there are decisions in step 3 (repo layout) you'll want to verify match your taste.

## What I already changed (via MCPs)

- **Linear**: 15 Roblox-era issues canceled with handover comments. M1/M2/M3 milestones renamed for the Godot direction. M4 milestone created. 22 new active issues spread across the four milestones — all with acceptance criteria and design-system / architecture references.
- **Docs in `game1/`**: rewrote `README.md` for Godot architecture; surgical edit on `VISION.md` Platform section; rewrote `v0.1-SPEC.md` as a retrospective; replaced the Roblox primitives table in `design-prompt-implementation.md` with Godot equivalents.

These doc changes need to land in the repo via the steps below.

## Step 1 — Pull the worktree branch onto a clean branch

You merged the Godot prototype into the worktree at `.claude/worktrees/heuristic-lichterman-af95c3/`. Either continue on that branch or create a fresh one off it for the pivot work.

```bash
cd C:\Users\aidan\workspace\goose-and-buff
git fetch
# Option A: continue on the existing worktree branch
git -C .claude/worktrees/heuristic-lichterman-af95c3 checkout -b chore/godot-pivot
# Option B: cherry-pick the prototype into a fresh branch off main
git checkout main
git pull
git checkout -b chore/godot-pivot
git merge heuristic-lichterman-af95c3   # or whatever the worktree branch name is
```

Pick the path that's easier given how you set the worktree up.

## Step 2 — Pick a repo layout and apply it

The Godot project currently lives at `godot-prototype/`. Two reasonable layouts:

**Layout A: Godot at repo root** (recommended — simplest for IDEs, gh actions, Godot's `project.godot` resolves cleanly)

```
.
├─ project.godot
├─ scenes/
├─ scripts/
├─ data/
├─ assets/
├─ addons/
├─ docs/                  ← move game1/* here
├─ design/                ← keep the design-system bundle
├─ archive/
│   └─ roblox/            ← any old Roblox source files preserved for history
├─ README.md              ← top-level, points to docs/
├─ .gitignore             ← Godot-flavored
└─ LICENSE
```

**Layout B: Godot in subfolder** (cleaner separation if you want multiple top-level concerns; slightly more friction for tools)

```
.
├─ game/                  ← project.godot lives here
├─ docs/
├─ design/
├─ archive/roblox/
├─ README.md
├─ .gitignore
└─ LICENSE
```

I'd default to **Layout A**. Less ceremony.

### Apply Layout A (commands)

```bash
cd C:\Users\aidan\workspace\goose-and-buff   # or the worktree if you stayed on it

# 1. Hoist Godot files to repo root.
git mv godot-prototype/project.godot project.godot
git mv godot-prototype/scenes scenes
git mv godot-prototype/scripts scripts
git mv godot-prototype/data data
git mv godot-prototype/assets assets
git mv godot-prototype/addons addons      # (will fail silently if empty / nonexistent — fine)
git mv godot-prototype/PROTOTYPE-NOTES.md docs/PROTOTYPE-NOTES.md
rmdir godot-prototype                     # only if empty after the moves

# 2. Move docs out of game1/ into a top-level docs/ folder.
mkdir -p docs
git mv game1/*.md docs/
rmdir game1

# 3. Hoist top-level README. (The repo-root README is the doorway file.)
git mv docs/README.md README.md

# 4. Archive any Roblox source that survived the merge.
mkdir -p archive/roblox
# (only run these if the files still exist — adjust paths as needed)
git mv src/server archive/roblox/server 2>/dev/null || true
git mv src/shared archive/roblox/shared 2>/dev/null || true
git mv default.project.json archive/roblox/default.project.json 2>/dev/null || true
git mv *.rbxlx archive/roblox/ 2>/dev/null || true

# 5. Add a Godot-flavored .gitignore (see below for the contents).
```

### `.gitignore` for Godot

Create or merge this into your `.gitignore`:

```gitignore
# Godot 4 — editor and import caches
.godot/
.import/
*.import

# Exported builds
build/
exports/
*.pck
*.exe
*.app
*.dmg
*.zip

# OS / IDE
.DS_Store
Thumbs.db
.vscode/
.idea/
*.swp

# User save data (don't ship these)
saves/
user_data/

# Roblox leftovers (in case any survive)
*.rbxl
*.rbxlx
*.rbxm
*.rbxmx
sourcemap.json
Packages/
ServerPackages/
DevPackages/
```

## Step 3 — Verify the project still opens cleanly in Godot

Before committing, open `project.godot` in Godot 4 and confirm:

- [ ] No broken references in `scenes/main.tscn` (paths to scripts / assets all resolve)
- [ ] Press F5 and the game runs as before (Buffalo solo, 5-card hand, 3 waves, win/loss)
- [ ] No new console errors

If any path broke from the move, the editor will offer to fix references — accept and resave the affected scene.

## Step 4 — Commit and push

```bash
git add -A
git commit -m "Pivot to Godot: rearrange repo, update docs, archive Roblox source

- Move Godot project from godot-prototype/ to repo root
- Move docs from game1/ to top-level docs/
- Archive Roblox source under archive/roblox/
- Rewrite README, v0.1-SPEC for Godot architecture
- Update design-prompt-implementation.md with Godot primitives mapping
- Add Godot-flavored .gitignore

Linear: M1/M2/M3 renamed for Godot direction; M4 (Multiplayer) created;
22 new issues spread across the four milestones."

git push -u origin chore/godot-pivot
```

## Step 5 — Open the PR

```bash
gh pr create \
  --title "Pivot to Godot — repo rearrangement + doc rewrite" \
  --body-file - <<'EOF'
## Summary

Pivots the project from Roblox to Godot 4. Rearranges the repo for Godot conventions, rewrites the load-bearing docs, archives the Roblox source for posterity.

## What's in this PR

- **Repo layout** — Godot project hoisted from `godot-prototype/` to repo root. Docs moved from `game1/` to `docs/`. Roblox source archived to `archive/roblox/`. Added Godot-flavored `.gitignore`.
- **README** — full rewrite for Godot architecture: scene layout, GDScript signal-based APIs, Godot-flavored conventions and anti-patterns, voice rules retained verbatim.
- **VISION** — Platform section rewritten: Godot 4, 2D-first, MultiplayerAPI for the 3-player networking, the architectural discipline that made the pivot cheap.
- **v0.1-SPEC** — repurposed as a retrospective covering what shipped in the prototype, what's stubbed, what carried over architecturally.
- **design-prompt-implementation** — replaced the Roblox primitives table with Godot equivalents (Control / PanelContainer / StyleBoxFlat / Theme / VBoxContainer / etc.).
- **Code** — no functional changes; just the path moves above.

## Linear

- Old Roblox-era milestones (M1/M2/M3) renamed: M1 — Solo loop complete (all 3 heroes), M2 — Solo depth + 30-minute session, M3 — Visual polish + audio.
- New milestone created: M4 — Multiplayer co-op.
- 15 Roblox-specific issues canceled with handover comments referencing the new direction.
- 22 new active issues spread across the four milestones.

## Verification

- [ ] `project.godot` opens cleanly in Godot 4
- [ ] Game runs end-to-end: Buffalo solo, 5-card hand, 3 waves, win/loss
- [ ] No new console errors
- [ ] No broken scene/script/asset references after the move

## What's intentionally NOT in this PR

- Any new gameplay code (M1+ work goes in subsequent PRs against this branch's merge)
- Real illustrations / animations / sound (M3 work)
- Multiplayer plumbing (M4 work)
- Real fonts loaded (M3 work)
EOF
```

## Step 6 — Optional: clean up

After merge:

- Delete the worktree if you used one: `git worktree remove .claude/worktrees/heuristic-lichterman-af95c3`
- Delete the local pivot branch: `git branch -d chore/godot-pivot`

---

## If anything goes sideways

- **Godot can't find a script after the move**: Godot stores `.uid` files alongside scripts and `.tscn` files reference resources by path. After moving, open the scene in Godot and let it auto-fix paths, or grep `*.tscn` for the old path and replace.
- **Imports fail on first open**: Godot's `.import/` cache regenerates on first open. Let it finish; restart the editor if scenes load before imports complete.
- **`gh pr create` errors with auth**: run `gh auth login` first.
- **Worktree merge has conflicts**: the only realistic conflict is between my doc rewrites in `game1/` and any in-flight changes in the worktree. Take my versions if so — they're the post-pivot canonical text.

Ping me when the PR is open or if any step needs unsticking.
