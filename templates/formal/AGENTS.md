# Agent instructions for the formal model of @PROJECT_NAME@

This directory holds the Isabelle/HOL model of @PROJECT_NAME@: the session
`@SESSION@` in `@SESSION@/`, checked with the Isabelle formal-modeling tooling
named in `README.md`. Generic Isabelle rules — how to check theories, iterate on
proofs, write the code-level model, and run differential tests — come from that
tooling's skills, not from this file. This file carries only what is specific to
this project.

## Conventions

The `isabelle-modeling` skill settles these with the user in an interview
before the first definition is written; the answers are recorded here and the
block doubles as the review checklist. An answer taken without the user is
marked `(default; not yet confirmed)`.

- **Source in scope:** which files and functions of @PROJECT_NAME@ are modeled,
  and which callees are opaque or out of scope. (unsettled)
- **Detected failures:** how failures the source detects — assertions,
  exceptions, error returns — are represented (default: a lightweight result
  type with a status enumeration and a bind operator, raised in source order).
  (unsettled)
- **Out-parameters and unassigned values:** how an out-parameter plus Boolean or
  status return is represented (default: a pair, with zero on paths where the
  source leaves it unassigned, said in the definition's text). (unsettled)
- **Casts and promotions:** every cast and implicit promotion is written out;
  same-width casts are annotated because their reading changes. (unsettled)
- **Unreachable defensive checks:** how checks the source can never reach are
  treated (default: modelled as written). (unsettled)
- **Undefined behaviour:** excluded by a stated definedness precondition, never
  modelled as a result; the sanitizer run over the corpus is the evidence.
  (unsettled)
- **Naming:** the source-name to Isabelle-name convention, argument order kept.
  (unsettled)

## Editing theories

On disk, Isabelle symbols are ASCII escapes: `\<open>...\<close>` for
cartouches, `\<Rightarrow>`, `\<forall>`. jEdit displays them as the Unicode
glyphs, but a raw Unicode glyph written into a file is a malformed command to
the batch prover.

## Layout

- `@SESSION@/` — the session: `ROOT`, theories, and the executable test
  interface once differential testing exists.
- `docs/` — analysis notes about the modeled code.

## Notes specific to this project

(None yet.)
