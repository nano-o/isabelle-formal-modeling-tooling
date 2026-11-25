# Validation records

`stable` names the commit that appended the newest entry below. There is
none yet: the next validation record starts the list. Each entry
is a validation record commit: the commit at which the fixtures below
passed, plus the entry itself. The mechanical checks are rerun at exactly
that commit before `stable` moves to it.

The records from 2026-09-29 to 2026-10-29 ran earlier fixtures and are in
Git history: `git show f5460ce:docs/validation.md`.

## Fixtures

Run the acceptance fixtures in a fresh Git repository and a small existing
codebase. Use isolated host configurations on Claude Code and Codex CLI
and start sessions from the checkout root and a subdirectory. Run Codex
fixtures at medium reasoning effort in the background with stdin closed.

Confirm skill, agent and I/Q discovery, including the root `.mcp.json` and
symlinked skill aliases from a subdirectory. In link mode, make a skill edit
in the development worktree and confirm a fresh host session sees it. Run
`sync` to restore the copies and confirm the tree is clean. Connect through
I/Q and delegate one smoke proof to the worker.

Exercise the command interface: `skills show` emits exactly the selected
Git object's bytes, with no provenance on stdout; `skills list` reports the
same revision; inspection works without a prover or network. Cover the
project pin when the tooling checkout has a different `HEAD` or uncommitted
skill edits, inspection outside a project (reads `stable`), unknown skill
names, malformed descriptors and missing pinned objects. Check that `init`
installs the complete integration at `stable`, `sync` preserves the pin, and
only `update` changes it. Include a skill with a supporting reference file,
to show that installation preserves the directory and not just `SKILL.md`.

Installer tests cover unrelated MCP servers, TOML content outside the
managed block, unmanaged collisions, edited owned entries, blocks and files,
obsolete entries, missing pinned commits, runtime mismatch, a pre-existing
root `AGENTS.md`, `CLAUDE.md` as a symlink and as a regular file, refusal
with unstaged or untracked managed paths, concurrent installer runs,
destinations on another filesystem than the temporary directory, and an
injected failure after each publication step, including during Isabelle
`init`'s session scaffold: the printed commands restore the tree, `check`
and doctor fail until they do, and a retry then succeeds. Adoption runs
`update` against a snapshot of the offer-exchange checkout (a linked
worktree at its current commit), with its own `.claude/skills/`, root
`AGENTS.md` and `CLAUDE.md` symlink. Confirm that doctor is read-only by
checking Git status and listing files in the project and runtime checkouts
before and after.

In fresh sessions started at the root and in a subdirectory, list the
worker profiles and tools each host offers, and have the proof worker
attempt an I/Q call, which must be unavailable to it. Exactly one worker
definition and one main-session `iq` server may be visible, so that a
passing smoke proof cannot hide a user-level or plugin duplicate.
