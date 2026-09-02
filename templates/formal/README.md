# Formal model of @PROJECT_NAME@

An Isabelle/HOL model of @PROJECT_NAME@ and the properties proved about it,
developed with the Isabelle formal-modeling tooling:

- tooling repository: @TOOLING_URL@
- validated against tooling revision `@TOOLING_REVISION@` (also recorded as
  `tooling_revision` in the checkout's `isabelle-tooling.conf`)
- Isabelle release: @ISABELLE_VERSION@

Build the session with `isabelle build -D @FORMAL_REL@`. For headless checking
and agent work, use the tooling clone's `scripts/ic2.sh` from anywhere inside
this checkout; `scripts/doctor.sh` checks the setup. `AGENTS.md` here carries
the project-specific modelling conventions (`CLAUDE.md` is a symlink to it).
