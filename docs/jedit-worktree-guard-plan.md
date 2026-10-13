# Plan: knowing which checkout jEdit owns

Proposed on 2026-10-12. Not yet reviewed.

The occasion is a project whose Git repository was converted to the `.bare`
layout: the repository lives in `PROJECT/.bare`, `PROJECT/.git` reads
`gitdir: ./.bare`, and every checkout, `main` included, is a linked
worktree. The human's jEdit runs in one of those linked worktrees. The
conversion itself needed nothing from the tooling. It exposed a guard that
never worked for this project, and does not work for any project whose
jEdit is outside Git's original checkout.

## The problem

The tooling says "main worktree" when it means the checkout whose theories
jEdit and I/Q are editing. The `ic2-prover` worker recognises that checkout
by Git's layout (`agents/ic2-prover.instructions.md`, "Assigned
worktree"):

```bash
git -C <worktree> rev-parse --absolute-git-dir
git -C <worktree> rev-parse --path-format=absolute --git-common-dir
```

and proceeds when the two differ. Two layouts break that test:

- jEdit in a linked worktree, `.bare` or not. The test lets a worker into
  jEdit's checkout. This was already true of the project above before the
  conversion.
- The `.bare` layout. Every checkout is linked, so the test never refuses.

A worker that gets in edits `.thy` files on disk, and jEdit's open buffers
fall out of sync with them. Today the only real safeguard is that the
coordinator never assigns jEdit's checkout.

Nothing else in the tooling depends on the layout. At `80d6118`:

- `scripts/project_files.py` finds the project with `git rev-parse
  --show-toplevel`.
- `scripts/common.sh` derives ic2 server names from the checkout path.
- The installer lock uses `git rev-parse --git-path project-files.lock`,
  one per checkout.
- agent-board keeps its board under `--git-common-dir`, shared by all
  checkouts as intended.

## Goal and definition of done

Stop inferring the role from Git's layout. Record it, and refuse unless the
record says "ic2 worktree".

The marker says where ic2 may work; it does not keep jEdit out. The hazard
is two writers on one checkout at the same time, so each side checks
whether the other is live there now. An ic2 worktree whose server has
stopped can be opened in jEdit to inspect the result, and ic2 can work in
it again once that jEdit exits.

Done means:

- `ic2.sh preflight` exits non-zero in every checkout except a marked ic2
  worktree that is not jEdit's write root, in a normal repository and in a
  `.bare` one.
- The `ic2-prover` instructions run `preflight` instead of comparing Git
  directories.
- `ic2.sh start` and `check` refuse in a checkout that is a live jEdit write
  root.
- `launch_jedit.sh` records which checkout jEdit owns and refuses to launch
  in a checkout whose ic2 server is running. It launches in a marked ic2
  worktree whose server has stopped.
- No text calls jEdit's checkout "the main worktree".
- `make validate` passes and the regenerated agent files match their source.

## 1. Mark ic2 worktrees when they are created

Add `ic2.sh worktree add <path> -b <branch> [<base>]`, which runs `git
worktree add` and then writes a marker. Add `ic2.sh worktree mark` for a
worktree that already exists.

The marker lives at `$(git rev-parse --git-path
isabelle-tooling/ic2-worktree)`:

- That path is in Git's per-worktree data, outside the working tree, so the
  marker cannot be committed and does not carry over to other checkouts.
  For a linked worktree it is `<common>/worktrees/<name>/`.
- In a jai sandbox the Git data is mounted read-only, so the worker cannot
  create the marker itself.

## 2. Replace the Git comparison with `ic2.sh preflight`

`preflight` exits non-zero unless the checkout has the marker and is not
jEdit's write root (step 3). The prover instructions then say: run
`preflight`; if it fails, stop and report a blocker.

- Edit the source `agents/ic2-prover.instructions.md`, then run
  `scripts/render-agents.sh` to regenerate `extension/agents/ic2-prover.md`
  and `extension/agents/ic2_prover.toml`.
- `ic2.sh start` and `check` call the same jEdit test and refuse in a live
  jEdit write root. A worker started while you inspect its worktree in
  jEdit therefore stops with a blocker; close that jEdit and ic2 can work
  there again.

## 3. Have `launch_jedit.sh` record which checkout jEdit owns

`launch_jedit.sh` already knows the write root: it passes it to jEdit as
`IQ_MCP_ALLOWED_ROOTS`. It writes its pid and that root to `$(git
rev-parse --git-path isabelle-tooling/jedit)`. The script ends with `exec`,
so that pid becomes jEdit's and nothing runs on exit to remove the file. A
record whose pid is dead counts as no record, which is what lets ic2 work
in a checkout again after its jEdit closes.

It refuses to launch while this checkout's ic2 server is running: the
server is named after the checkout (`ic2.sh name`), and `isabelle ic2
server status -n NAME` reports its pid. The marker alone is no reason to
refuse. The `ic2-prover` instructions already have the worker stop its own
server when it finishes, so a finished worktree opens normally. When an
ic2 server was left running after its work ended, the message says to run
`ic2.sh stop` in that checkout first.

A plain `isabelle jedit` skips all of this. That is why step 1's marker is
the real safeguard and this step is a backstop.

## 4. Rename "main worktree" to "jEdit worktree"

- `extension/skills/isabelle-proving/SKILL.md`: the frontmatter
  description, the two workflow bullets and the sentence after them, the
  delegation section ("inspects the main worktree first"), and the
  `token:jedit` description.
- `extension/skills/isabelle-modeling/SKILL.md`, the paragraph that defers
  theory editing to `isabelle-proving`.
- `agents/ic2-prover.instructions.md`: the opening paragraph, "Assigned
  worktree", the I/R sentence under "Tooling", and the `token:jedit`
  sentence.
- `scripts/render-agents.sh`: the `DESCRIPTION` string and the comment above
  `[mcp_servers.iq]`.
- `docs/jai-agent-isolation.md`: replace `-r "$MAIN/.git"` with the path
  from `git rev-parse --path-format=absolute --git-common-dir`, and use
  `ic2.sh worktree add` in the examples. The examples still name a
  submodule and a per-project ic2 script from before the tooling clone
  existed; bring them up to date at the same time.

## 5. Tests

In `tests/ic2_test.sh`, `preflight` refuses in:

- an unmarked main checkout;
- an unmarked linked worktree (the bug: today's test passes it);
- a marked worktree that is jEdit's write root.

It passes in a marked linked worktree, in a normal repository and in a
`.bare` one. After marking, `git status` is still clean.

`launch_jedit.sh` cases, using `--dry-run` or a stub `--isabelle`
executable so no real jEdit starts:

- refuses in a checkout whose ic2 server is running;
- launches in a marked ic2 worktree whose server has stopped, and the stub
  run writes the jEdit record;
- after that, `preflight` and `ic2.sh start` refuse in the worktree while
  the recorded pid is alive, and pass once it is dead.

Rerun
`tests/extension_manifest_test.py` to confirm the regenerated agent files
match their source.

## 6. Order of work

1. Steps 1 to 5 on this branch, which starts at `stable` (`80d6118`, one
   commit ahead of `main`). `make validate` and `make check-isabelle` pass
   at its end.
2. Validation and the validation record, as `docs/validation.md`
   describes; then fast-forward `stable`.
3. Adoption: in each project that uses the tooling, `isabelle-tooling
   update REV` and commit, then `ic2.sh worktree mark` in each existing ic2
   worktree. The project-specific steps are kept outside this repository,
   since these docs name no private projects or local paths.

## 7. Optional: the shared I/Q port

Every checkout's `.mcp.json` uses I/Q bridge port 8765, so every agent
session on the machine reaches the one jEdit, including sessions in other
repositories. I/Q refuses writes only outside jEdit's write root. So a
session in another checkout, or another repository, can read jEdit's
buffers and edit them inside that root.

Once step 3 exists, `extension/bin/iq-bridge.sh` could refuse to start
unless its checkout is the one jEdit recorded. The root cause is the same:
nothing records which checkout owns jEdit.

## Open questions

- **The jai sandbox.** `docs/jai-agent-isolation.md` calls the read-only
  mount of the common Git directory optional. `preflight` needs it to read
  the marker. Proposed: make it required, since the worker's Git commands
  need it anyway.
- **A second jEdit.** Inspecting an ic2 worktree means running jEdit in it,
  while the usual jEdit may still be open on another checkout. Both would
  use I/Q port 8765. Check what `launch_jedit.sh` and the I/Q plugin do
  with a second jEdit today, and whether to close the first one or give
  the second its own port. Opening the worktree's theories in the existing
  jEdit is no substitute: both checkouts have the same session and theory
  names.
- **Existing checkouts.** Which existing checkouts are ic2 worktrees and get
  marked during adoption is a per-project question, answered outside this
  repository.

## History

**2026-10-12.**

- Drafted in a session that converted a project to the `.bare` layout. The
  investigation is summarised under "The problem".

**2026-10-13.**

- The human inspects finished ic2 worktrees in jEdit. The draft's step 3
  refused to launch jEdit in any marked worktree, which blocked that. Steps
  2, 3 and 5 now check whether the other writer is live instead: jEdit
  refuses only while the checkout's ic2 server runs, and ic2 refuses only
  while a live jEdit owns the checkout.
