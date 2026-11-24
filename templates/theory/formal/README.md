# Isabelle theories of @PROJECT_NAME@

The Isabelle/HOL theories of @PROJECT_NAME@, developed with the Isabelle
formal-modeling tooling:

- tooling repository: @TOOLING_URL@, pinned by `tooling_revision` in the
  checkout's `isabelle-tooling.conf`
- Isabelle release: `isabelle_version` in the checkout's `isabelle-tooling.conf`

Build the session with `isabelle build -D @FORMAL_REL@`. The root `AGENTS.md`
points to the project's proof workflow. Run
`"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" doctor` to check the setup.
`AGENTS.md` here carries the project's own notes for agents
(`CLAUDE.md` is a symlink to it).
