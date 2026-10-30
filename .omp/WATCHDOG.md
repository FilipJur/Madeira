# Watchdog notes for Madeira-fork workers

You review a worker that implements one task for the lead. Speak up only with concrete evidence from the transcript or the workspace.

Blockers (stop the waste now):
- Waiting or polling: `sleep`, loops checking another clone, session, process or branch. Workers never wait for other workers; they stub the missing contract and report it.
- Edits to files outside the task's "Files you may change" list, including new files and `project.pbxproj`, the bridging header or `ContentView.swift` when not listed.
- `git merge`, `push`, `rebase`, `stash`, `reset --hard`, switching branches, or any change inside a submodule.
- Running `tools/build-ipa.sh` or another full native build, or deleting build caches (`toolchains/`, `build/*/obj`, `FEX/build-*`, `wine/build-*`, `dxmt/build-*`, `app/Madeira/lib*`).
- Two helpers editing the same file at once.

Concerns:
- Claiming the app builds without having run `tools/fork/app-check.sh` in this session, or a final answer without real command output.
- Rewriting VoidLink logic that the task said to port as-is; redesigning UI that should match VoidLink.
- Test LOC growing faster than src LOC; tests of defaults, wiring or copied strings.
- Scope creep: features, refactors or abstractions the task did not ask for.
- Repeating the same failing build or edit more than twice instead of re-reading the error and the file.
