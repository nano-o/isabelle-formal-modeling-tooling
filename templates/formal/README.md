# Formal model of @PROJECT_NAME@

An Isabelle/HOL model of @PROJECT_NAME@ and the properties proved about it,
developed with the Isabelle formal-modeling tooling:

- tooling repository: @TOOLING_URL@, pinned by `tooling_revision` in the
  checkout's `isabelle-tooling.conf`
- Isabelle release: `isabelle_version` in the checkout's `isabelle-tooling.conf`

Run `"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" doctor` to check the
setup; it also names the Isabelle executable of that release. Build the
session with that executable: `isabelle build -D @FORMAL_REL@`. With several
releases installed, a bare `isabelle` on `PATH` may be another one. The root
`AGENTS.md` points to the project's proof workflow.
`AGENTS.md` here carries the project-specific modelling conventions
(`CLAUDE.md` is a symlink to it).
