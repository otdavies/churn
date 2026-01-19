# Churn

**Persistent memory and iterative refinement for Claude Code.**

Claude Code loses context at compaction. Churn fixes this by extracting flagged items before compression and injecting them back at session start. It also provides `/churn N` for automated work/review cycles with build validation and auto-revert on failure.

## Features

- **Memory persistence** - Flag important context with `[FLAG:x]` markers; extracted pre-compaction, injected at session start
- **Iterative refinement** - `/churn 10` spawns subagent loops alternating work and review phases, with automatic build validation
- **Git workflow** - Branch-scoped memory, auto-commits per iteration, squash-and-rename on completion

## Install

Requires `jq` for JSON processing:

```bash
# Install jq (if not already installed)
brew install jq          # macOS
# or: apt-get install jq  # Linux

# Clone and install
git clone https://github.com/user/churn.git  # or your fork
cd churn                                      # directory name from clone
bash install.sh
```

Installs to `~/.claude/`: memory files, hooks (session_start, pre_compact, session_end), and commands (churn, churn-done, churn-push). Existing `settings.json` is backed up before modification.

---

## Architecture

```
SESSION LIFECYCLE

  SessionStart ──────> Work ──────> PreCompact ──────> Compaction
       │                │                │                  │
       │ inject         │ [FLAG:x]       │ extract flags    │ compress
       │ context        │ markers        │ capture snapshot │ transcript
       │                │                │ extract traces   │
       v                v                v                  v
  ┌─────────────────────────────────────────────────────────────┐
  │                      MEMORY LAYERS                          │
  ├─────────────────────────────────────────────────────────────┤
  │  GLOBAL (~/.claude/memory/)                                 │
  │    self-model.md     - Claude's learned style               │
  │    global-index.md   - Session history                      │
  │    traces/           - Extracted reasoning                  │
  │                                                             │
  │  PROJECT (~/.claude/projects/[path]/)                       │
  │    flagged.md        - Auto-extracted from [FLAG:x] markers │
  │    working.md        - Session state                        │
  │    shadow-repo/      - Project snapshots                    │
  │                                                             │
  │  BRANCH (.../branches/[branch]/)                            │
  │    working.md        - Branch-specific state                │
  └─────────────────────────────────────────────────────────────┘
```

---

## Memory Files

| File | Scope | Updated By | Purpose |
|------|-------|------------|---------|
| self-model.md | Global | Manual (session count auto-incremented) | Claude's style and preferences |
| flagged.md | Project | Auto (pre_compact.sh) | Flags extracted before compaction |
| working.md | Branch | Auto (save.sh) or manual edit | Session state, preserved turns |

### Flag Markers

Write these inline during work. Extracted to `flagged.md` before compaction:

```
[FLAG:prompt] Original task description
[FLAG:progress] Current status
[FLAG:decision] Key choice + rationale
[FLAG:diff] Important file changes
[FLAG:blocker] What's blocking progress
[FLAG:note] Other context
```

---

## Churn Workflow

```
/churn 10              # 10 iterations (Work/Review alternating)
/churn 10 --linear     # 10 iterations (Work only)
/churn task            # Run until DONE (max 50)
```

### Iteration Cycle

```
┌─────────────────────────────────────────────────────────────┐
│  WORK (odd: 1,3,5...)           REVIEW (even: 2,4,6...)     │
│  - Read docs/CHURN_PLAN.md      - Check for drift:          │
│  - Choose most important task     - Plan drift              │
│  - Execute one focused change     - Doc drift               │
│  - Commit: churn [N]: [desc]      - Test drift              │
│  - Return: DONE/NEXT              - Scope drift             │
│                                   - Goal drift              │
│                                 - Fix small issues          │
└─────────────────────────────────────────────────────────────┘
                              │
                              v
┌─────────────────────────────────────────────────────────────┐
│  VALIDATION (after each iteration)                          │
│  - Run build command (auto-detected)                        │
│  - If build fails: STOP                                     │
│  - If errors increase: git revert HEAD --no-edit            │
│  - Build broken 2x in a row: STOP                           │
└─────────────────────────────────────────────────────────────┘
```

### Git Flow

```
/churn 10 refactor auth
    │
    └── creates: churn/refactor-auth-0119-1430
                 docs/CHURN_PLAN.md

    ... iterations commit: "churn [N]: description" ...

/churn-done
    │
    └── squashes commits, renames to: feature/refactor-auth

/churn-push
    │
    └── pushes, optionally creates PR via gh
```

### Build Detection

| File | Command |
|------|---------|
| package.json | `npm run typecheck` or `npm run build` |
| Cargo.toml | `cargo check` |
| go.mod | `go build ./...` |
| Makefile | `make check` or `make build` |
| pyproject.toml | `python -m py_compile` |

---

## Commands

| Command | Purpose |
|---------|---------|
| `/churn N [desc]` | Run N iterations of subagent work |
| `/churn-done` | Squash commits, rename branch |
| `/churn-push` | Push to remote, optionally create PR |

## Hooks

| Hook | Trigger | Purpose |
|------|---------|---------|
| session_start.sh | SessionStart | Inject memory context (4KB max) |
| pre_compact.sh | PreCompact | Extract flags, capture snapshot, extract traces |
| session_end.sh | SessionEnd | Log session to index |
| git.sh | Manual | Git operations for churn workflow |
| snapshot.sh | Auto/Manual | Shadow repo for project state tracking |
| trace.sh | Auto | Extract reasoning from transcripts |
| query.sh | Manual | Search past reasoning traces |
| save.sh | Manual | Append to working.md |

---

## Directory Structure

```
~/.claude/
├── memory/
│   ├── self-model.md
│   ├── global-index.md
│   └── traces/
├── projects/[encoded-path]/
│   ├── memory/
│   │   ├── flagged.md
│   │   ├── working.md
│   │   └── branches/[branch]/working.md
│   └── shadow-repo/
├── memory-hooks/
│   └── *.sh
├── commands/
│   └── churn*.md
└── settings.json
```

---

## Troubleshooting

**Hook not running:** Check `~/.claude/settings.json`, ensure scripts are executable.

**Context not loading:** Verify files exist in `~/.claude/memory/` and project path encoding matches.

**Shadow repo errors:** `bash ~/.claude/memory-hooks/snapshot.sh reset`

**Recovery after failed squash:** `bash ~/.claude/memory-hooks/git.sh abort-finalize`

## Uninstall

```bash
bash uninstall.sh
```

Memory files preserved unless you delete `~/.claude/memory/` and `~/.claude/projects/`.
