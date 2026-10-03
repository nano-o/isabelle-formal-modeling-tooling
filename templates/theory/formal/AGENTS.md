# Agent instructions for the Isabelle theories of @PROJECT_NAME@

This directory holds the Isabelle/HOL theories of @PROJECT_NAME@, the session
`@SESSION@` in `@SESSION@/`, checked with the Isabelle formal-modeling tooling
named in `README.md`. Generic Isabelle rules, such as how to check theories and
iterate on proofs, come from that tooling's `isabelle-setup` and
`isabelle-proving` skills; this file carries only what is specific to this
project.

## Editing theories

On disk, Isabelle symbols are ASCII escapes: `\<open>...\<close>` for
cartouches, `\<Rightarrow>`, `\<forall>`. jEdit displays them as the Unicode
glyphs, but a raw Unicode glyph written into a file is a malformed command to
the batch prover.

## Layout

- `@SESSION@/` — the session: `ROOT` and its theories.

## Notes specific to this project

(None yet.)
