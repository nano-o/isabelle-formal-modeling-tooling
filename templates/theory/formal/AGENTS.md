# Agent instructions for the Isabelle theories of @PROJECT_NAME@

This directory holds the Isabelle/HOL theories of @PROJECT_NAME@, the session
`@SESSION@` in `@SESSION@/`, checked with the Isabelle formal-modeling tooling
named in `README.md`. The root `AGENTS.md` points to the skills for checking
theories and iterating on proofs in this project's Isabelle release.

## Editing theories

On disk, Isabelle symbols are ASCII escapes: `\<open>...\<close>` for
cartouches, `\<Rightarrow>`, `\<forall>`. jEdit displays them as the Unicode
glyphs, but a raw Unicode glyph written into a file is a malformed command to
the batch prover.

## Layout

- `@SESSION@/` — the session: `ROOT` and its theories.

## Notes specific to this project

(None yet.)
