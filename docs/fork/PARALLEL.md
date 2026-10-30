# Parallel work (fork only)

How agents work on this fork: three roles (lead, worker, helper), native subagents in isolated APFS clones. Everything under `.omp/`, `docs/fork/`, `tools/fork/`, `third_party/voidlink/` and `app/Madeira/VLTouch/` is fork-only and never goes upstream.

## Branches

| Branch | Content | Who moves it |
|---|---|---|
| `main` | exact mirror of `willfaust/Madeira` `main`; never commit here | lead: `git fetch upstream && git merge --ff-only upstream/main` |
| `fork/main` | `main` + fork tooling + our features; workers start here | lead only (merges) |
| `omp/task/<name>` | one worker's commits, captured by omp | the worker; lead deletes after merge |
| `upstream-pr/<topic>` (later) | a feature cut from `main` for an upstream PR, without fork tooling | lead, with user approval |

## Roles

| Role | Job | Model | May |
|---|---|---|---|
| Lead (exactly one) | plan, contracts-first ordering, task prompts, review, merge, full native builds | `default` → Claude Opus 5.5 | start workers and helpers; only one who merges into `fork/main`; no feature code — its own commits are merges, docs and lead tooling |
| Worker (`worker`) | one task on its own branch: model, persistence, input sink, tooling | `worker` → Muse Spark 1.3 Contributor | edit its file set, commit, start helpers |
| UI worker (`ui-worker`) | same for UIKit/SwiftUI: widgets, editor, overlay integration | `ui` → Claude Sonnet 5.5 | edit its file set, commit, start helpers |
| Helper (`scout`, `sonic`, `task`) | look-ups, small mechanical edits | `task` → DeepSeek V4.1 Flash (fallback Haiku 5.5) | `scout` read only; `sonic` small edits |
| Helper (`reviewer`) | diff review | `review` → Claude Haiku 5.5 | read only |

- **User**: approves plans and pushes, tests every merged build on the iPhone (the only real acceptance test), sends logs.
- **Advisor**: attached to every worker (`advisor: true`), Opus at medium effort, every 4th turn, rules in `.omp/WATCHDOG.md`.
- Chain depth is capped at lead → worker → helper (`task.maxRecursionDepth: 2`). Role comes from agent type, not depth: a scout the lead starts is still a helper.

## Parallelism

- Workers: up to 4 by default; up to 7 in the touch-port wave (P3) when file sets are disjoint and the contract is merged. The limit is review and the 2-build lock, not tokens.
- Inside a worker: as many helpers as useful, in parallel — scouts for look-ups, several `sonic` helpers on different files, one reviewer before finishing. Helpers share the worker's clone, so never two on one file; helpers never build.
- Lead-level research (P1) fans out to parallel scouts directly.

## Builds and disk

- Full native build (`tools/build-ipa.sh`, hours, LLVM ×2 + FEX + Wine + DXMT): lead only, in the primary checkout `~/Developer/Madeira`.
- Workers get the build caches through the APFS clone (copy-on-write) and only rebuild the app target: `tools/fork/app-check.sh` (from P2). It holds a machine-wide lock so at most 2 `xcodebuild`s run at once (16 GB RAM, fanless M4).
- Never clean caches in a clone; never touch submodules.

## Shared registries (one owner per wave)

- `app/Madeira.xcodeproj/project.pbxproj` — Madeira lists files by hand (no synchronized folders). All new files are registered once in the contract task; workers never add files.
- `app/Madeira/Madeira-Bridging-Header.h` — same: all VoidLink ObjC headers added in the contract task.
- `app/Madeira/ContentView.swift` — 4,900 lines, changes upstream constantly; one minimal hook, owned by the integration task only.

## Dispatch (lead)

1. Contract task first when workers share types; merge it.
2. Lead tree clean (`git status --short` empty) before spawning; uncommitted files leak into clones.
3. One `task` call, items `agent: "worker"`/`"ui-worker"`, `isolated: true`, unique `name` never reused. Task text: `Files you may change: …`, why, numbered changes (one commit each), acceptance commands.
4. Review: `git diff <base>..omp/task/<name>`, transcript `history://<name>`, re-run `tools/fork/app-check.sh` yourself, then a `reviewer` helper ("every requirement met? correctness gaps only").
5. Merge one branch at a time into `fork/main`, app-check after each merge, delete the branch. Push only with user approval.
6. Fix round: new worker whose task starts with `git cherry-pick <base>..omp/task/<name>`.

## Gotchas

- Start the lead with `cd ~/Developer/Madeira && omp`; project agents load only from the session cwd.
- Native workers stop when the lead process exits (`omp --restore` resumes).
- `omp config get modelRoles` checks roles; `omp config list | grep -E "isolation|prewalk"` checks isolation.
