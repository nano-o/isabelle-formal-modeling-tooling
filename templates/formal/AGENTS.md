# Agent instructions for the formal model of @PROJECT_NAME@

This directory holds the Isabelle/HOL model of @PROJECT_NAME@: the session
`@SESSION@` in `@SESSION@/`, checked with the Isabelle formal-modeling tooling
named in `README.md`. Generic Isabelle rules — how to check theories, iterate on
proofs, write the code-level model, and run differential tests — come from that
tooling's skills, not from this file. This file carries only what is specific to
this project.

## Conventions

Settle these with the user before writing the first definition, then record the
answers here; the block doubles as the review checklist.

- **Source in scope:** which files and functions of @PROJECT_NAME@ are modeled.
- **Errors and exceptions:** how failures the source detects are represented
  (default: a lightweight result monad with a status enumeration and a bind
  operator, raised in source order).
- **Out-parameters:** how an out-parameter plus Boolean return is represented
  (default: a pair, with zero on paths where the source leaves it unassigned).
- **Casts and promotions:** every cast and implicit promotion is written out;
  same-width casts are annotated because their reading changes.
- **Unreachable defensive checks:** how checks the source can never reach are
  treated.
- **Undefined behaviour:** excluded by a stated definedness precondition, never
  modelled as a result.

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
