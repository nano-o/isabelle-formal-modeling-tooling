# Isabelle theories of @PROJECT_NAME@

The Isabelle/HOL theories of @PROJECT_NAME@, developed with the Isabelle
formal-modeling tooling:

- tooling repository: @TOOLING_URL@, pinned by `tooling_revision` in the
  checkout's `isabelle-tooling.conf`
- Isabelle release: @ISABELLE_VERSION@

Build the session with `isabelle build -D @FORMAL_REL@`. For headless checking
and agent work, use the tooling clone's `scripts/ic2.sh` from anywhere inside
this checkout; `"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" doctor` checks the
setup. `AGENTS.md` here carries the project's own notes for agents
(`CLAUDE.md` is a symlink to it).
