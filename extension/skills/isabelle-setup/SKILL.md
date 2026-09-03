---
name: isabelle-setup
description: Set up the Isabelle formal-modeling tooling for a project checkout — locate the pinned Isabelle release, verify the tooling clone, show the one-time ic2/I/Q/token steps for the user to run, create the descriptor and an empty session from templates, and run doctor. Use when the user asks to "set up Isabelle for this project", to add formal modelling to a codebase, or when doctor fails on a fresh machine.
---

# Setting up Isabelle for a project

You run inside the agent host the user has already installed (Claude Code or
Codex CLI) with this extension loaded. You never install or configure the
host. Every step below either reads, runs a tooling script, or *shows* the
user a command that touches their home directory; those you do not run
yourself unless the user says so.

## 1. Find the tooling clone

The tooling clone is the source clone of `isabelle-formal-modeling-tooling`
with its `AutoCorrode` submodule, at a path the user chose, never inside a
project checkout. The extension finds it through `ISABELLE_TOOLING_ROOT`.

```bash
test -x "$ISABELLE_TOOLING_ROOT/scripts/doctor.sh" && echo ok
```

If the variable is unset or wrong, stop and tell the user to set it in their
shell environment to the clone's path and to restart the host session. If
`AutoCorrode/ic2/etc/build.props` is missing, the submodule is not populated:
show `git -C "$ISABELLE_TOOLING_ROOT" submodule update --init`.

## 2. Locate Isabelle

Order, fixed: `isabelle` on `PATH`, else the executable or installation named
by `ISABELLE_TOOLING_ISABELLE`. Its `isabelle version` must print the release
the descriptor names (Isabelle2025-2 unless the project says otherwise). If
none is found, **stop**: name the release and its download page,
<https://isabelle.in.tum.de>, and tell the user to unpack it where they like
and put its `bin/` on `PATH` or set `ISABELLE_TOOLING_ISABELLE`. Do not
download or install Isabelle; do not continue to later steps.

## 3. Build products inside the clone

Run these; they write only inside the tooling clone:

```bash
"$ISABELLE_TOOLING_ROOT/scripts/setup-ir-venv.sh"   # .venv/ for the I/R bridge
```

## 4. The steps that touch the home directory (user runs them)

Show each with what it writes and how to undo it. Run one only when the user
says so.

- **Register the ic2 component and build its JAR.**
  `"$ISABELLE_TOOLING_ROOT/scripts/build-ic2.sh"` runs
  `isabelle components -u $ISABELLE_TOOLING_ROOT/AutoCorrode/ic2`, adding one
  line to `$ISABELLE_HOME_USER/etc/components`, then `isabelle scala_build`,
  which writes the JAR inside the clone. Isabelle discovers components only
  through that file. Exactly one ic2 component may be registered; if `isabelle
  components -l` already lists another `ic2`, show the pair `isabelle
  components -x OLD` then `-u NEW`. Undo: `isabelle components -x
  $ISABELLE_TOOLING_ROOT/AutoCorrode/ic2`.
- **Install the I/Q jEdit plugin** (jEdit workflow only; jEdit must be closed):
  `"$ISABELLE_TOOLING_ROOT/scripts/install-iq-plugin.sh"` writes one JAR and a
  stamp under `$ISABELLE_HOME_USER/jedit/jars/`. Undo: delete those two files.
- **Create the I/Q token** at `~/.config/isabelle-iq/auth-token`, mode 600:
  `mkdir -p ~/.config/isabelle-iq && (umask 077; openssl rand -hex 32 >
  ~/.config/isabelle-iq/auth-token)`. Never print its contents.
- **Codex CLI only — install the proof-worker profile.** The extension ships
  `codex/ic2_prover.toml`; show
  `install -m 0644 "<extension>/codex/ic2_prover.toml" ~/.codex/agents/ic2_prover.toml`
  (create the directory first). Under Claude Code the worker is part of the
  extension and needs no step.

## 5. Create the project files

Ask for the session name (an Isabelle identifier) and, if not obvious, where
the formal artifacts should live (default `formal/` at the checkout root, code
at `.`). Then:

```bash
"$ISABELLE_TOOLING_ROOT/scripts/new-project.sh" --checkout <checkout> --session <Name> [--formal-rel formal] [--source-rel .]
```

This writes `isabelle-tooling.conf` at the checkout root and
`<formal>/{ROOT,ROOTS,AGENTS.md,README.md,CLAUDE.md -> AGENTS.md}` plus
`<formal>/<Name>/{ROOT,<Name>.thy}`, refusing to overwrite anything. The
descriptor records `tooling_revision`, the clone's current commit. Commit
these files with the project; the descriptor must be in every clone and
worktree.

## 6. Doctor, then build

```bash
"$ISABELLE_TOOLING_ROOT/scripts/doctor.sh" --project-root <checkout>
isabelle build -D <checkout>/<formal>
```

Doctor prints remediation commands and runs none; fix what it reports, in
order, then rerun it. A green doctor and a building empty session is the
finished setup. Then hand over to the proving and modelling skills.

## What this skill never does

Install or configure Claude Code or Codex CLI; download Isabelle; write under
`$HOME` on its own; register a project's own AutoCorrode copy as a component;
nest the tooling clone inside a project checkout.

## Revision

Skill revision marker: v0.6.1 (this line changes with each release so an
upgraded install is observable).
