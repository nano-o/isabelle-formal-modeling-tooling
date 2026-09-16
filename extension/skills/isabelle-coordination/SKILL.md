---
name: isabelle-coordination
description: Coordinate several agents (Claude Code or Codex CLI sessions) working at once on one repository and its Git worktrees through the shared coordination board (scripts/board.sh) — presence, posts, claims on files, refs and the jEdit worktree, handoffs, and the pre-commit guard. Use when more than one agent shares a repository, when asked to "post to the board", "claim", "hand off", or before editing a shared file such as the project plan.
---

# Coordinating through the board

Several agents may work on one repository at the same time: one in the main
checkout that jEdit owns (Isabelle/IQ), others in linked worktrees with their
own ic2 servers, on either host. The board is where they see each other. It
is a directory of plain files in the repository's Git common directory,
shared by every worktree, driven by one script:

```bash
"$ISABELLE_TOOLING_ROOT/scripts/board.sh" --as <handle> ACTION ...
"$ISABELLE_TOOLING_ROOT/scripts/board.sh" --help
```

Run it from inside the checkout or worktree you work in, or pass
`--project-root DIR`. Read-only actions (`who`, `claims`, `show`, `digest`,
`guard`, `path`) need no handle. Nothing it writes lands in a working tree or
under `$HOME`; the board and its posts stay local to the machine.

## Your handle

Pick a short lowercase handle for the session, by convention the worktree or
the topic (`main`, `tx-layer`, `env-repair`), and pass it as `--as` on every
writing action. `ISABELLE_BOARD_AGENT` does the same where the host keeps
environment across commands; Claude Code's shell does not, so `--as` is the
reliable form. The pre-commit guard infers the committer from the worktree;
two agents sharing one worktree therefore commit as
`ISABELLE_BOARD_AGENT=<handle> git commit ...`.

## When to read the board

- At the start of a task: `digest --cursor <handle> --mark`, or `show` for
  the whole picture. Claude Code sessions get the digest injected by the
  extension's hooks at session start and before each prompt; Codex CLI
  sessions run it themselves at these moments.
- Before editing a file another agent might edit (the project plan, a shared
  theory, a README): `guard PATH` says whether it is claimed and by whom.
- Before moving a ref (rebase, history rewrite, merge into `main`) and
  before merging a branch.
- Before returning or ending, once more, so a request addressed to you does
  not go unanswered.

## When to write

1. `hello --task "..."` when you begin: one line saying what you do. It
   records your worktree and branch so others can find your work.
2. `claim --reason "..." RESOURCE...` before you edit a shared file,
   rewrite a branch, or take over the jEdit worktree. Resources are paths
   relative to the worktree root (`PLAN.md`; `formal/` covers the
   directory), refs (`refs/heads/main`), the token `jedit` for the I/Q
   editing session in the main worktree, or `path#passage` for one part of
   a file, which is shown to others but never enforced, so two agents can
   hold different passages of one theory and both commit.
3. `post` for what others need to know. `--kind handoff` when a branch is
   ready: branch, commit, what changed, what the merge does to files open in
   jEdit. `--kind request` when you need something from a named agent.
   `--kind done` when a milestone lands. `--re RESOURCE` ties the post to a
   file or ref; a plain `post` is a note; `post -` reads a longer body from
   stdin.
4. `release RESOURCE...` or `release --all` as soon as you are done;
   `bye "..."` when you leave, which releases everything you hold.

Keep posts short and specific: what, where (path, branch, commit), and what
the reader should do. The board is not the decision log. Decisions and
milestones still go to the project's plan file, and the agent who posts
"ready to merge" carries them over.

## The guard

`install-hook`, once per repository from any worktree, installs a
`pre-commit` hook that every worktree shares (`--force` keeps and chains an
existing hook). It refuses a commit that touches a path, or sits on a branch,
another agent holds an active claim on, and names the owner and the reason.
Then wait, ask with a post, take over with `claim --force --reason "..."` if
the owner is unresponsive, or bypass with `git commit --no-verify` and post
why. Never bypass silently.

A claim goes stale after `ISABELLE_BOARD_STALE_MINUTES` (default 180)
without board activity by its owner, or when the owner said `bye`. Stale
claims are shown as such, do not block, and a plain `claim` takes them over.
Every board action of yours counts as activity, so a long proof job that
neither posts nor claims for three hours loses its leases; post a note now
and then.

## Etiquette

- One handle per session; never write under another agent's handle.
- Claim narrowly and briefly: a passage rather than a theory several agents
  edit, a file rather than a directory, a branch only while you move it.
- Do not release, force or take over another agent's active claim unless
  the human asked.
- Answer requests addressed to you; if you cannot, say so on the board.
- `ic2.sh start` and `stop` post server notes on their own when the
  repository has a board; do not repeat them.
- Facts about the runtime, doc gaps and proof techniques belong in the
  project's own files, not on the board.

Skill revision marker: v0.7.1.
