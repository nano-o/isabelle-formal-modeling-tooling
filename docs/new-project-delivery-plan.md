# Plan: Isabelle tooling and agent-board, ready for new projects

Decided on 2026-09-03 and reviewed by Codex (`gpt-5.6-sol`, high effort) the
same day; revised on 2026-09-15 (source and upstream review), 2026-09-16
(command interface) and 2026-09-28 (board extraction; then restructured
around new projects, with no compatibility layer and local repositories
only). It supersedes the extraction plan's TODO "Make project-local skills
the default development loop" and a first plan, dropped on 2026-09-03,
that kept both marketplaces behind a `dev-mode.sh` switch: Codex CLI 0.153
did not honour a project- or CLI-layer `[plugins."…"] enabled = false`
([openai/codex#33472](https://github.com/openai/codex/issues/33472)), so
uninstalling was the only dependable switch. Recheck that in the fixtures;
the durable reasons for vendoring, per-project provenance and a simpler
authoring loop, do not depend on it. The September 3 review covers the
vendoring proposal, not the board. The interfaces both installers, both
doctors and the fixtures share are fixed in
[delivery-contracts.md](delivery-contracts.md) (step 1); where this plan and
that document disagree, the contracts win.

This plan was moved on 2026-09-28 from the last section of
`formal/docs/isabelle-tooling-extraction-plan.md` in the offer-exchange
checkout (`~/Documents/isabelle-offer-exchange`), which keeps Phases 0–4,
the earlier design and its history. "The extraction plan" below means
that document.

## Goal and definition of done

Two local repositories on this machine, each usable alone or with the other
in a new project:

- the Isabelle tooling, in the existing clone at
  `~/Documents/isabelle-formal-modeling-tooling`, delivered to projects as
  committed project-local files instead of through host marketplaces;
- `agent-board`, a new local repository at `~/Documents/agent-board`,
  extracted from the tooling.

Done means: starting from a new Git repository, with only the two clones, the
pinned Isabelle release and one agent host installed, a user or their agent
runs `isabelle-tooling init`, `agent-board init`, or both, starts a fresh
host session, and has working skills, I/Q, the proof worker and, with the
board, coordination. This holds on Claude Code and on Codex CLI, with each
repository pinned at a `stable` commit that passed the new-project fixtures
below.

Both repositories stay local: nothing is pushed, published, run in CI or
offered through a marketplace as part of this plan. The tooling clone keeps
its existing `origin` untouched; `agent-board` gets no remote. The
offer-exchange checkout adopts the result at the end, like any other
project; it is no longer the constraint the plan is organized around. Other
checkouts with a descriptor, such as `~/code/thruput-hackathon`, are
temporary experiments and are not migrated.

## Starting point

Tooling `main` at `5b0f349` (followed only by documentation commits,
including this plan) contains the board implementation and its concurrency
fixes, six skills (including `isabelle-coordination`), Claude
digest hooks and Isabelle-specific board integration. The `release` branch
still names v0.7.1. The separate `feedback-thruput-erc20` branch holds
unmerged feedback and instruction work: preserve it and account for it when
moving files, but it is not part of this plan. Mentions of "five skills"
below mean the Isabelle bundle after extraction.

The board has never been deployed. It was used only in temporary
experiments; no release contains it (v0.7.1 predates it), neither host's
installed extension has its skill or hooks, and no repository on this
machine had board state or board Git guards when checked on 2026-09-28.
Nothing needs carrying across (see "No compatibility layer").

Both hosts run development installs of extension 0.7.1: Claude Code from a
directory marketplace on the tooling clone's working tree, Codex CLI from the
`isabelle-formal-modeling-dev` marketplace, plus the user-level
`~/.codex/agents/ic2_prover.toml`. Until step 5, do not refresh or reinstall
the Claude Code plugin: the working-tree manifest on `main` already declares
the board hooks and `isabelle-coordination` under the unchanged version
0.7.1, so a refresh would deploy the board through the plugin. Implement in
separate candidate checkouts, and keep the clone that `ISABELLE_TOOLING_ROOT`
names, and the registered runtime paths, usable until then. The plugin's
Claude worker profile disallows `mcp__iq`, which by the Claude Code
documentation matches only a server named `iq`, not the plugin's
`mcp__plugin_isabelle-formal-modeling_iq__*` tools. Until step 5 the
worker's instructions may be the only thing keeping it off the human's
jEdit; the project `.mcp.json` server named `iq` closes that gap.

**Upstream, 2026-09-28.** AutoCorrode `main` is
[`761256a`](https://github.com/awslabs/AutoCorrode/commit/761256a2dca62754b25477ae7dae00b31e236309),
13 commits past the fork's upstream base `eccf4fe`, none touching `ic2/`,
`iq/`, `ir/`, `ic/` or `isabelle-assistant/`; the latest eleven are enum and
Micro Rust work under `Misc/` and `Shallow_Micro_Rust/`
([comparison](https://github.com/awslabs/AutoCorrode/compare/c666753ab030e359c15c9427bf5d62000d39c5ef...761256a2dca62754b25477ae7dae00b31e236309)).
The prover-death fix
[`6f69263`](https://github.com/nano-o/AutoCorrode/commit/6f692634a7f6294a83079171d7f2cdfb9d2a48a2)
is still fork-only (`git cherry` reports `+`). The
[Isabelle2026 adaptation, PR #272](https://github.com/awslabs/AutoCorrode/pull/272),
is an open draft whose description says ic2 was not compiled; the open I/Q
and I/R PRs (#261, #233, #231, #228, #208) are unmerged and were not reviewed
for adoption. Keep the fork pin and Isabelle2025-2. An AutoCorrode or
Isabelle upgrade is separate work with its own build, prover-death, I/Q and
I/R validation. Recheck upstream at implementation time.

## Component ownership

`agent-board`
: The board implementation and CLI (today `scripts/board.py` and
  `scripts/board.sh`); the storage format and locks; claims, presence,
  messages and cursors; the Git commit and ref guards; the shell and
  concurrency regressions; the generic `agent-coordination` skill, replacing
  `isabelle-coordination`; the host digest adapters, replacing
  `extension/bin/board-hook.sh` and `extension/hooks/board-hooks.json`; its
  own project installer and read-only doctor; design and recovery
  documentation. It has no dependency on Isabelle, the Isabelle descriptor or
  `ISABELLE_TOOLING_ROOT`.

Isabelle tooling
: The five Isabelle skills; the I/Q MCP declarations and launcher; the
  neutral proof-worker instructions and rendered host profiles; descriptor
  and session setup; the model runner and export check. Optionally, when a
  project uses the board: ic2 lifecycle notes, proof-specific claims (theory
  files, branches, `token:jedit`), and a doctor call to board doctor.

Neither component installs, advances, removes or interprets the other's pin.
The Isabelle setup skill may explain the optional board setup, but `init`,
`sync` and `update` never install or upgrade the board.

## The agent-board repository

```text
agent-board/
  bin/agent-board
  src/agent_board.py
  skills/agent-coordination/
  integrations/claude/             digest hook and project settings template
  scripts/                        project integration installer
  tests/                          existing shell and concurrency regressions
  docs/                           design, CLI compatibility, recovery
  README.md
  Makefile
```

**Extraction.** Move the implementation with its regression tests, and
record the source commit and applicable license notices. Keep the Python
standard-library and Git implementation, local storage and Linux/POSIX scope.
Do not redesign the protocol or add a daemon. Host adapters stay separate
from the core. Provide the generic skill on both hosts; keep the explicit
digest workflow on Codex unless an equivalent host hook is validated, and do
not invent automatic delivery parity the current integration lacks.

**No compatibility layer.** Nothing is carried across, so the extraction
renames and removes freely:

- runtime data lives under `<git common dir>/agent-board/`; the board keeps
  its current on-disk format, and the extracted code reads only that format;
- the environment names become `AGENT_BOARD_AGENT`, `AGENT_BOARD_DIR` and
  `AGENT_BOARD_STALE_MINUTES`; the `ISABELLE_BOARD_*` names are dropped, not
  aliased;
- the bare `jedit` resource shorthand is dropped: the generic board knows
  only `token:NAME`, and Isabelle instructions write `token:jedit`;
- the `migrate` verb and the legacy-format handling behind it are deleted
  together with their tests;
- Git guards carry an `agent-board` marker; the installer does not
  recognize the old `isabelle-tooling board guard` marker;
- no forwarding wrappers remain at the old tooling paths: the change series
  that creates `agent-board` also removes `scripts/board.py`,
  `scripts/board.sh`, `isabelle-coordination`, `extension/bin/board-hook.sh`,
  `extension/hooks/board-hooks.json` and the manifest's `hooks` entry from
  the Isabelle source.

Experimental board state or guards found later are deleted by hand, not
migrated.

**Public interface.** Keep the current verbs other than `migrate`, and their
exit semantics. Add a version and capability query reporting the CLI and
state versions, the executable's commit, and whether its checkout is clean;
and a read-only `doctor` covering the storage format, the installed Git
guards and the executable, with machine-readable output for callers.
Isabelle's doctor calls it instead of parsing the board's directories and
hook markers. The Isabelle adapter records the interface version and the
capabilities it needs; it never reads board storage, so the state version
is the board's own concern. Resolve the executable from
`AGENT_BOARD_COMMAND` (one path, not shell text), else `agent-board` on
`PATH`; machine paths stay in host-local configuration or the environment,
never in committed files. A
configured but missing, mismatched or broken board fails doctor; a project
without board configuration needs no executable. The ic2 notifier stays
best-effort and never masks a prover result.

**One active board revision.** As on the Isabelle side, the executable must
be a clean checkout at the project's `board_revision`; a project on another
pin fails board doctor with the required revision, and `--allow-dirty`
marks development use as Isabelle doctor's does. Keep the checkout that
projects use at `stable` and develop in a separate worktree. Git guards
record the executable's absolute path when installed; board doctor fails
when that path no longer matches the current resolution.

**Project operations.** `agent-board init [--revision REV]` bootstraps a
project before the host session starts: it writes `agent-board.conf` with
`board_revision=<full commit>` (default: the commit `stable` resolves to),
installs the board's project files (see "Project files") and refuses an
existing `agent-board.conf`. Then `sync`, `sync --link`, `sync --check`,
`update REV` and `remove` behave as the Isabelle operations below. `init`
does not register an agent and does not install Git guards; `install-hook`
does, explicitly,
chaining a foreign `pre-commit` or `reference-transaction` hook as the
current code does. Runtime board data stays under Git's common directory,
outside the inventory. None of these commands exists yet.

**How agents learn to use the board.** The skill is only the discovery
mechanism. Setup also installs a short managed block in the root instruction
files (see "Root instruction files") requiring each agent coordinating
directly to load `.agents/skills/agent-coordination/SKILL.md` for its first
repository task and to consult the board at task entry and after compaction
or resume. Reuse the skill while its current text remains in context; reload
it after compaction, when resuming without it, or when its installed
revision changes. Before changing shared files or refs, or delegating work,
agents follow the skill's registration, ownership and handoff procedure. The
block points to the skill rather than repeating its procedure, and it
explicitly permits the supervised-worker exception below, so a worker's
brief does not conflict with an unconditional project rule. It applies only
to projects that opt into coordination.

The skill explains unique agent handles, reading current claims and
messages, claiming before edits or Git mutations, renewing presence during
long work, checking for updates at work boundaries, posting handoffs and
releasing claims. When a board is configured, the Isabelle worker profiles
support both delegation modes below. For a worker coordinating directly, the
delegation brief passes the repository and board location and a distinct
worker handle, and requires the worker to read the skill; do not rely on a
subagent inheriting its parent's conversation. Claude digest hooks supply
current board context; Codex agents request a digest explicitly. Hooks are
reminders and delivery, not a replacement for the instruction rule. Git
guards check commits and ref updates; file edits still depend on cooperative
claiming, so nothing guarantees that every agent follows the protocol.

**Supervised workers may skip the coordination skill.** Coordination can
stay with the directing agent instead of being repeated in every worker's
context. Choose the mode explicitly when delegating:

- **Independent agent:** owns its board identity and claims, reads the skill,
  checks messages and maintains its presence. Use this for autonomous or
  long-lived work, self-directed scope changes, further delegation, or workers
  that must perform Git mutations themselves.
- **Supervised worker:** receives a bounded assignment from an active
  coordinator and does not load the board skill or use the board. Prefer
  this for narrowly scoped analysis or edits whose coordination the parent
  can manage. Read-only workers need no write claims, but their brief still
  identifies the source or snapshot and forbids unassigned mutations.

For supervised edits, the coordinator acquires the necessary claims before
launching the worker and keeps them, records which worker and worktree uses
each scope, keeps its presence current, reads board messages and relays
relevant changes. It gives its own workers non-overlapping scopes, since the
board sees only the coordinator's claims and cannot detect conflicts between
them. It collects the result, confirms the worker has stopped writing and
completes any integration before releasing or handing over ownership; it
never releases a claim while its worker is still writing.

The worker needs only a short brief: supervised mode and how to reach the
coordinator, the assigned checkout and allowed paths or resources, permitted
actions, the reporting or check-in boundary, and "stay within this scope;
ask the coordinator before expanding it." In this mode the worker performs
no board operations, commits, ref or index mutations, further delegation or
unassigned use of shared resources. It returns edits and validation results;
the coordinator commits under its own identity, and the proof-worker
profile's commit and handoff instructions change accordingly. No delegated
identities or board ACL are needed, with three practical consequences:

- Without an explicit handle, a guard takes the committer to be the one
  active agent registered for that worktree. A coordinator committing in a
  supervised worker's worktree is not registered there, so it passes its
  handle explicitly (`AGENT_BOARD_AGENT=<coordinator> git -C <worktree>
  commit …`); the skill shows this. Conversely, a Claude subagent inherits
  its parent's environment, so a coordinator that exports its handle lends
  it to its workers, and only the brief stops a supervised worker from
  committing as the coordinator.
- The Isabelle adapter's ic2 start and stop notes are tool notices posted as
  `ic2`, not agent coordination, and are permitted from a supervised worker.
- A coordinator blocked on a foreground worker cannot renew its presence,
  and the guards ignore a stale owner's claims, which others can then take
  without `--force`. Run long supervised work in the background, or keep it
  within the lease (`AGENT_BOARD_STALE_MINUTES`, default 180).

If a worker needs broader scope, reaches its check-in boundary without
renewed direction, or loses contact with its coordinator, it pauses shared
writes and reports back. The coordinator may reissue a bounded assignment,
or transfer ownership explicitly and switch the worker to independent mode,
which requires loading the skill. A worker resumed on its own must obtain a
valid assignment or use the full protocol before changing shared state. The
instruction block and the host worker profiles must agree on this
exception. Where a host can identify the explicit supervised mode, avoid
injecting board digests into that worker; never infer the exemption merely
from being a subagent.

**Context cost.** Keep the required skill small: roughly 500–800 tokens for
the routine protocol, essential command examples and the rules that always
apply. The current Isabelle coordination skill is 1,190 words (7,605 bytes),
about 2,000 tokens depending on the tokenizer; do not carry all of it into
every worker. Move extended CLI syntax, recovery and unusual Git cases into
bundled references, with clear triggers requiring the relevant reference
before those operations. Keep the instruction block to a short pointer, do
not repeat the skill in worker prompts, and do not inject it on every
prompt. Supervised workers receive only their brief; measure their context
cost separately.

Routine digests should be incremental and bounded, with explicit retrieval
for more. Never advance a delivery cursor past unread messages omitted by a
size limit. On compaction or resume, recover current ownership and relevant
messages instead of dumping the whole board history. These delivery changes
come after the behaviour-preserving extraction, with their own cursor and
delivery tests (step 3). Measure skill and digest sizes in the host
fixtures, including a board with a long history.

## The Isabelle tooling repository

**Why vendoring.** After extraction the Isabelle extension carries no
engine: five skill directories, two MCP declarations and two rendered worker
profiles, all in the tooling clone that every host already reaches through
`ISABELLE_TOOLING_ROOT`. Committed copies give each project provenance for
its instructions and configuration and let projects pin different revisions,
though not run different engines at once (see "One active runtime
revision"). Checking the copies against the Git object named by
`tooling_revision` is a stronger skew check than today's plugin version
comparison. The review's caveat stands: plugins would buy back install-once
discovery, bootstrap without a clone, Claude Code skill namespacing and an
atomic bundle once unrelated projects or machines must update without a
commit in each. That is out of scope while both repositories are local.

**Command interface.** A small `bin/isabelle-tooling` shell or Python entry
point in the tooling clone; compiling a binary to print Markdown adds
nothing. `extension/skills/` stays the one Markdown source for inspection and
installation, with no second copy of the instructions in the launcher. The
entry point delegates to the existing helpers and the synchronizer below:
one installation implementation, with the scripts as implementation details.
Printing a skill does not register it with a host; the committed project
files do. None of these commands exists yet.

`isabelle-tooling skills list`
: List skill names and descriptions with the resolved source commit.

`isabelle-tooling skills show NAME`
: Print that `SKILL.md` unchanged on stdout; provenance and diagnostics go
  to stderr. An unknown name fails with a nonzero status and no output.

`isabelle-tooling init`
: Create the descriptor and session through `new-project.sh`, add the root
  instruction block, and install the complete integration pinned at the
  commit `stable` resolves to (`--revision` overrides). Refuse an existing
  descriptor.

`isabelle-tooling sync`, `sync --link [--source DIR]`, `sync --check`
: Run the synchronizer's `copy`, `link` or read-only `check`.

`isabelle-tooling update REV`
: Change the pin and the installed files together; `update stable` moves a
  project to the current validated commit.

`isabelle-tooling remove`
: Delete the unchanged integration files, entries and blocks, the inventory
  and the descriptor, leaving the session and the root instruction files.

`isabelle-tooling doctor`
: Run the complete setup, integration and runtime checks.

**Instruction revision selection.** Inside a project, `skills list` and
`skills show` read the Git object named by the descriptor's
`tooling_revision`, as `sync` does, never a newer tool on `PATH`, the working
tree or a linked skill. Outside a project they read `stable` and report the
commit it resolves to. A malformed descriptor or a missing pinned object is
an error, not a reason to fall back. Reading needs no prover, host plugin or
network, and does not show that the runtime matches; that is doctor's job.

**One active runtime revision.** The tooling clone that
`ISABELLE_TOOLING_ROOT` names must be at the project's pin, and the single
registered ic2 component and installed I/Q plugin at the AutoCorrode revision
that pin selects. Projects on the same pin share that runtime; a project on
another pin fails doctor with the required revision, and nothing advances
its pin or switches a running prover for it. Keep that clone at `stable` and
develop in a separate worktree. Running several revisions at once needs
separate runtime environments (component registration, jEdit plugin state)
and is deferred.

**Synchronizer.** `scripts/sync-extension.sh`, run inside a project, is the
manifest-driven, non-destructive implementation behind `sync` and `update`.
It installs whole skill directories, including references and assets, with
the managed configuration entries and worker profiles; it never reduces
installation to redirecting `skills show` into a file. It follows the
installer rules below.

`copy`
: Materializes exactly the pinned revision, reading through
  `git -C "$ISABELLE_TOOLING_ROOT" show REV:extension/...`, never the working
  tree, then merges the owned entries and writes the inventory. Refuses
  unmanaged collisions and edited managed content; unchanged symlinks
  recorded by `link` are replaced with copies.

`update REV`
: The only operation that changes the pin. Stages the target revision's
  files, merges configuration into the staged copies, validates the whole
  result, then installs it, writing the descriptor last.

`link`
: The development loop. Replaces the managed skill copies with symlinks into
  a development worktree of the tooling (`--source`, by default the clone
  `ISABELLE_TOOLING_ROOT` names, which should stay clean at the pin), so an
  edit is visible after a reload with no reinstall. Records the mode in the
  inventory, dirties the worktree on purpose and touches nothing unmanaged;
  `copy` restores the committed state.

`check`
: Verifies paths, contents, modes, symlink targets, missing and obsolete
  managed files, parsability of the configuration files, rendered-agent
  freshness, the presence of the pinned Git object, and that the running
  scripts come from that revision. Checks shared files by owned entry, and
  detects a partial install by comparing files, inventory and descriptor.
  Reports link mode explicitly as development state. Doctor calls it.

**Tooling source changes.** `extension/` keeps `skills/`, `agents/`
(rendered from the one neutral source), `bin/iq-bridge.sh`, and gains
`project/` with the templates for the managed entries and the Claude skill
aliases. `isabelle-setup` stops telling users to install
`~/.codex/agents/ic2_prover.toml`: the worker profile is now a project file.
After the offer-exchange checkout has adopted the result (step 5), delete
the two plugin
manifests, the two marketplace files, the Codex dev-marketplace README
section, `scripts/release.sh`, the local `release` branch and the `REVISION`
handling in doctor, keeping the tags as history and adding one README
paragraph saying the plugin route existed through extension v0.7.1 and can
be restored from Git. The review's alternative of keeping them dormant was
rejected because untested release code rots. The host-parity test survives
in a new form: it locks the two generated MCP declarations to their hosts'
shapes and environment variables. Small adapter tests cover optional board
invocation and failure handling; the generic board regressions run in the
board repository.

**Across the three layouts of the extraction plan's §1** (A: the tooling as
a submodule of `X`; B: external tooling, this plan's default; C: a separate
assurance repository holding the formal artifacts). Hosts discover skills,
agents and MCP declarations only at fixed paths relative to the repository
they run in, so the managed files live at the checkout root that holds the
descriptor: `X`'s root under A and B, the assurance repository's root under
C, with the host started anywhere inside that checkout. Under C, `X` holds
only the adapter and receives nothing from the extension. Under A the
submodule is simply the runtime checkout that `ISABELLE_TOOLING_ROOT` names,
and the project still receives copies, so all three layouts install the
same way. A delivery mode that commits symlinks into the submodule and
treats the gitlink as the pin was considered and cut on 2026-09-28: it
needed its own inventory, preflight, doctor and failure rules, and no
project uses layout A.

**Verified host facts** (documentation unless stated otherwise):

- Claude Code 2.1.259 discovers `.claude/skills/<name>/SKILL.md` and follows
  a symlinked entry there; it does *not* read `.agents/skills`. Both facts
  were checked empirically on 2026-09-03 with probe skills in a scratch
  repository and `claude -p`. Project `.mcp.json` supports `${VAR}`
  interpolation in `command`; project agents live in `.claude/agents/*.md`
  with full frontmatter including `disallowedTools`; a project `.mcp.json`
  server named `iq` does not clash with the plugin's `plugin:…:iq`, but both
  would launch a bridge. `enabledMcpjsonServers` in `settings.local.json`
  pre-approves `.mcp.json` servers.
- Codex CLI scans `.agents/skills` from the working directory upward through
  the repository root, follows symlinked skill directories, and presents
  duplicate names rather than merging them. Trusted projects may supply
  `.codex/config.toml` including `mcp_servers`, layered from the repository
  root toward the working directory. Project-scoped custom agents under
  `.codex/agents/*.toml` are supported (not yet smoke-tested). `AGENTS.md`
  can require skill use but cannot register skills, agents or servers.
- The two `iq` declarations would not fight over a port: the bridge
  *connects* to the I/Q server on 8765, so duplication yields two bridge
  processes and ambiguous host configuration, not a bind failure.

The 2026-09-15 documentation review reconfirmed Codex's
[repository skill discovery and symlink support](https://learn.chatgpt.com/docs/build-skills)
and [project-scoped custom agents](https://learn.chatgpt.com/docs/agent-configuration/subagents),
without rerunning host smoke tests. Record the actual host versions in the
fixtures; the September 3 observations remain dated evidence.

## Rules both installers follow

**Project files.** The two components own disjoint files, so neither
installer needs to coordinate with the other. Each keeps its inventory, and
any gitignored local state, in a directory it owns at the checkout root with
its own `.gitignore`; neither edits the project's `.gitignore`. All of the
following is committed.

Isabelle tooling
: `isabelle-tooling.conf`; `.isabelle-tooling/` (inventory); the five
  `.agents/skills/isabelle-*` directories and relative `.claude/skills/`
  symlinks to them; the `mcpServers.iq` entry in `.mcp.json`, launching
  `${ISABELLE_TOOLING_ROOT}/extension/bin/iq-bridge.sh`; the managed
  `mcp_servers.iq` block in `.codex/config.toml`;
  `.claude/agents/ic2-prover.md` and `.codex/agents/ic2_prover.toml`; its
  block in the root instruction files.

`agent-board`
: `agent-board.conf`; `.agent-board/` (inventory and the project-local
  digest-hook launcher, from the pinned source); the
  `.agents/skills/agent-coordination` directory and its `.claude/skills/`
  symlink; the digest-hook entries in `.claude/settings.json`; its block in
  the root instruction files.

The only places both touch are the root instruction files, in separate
blocks, and the skill directories, in separate entries; a project may keep
unrelated skills there (the offer-exchange checkout has many). The
inventory records the revision, hashes of wholly managed files and
canonical values of owned entries and blocks. Machine-specific paths and
credentials stay out of committed files. Git hooks and board runtime data
are runtime resources, checked by board doctor, not vendored. Because the
files are committed, every clone and worktree has them without a sync,
though running them still needs the matching runtime and host setup.

**Owned entries and blocks.** In a file shared with the project, an
installer owns only its entry or block, compares it with the inventory
before replacing or removing it, and refuses when it was edited or when an
unmanaged entry of the same name exists. Removal deletes only unchanged
owned content. Inventory checks cover the owned entries, never a whole-file
hash that would count unrelated settings as drift.

- JSON (`.mcp.json`, `.claude/settings.json`): merge with the standard
  library, keeping sibling entries and array order; the file is rewritten
  with stable formatting, and JSON has no comments to lose.
- TOML (`.codex/config.toml`): a delimited text block
  (`# BEGIN isabelle-tooling` … `# END isabelle-tooling`) holding the
  `[mcp_servers.iq]` tables; everything outside it is left byte for byte, so
  no TOML writer is needed. An `[mcp_servers.iq]` table outside the block is
  an unmanaged collision.
- Markdown instruction files: delimited blocks
  (`<!-- BEGIN agent-board -->` … `<!-- END agent-board -->`, likewise for
  `isabelle-tooling`), surrounding text untouched.

**Root instruction files.** `new-project.sh` writes only
`<formal_rel>/AGENTS.md` and its `CLAUDE.md` symlink, which a session started
at the repository root does not load; the offer-exchange checkout works
only because of a
hand-written root `AGENTS.md` pointing there. `init` therefore adds an
Isabelle block to the root instruction files that points to
`<formal_rel>/AGENTS.md` and names the skills, and `agent-board init` adds
its own block. Both resolve symlinks first: when `CLAUDE.md` resolves to
`AGENTS.md`, as in the offer-exchange checkout, one block serves both hosts
and is
recorded once. When neither file exists, create `AGENTS.md` and a
`CLAUDE.md` symlink to it, the convention `new-project.sh` already uses
under `<formal_rel>/`. When `CLAUDE.md` is a separate regular file, write
the block to both.

**Git is the transaction log.** Every managed file is committed, so no
rollback record or in-progress marker is needed; a per-worktree installer
lock only keeps the two installers from interleaving writes to the files
they share. The index is the
checkpoint: an installer refuses to start while any path it would modify
has unstaged changes or is untracked, other than changes its own `link`
recorded. Staged changes are accepted, so a new repository stages what one
`init` printed before running the other, without an intermediate commit.
An installer never stages or commits. It
stages the complete result in a temporary directory, validates it,
rechecks each destination immediately before replacing it, and writes the
descriptor last. If writing fails, it names the paths it touched and prints
the command that restores them (`git restore` for tracked paths, removal for
new ones); until then `check` reports the mismatch between files, inventory
and descriptor, and doctor fails. Git hooks and board runtime data lie
outside the repository, which is why guards are installed only by the
explicit `install-hook`.

**`stable` refs.** Each repository keeps a local `stable` branch,
fast-forwarded only to a validation record commit: the commit at which the
new-project fixtures passed, plus one appended entry in
`docs/validation.md` recording the outcome. Both `init` commands pin the
commit `stable` resolves to, `--revision` overrides it (the fixtures use this
for candidates), and `update stable` moves a project forward. `stable`
replaces the `release` branch as the marker of a validated commit; nothing
is packaged.

**Doctor.** Isabelle doctor fails on an active Isabelle plugin in either
host's registry, a duplicate `iq` declaration, a user-level `ic2_prover`
profile (today's doctor requires it; it would now duplicate the project
one), and `check` drift, and it enforces the one-active-runtime rule. It
must pass before interactive work, and a sync still needs a new host session
or the documented reload. When coordination is configured it also checks the
board's CLI compatibility and runs board doctor; missing board configuration
is valid. Board doctor runs with no Isabelle installation or descriptor. In
fixtures, discovery and duplicate checks use the fixture's host
configuration roots, not the user's.

**Bootstrap.** Neither tool can depend on a skill that is not yet installed,
so both installers run before the host session. With the prerequisites in
place (the host; the pinned Isabelle release; the one-time ic2 component
registration, I/Q plugin installation and I/Q token that `isabelle-setup`
shows, described in the extraction plan's §2), a new project runs:

```sh
"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" init --session NAME
git add -- PATHS...                                    # as init printed
~/Documents/agent-board/bin/agent-board init           # optional
~/Documents/agent-board/bin/agent-board install-hook   # optional
```

Depending on the host, the user then trusts the project in Codex CLI or
approves the `iq` server at the first Claude Code start, and starts a
session in which
`isabelle-setup` finishes the work. `skills show isabelle-setup` is readable
guidance before installation, not a substitute for it. Each README's quick
start uses explicit paths for installation, shows the Isabelle-only path
first with coordination as an optional step, puts `agent-board` on `PATH`
(or sets `AGENT_BOARD_COMMAND`) for projects that use the board, since its
hook, the ic2 notifier and agents resolve it that way,
invites users to have their agent run setup and checks, and gives exact
commands for what only the user can do.

## Fixtures

The acceptance fixtures are new projects: a bare `git init` repository and a
small existing codebase other than stellar-core. Run board alone, Isabelle
alone, and both in each installation order, separately on Claude Code and
Codex CLI, with isolated host configuration roots, starting sessions both at
the repository root and in a subdirectory. Board-only runs have no Isabelle
descriptor, installation or `ISABELLE_TOOLING_ROOT`; Isabelle-only runs have
no board executable. Combined runs also cover independent pin mismatches and
`remove` of one component while keeping the other. Record both source
revisions, the CLI compatibility version, host versions and outcomes. Run
Codex fixtures at medium reasoning effort, in the background, with stdin
closed.

With Isabelle, confirm skill, agent and I/Q discovery (Codex's upward scan
is documented; Claude Code's root `.mcp.json` and symlinked skill aliases
from a subdirectory start need proving); `link`, make one unmistakable skill
edit, start a fresh session and observe it with no reinstall; connect
through I/Q; delegate one smoke proof to the worker; `copy` and confirm the
tree is clean.

Exercise the command interface: `skills show` emits exactly the selected
Git object's bytes, with no provenance on stdout; `skills list` reports the
same revision; inspection works without a prover or network. Cover the
project pin when the tooling checkout has a different `HEAD` or uncommitted
skill edits, inspection outside a project (reads `stable`), unknown skill
names, malformed descriptors and missing pinned objects. Check that `init`
installs the complete integration at `stable`, `sync` preserves the pin, and
only `update` changes it. Include a skill with a supporting reference file,
to show that installation preserves the directory and not just `SKILL.md`.

Installer tests cover unrelated MCP servers, TOML content outside the
managed block, unmanaged collisions, edited owned entries, blocks and files,
obsolete entries, missing pinned commits, runtime mismatch, a pre-existing
root `AGENTS.md`, `CLAUDE.md` as a symlink and as a regular file, refusal
with unstaged or untracked managed paths, two installers started at once,
destinations on another filesystem than the temporary directory, and an
injected failure after each publication step, including during Isabelle
`init`'s session scaffold: the printed commands restore the tree, `check`
and doctor fail until they do, and a retry then succeeds. Adoption runs
`update` against a snapshot of the offer-exchange checkout (a linked
worktree at its current commit), with its own `.claude/skills/`, root
`AGENTS.md` and `CLAUDE.md` symlink. Both doctors are checked to be
read-only: `git status` and a file listing of the project and the runtime
checkouts are the same before and after.

For the board, run the original shell tests and behavioural regressions,
renamed with the code, before changing behaviour. Delete the three
regressions that exercise `migrate` together with it, and rewrite the one
that uses the bare `jedit` shorthand for `token:jedit`; the remaining 28
must pass unchanged. Add coverage for executable resolution, shared state
and lock identity across linked worktrees, both Git guards under real Git
operations, foreign-hook chaining, a commit in another worktree with an
explicit handle, a guard whose recorded executable no longer matches, a
failure between the two guard writes, a `core.hooksPath` outside the Git
directory, the incomplete-state cases, and the ic2 notifier returning
within its timeout while another process holds the board lock. Verify
exactly one digest route and one coordination skill in fresh host sessions,
using the explicit digest workflow on Codex.

In fresh sessions started at the root and in a subdirectory, list the
worker profiles and tools each host offers, and have the proof worker
attempt an I/Q call, which must be unavailable to it. Exactly one worker
definition and one main-session `iq` server may be visible, so that a
passing smoke proof cannot hide a user-level or plugin duplicate.

Behavioural scenarios, on both hosts: an ordinary editing task that does
not mention the board, where the agent should consult the skill and board
and claim before editing; the same after compaction or resume; an
independent delegated worker without inherited context; a supervised worker
with only its brief, where the coordinator claims first and keeps ownership
until the worker stops, the worker stays in scope with no board or Git
operations, and the coordinator commits without bypassing guards; several
supervised workers with disjoint assignments; a scope-expansion request; a
missed check-in or unavailable coordinator; an explicit transfer to
independent mode; and a check that the exception does not suppress ordinary
coordination. These depend on model behaviour, so treat them as recorded
observations rather than pass/fail gates: run each at least three times per
host, record every outcome and how compaction or resume was triggered, and
fix any protocol violation in the skill, instruction block or worker profile
before moving `stable`. After failure injection, recheck board and host
session state; a passing file-copy check is not enough.

## Order of work

Steps 1 to 3 were done on 2026-09-28 and steps 4 and 5 on 2026-09-29
(see History); step 6 is pending.

1. **Settle the contracts.** Record the ownership, project files, owned
   entry and block formats, root instruction handling, executable
   resolution, CLI compatibility version, `stable` refs, the renames and
   removals, and the delegation modes in
   [delivery-contracts.md](delivery-contracts.md); step 2 copies its shared
   rules and board part into the new repository. Have this plan and the
   contracts design-reviewed, as the vendoring proposal was. Recheck the
   branches and upstream, preserve unrelated work including the feedback
   branch, and keep the AutoCorrode and Isabelle pins.
2. **Extract the board.** Create `~/Documents/agent-board`, move the core
   code, tests, docs, generic skill and host adapters, and record provenance
   and licenses. Keep the on-disk format, locking and verbs other than
   `migrate`; apply "No compatibility layer", including removing the board
   from the Isabelle source on a candidate branch, and replace the legacy
   detection with the incomplete-state rule. Add `version` and the ic2
   notifier adapter, and drop Isabelle doctor's board section, which parses
   the old directories and markers. Board doctor and the doctor adapter
   depend on the project files and come in step 3. Gate: the board
   regressions, the corruption cases and the notifier tests pass, with no
   Isabelle dependency and no installed setup changed. Commit the two
   repositories separately.
3. **Build project-local delivery for both.** Implement `bin/isabelle-tooling`,
   the templates and manifests, `sync-extension.sh` and the `init`
   renderer, and the board's init, sync, update, remove, check and doctor
   commands; the installer lock, the root instruction blocks and the
   adoption path; the revised doctors and the board doctor adapter, README
   quick starts, setup skill and worker instructions; and, in the board,
   the smaller skill and bounded digests with their cursor and delivery
   tests. Keep the plugin entry points until
   step 6. Gate: the installer, command-interface and board tests above
   pass. Commit candidate revisions of both repositories.
4. **Validate on new projects and mark `stable`.** Run the new-project
   fixtures on both hosts against the candidates. Resolve every failure,
   then make each repository's validation record commit on `main`, naming
   the candidates of both, rerun the mechanical checks at exactly that
   commit, and create `stable` there.
5. **Adopt the result in the offer-exchange checkout and retire the plugins.**
   Close host sessions. Uninstall both hosts' Isabelle extensions, remove the
   Claude Code directory marketplace and the Codex
   `isabelle-formal-modeling-dev` marketplace, and move
   `~/.codex/agents/ic2_prover.toml` aside, all before the first verification
   session, so no duplicate is present while the project copies are tested.
   Check out `stable` in the clone `ISABELLE_TOOLING_ROOT` names, moving
   development on `main` to a linked worktree, and run `isabelle-tooling
   update stable` in the offer-exchange checkout, which is the adoption path,
   since it has a descriptor but no inventory. Then, if this project uses
   coordination, run `agent-board init` and `install-hook`. Keep
   `enabledMcpjsonServers` for the root `.mcp.json`. Start fresh sessions and
   verify doctor, I/Q, the project proof worker and, with the board, digest
   delivery and the claim and ref guards from a linked worktree; then commit
   the descriptors, inventories and project files and delete the moved-aside
   profile. If this fails, restore the project files with Git and reinstall
   the 0.7.1 extensions from the tooling history before resuming work.
6. **Remove the plugin and release machinery.** Delete what "Tooling source
   changes" lists, rerun the fixtures at the resulting commits, advance
   `stable`, and run `update stable` in the offer-exchange checkout. Gate:
   each repository works alone
   and with the other in a new project, and no active configuration points
   at a removed delivery path.

## History

**Kept from the first plan**, per the review: the one-copy-per-host
invariant, explicit status reporting, the session-boundary rule, the
clean-checkout fixtures with an unmistakable skill edit, the I/Q and
proof-agent smoke tests, host-parity checks for the two MCP shapes, agent
rendering from one neutral source, and the short agent-led README quick
start. Dropped: the Claude Code dev marketplace, the Codex cachebuster
updater, and whole-plugin integration testing.

**The vendoring review's verdict**, quoted: "I agree, conditionally. For the
present, tightly controlled set of projects, committed project-local copies
are simpler and give better per-project reproducibility than two host
marketplaces. I would describe this as a temporary vendored-extension
design, not as proof that plugins were the wrong abstraction." Its three
corrections to the argument as first stated were the circular bootstrap,
the requirement that `check` compare against the Git object rather than the
working tree, and that marketplaces solve distribution rather than file
volume. Its other conditions are folded into this plan.

**The contracts review, 2026-09-28** (Codex `gpt-5.6-sol`, high effort,
over this plan and the first draft of the contracts). It made 11 findings,
and all of them are now folded in: an adoption path for existing
descriptors; an `init` whose session scaffold comes from the pinned object
and is published descriptor last; an installer lock and same-filesystem
publication; paired, byte-exact Git guards; a bounded ic2 notifier;
cutting layout A's symlink delivery; stable doctor check ids; read-only
doctors; an incomplete-state rule for board storage; a negative I/Q check
for the proof worker; and a doctor split between steps 2 and 3, with an
exact `stable` validation record. Two findings were narrowed. Isabelle
doctor gets no JSON output, since nothing consumes it. The adapter does not
check the board's state format, since it never reads board storage. The
hooks-directory finding was partly mistaken: `git rev-parse --git-path
hooks` already follows `core.hooksPath`. It became the rule that guards are
installed only inside the Git directory.

**Step 2, 2026-09-28.** agent-board lives in `~/Documents/agent-board`, a
local repository without a remote: an import commit holding the source
files unchanged (`f9aacb8`, recording provenance), the standalone
adaptation with its tests (`b836c94`), and the Claude hook, generic skill
and documentation (`b2ba4b2`), with the contracts' board part copied to
its `docs/project-integration.md`. Its 36 regressions (27 kept, 9 new),
the CLI suite and the hook test pass. This repository's candidate is the
`delivery` branch, in its own worktree, with the board removed, the ic2
notifier adapter and its test, doctor's board section dropped, and the
docs, profiles and proving skill updated; the runtime clone stays on
`main` at the pin. Three details differ from the order of work above:

- `install-hook` already refuses a hooks directory outside the Git common
  directory and writes both guards or neither, since that is the board's
  own code and its tests belong with it; board doctor still comes in
  step 3.
- `version` reports an empty capability list, since `doctor` and the
  project verbs do not exist yet; step 3 adds `doctor` and `project` with
  them.
- The notifier's five-second bound is tested with a board command that
  blocks, standing in for `post` waiting on a held lock, so the Isabelle
  tests need no agent-board checkout; the board repository tests its own
  Claude hook with the lock really held.

**Step 3, 2026-09-28.** agent-board `ddb36e7` adds the project
operations, doctor, bounded digests and the smaller skill (489 words, about
700 tokens, with four references), and `c6b934c` accepts
`--project-root` after the project verbs, a bug that only running both
candidates together showed. This repository's `delivery` branch has
`b1070e9`: `bin/isabelle-tooling`, the manifest and templates in
`extension/project/`, the renderer, the revised doctor with the board
adapter, and the setup skill, worker profiles, proving skill and README.
The installer rules are one module, kept as identical copies in both
repositories. Both `make validate` runs pass: agent-board's 41 regressions
(5 new, for bounded digests) and 22 project-file and doctor tests, and this
repository's 17 project-file, command-interface and doctor tests beside
the existing suites. A mutation check confirmed that the tests catch a
skipped preflight, the descriptor written before the inventory, a doctor
that lets Git refresh an index, a digest that marks past what it printed,
unverified owned blocks and an unchecked guard. By hand, on new
repositories with both real candidates: each installation order, the two
installers started at once under the held lock (they serialize and the
second refuses on the first's unstaged files), both doctors, and `remove`
of either component keeping the other.

What differs from the text above, besides the decisions the contracts now
list:

- A new digest cursor, and `--full`, start at the latest posts rather than
  replaying the whole history, which is available through `show --all`.
- No `stable` branch exists yet, so `init` without `--revision` fails in
  both repositories until step 4.
- The other four skills keep their `Skill revision marker` lines, which
  step 6 removes with the release machinery; the rewritten setup skill has
  none.
- The candidate worktree is not a working runtime: its AutoCorrode is not
  populated and the one registered ic2 component is the runtime clone's,
  so Isabelle doctor run from it fails those checks. Step 4 needs a
  runtime checkout at the candidate, which means either moving that
  registration for the fixtures or giving them their own Isabelle user
  home.

**Step 4, 2026-09-29: the fixtures.** By the user's choice the existing
codebase was a clone of stellar-core-internal,
`~/Documents/formal-offer-exchange-demo` (branch `formal-demo`, both
components installed, session `Demo` holding the offer-exchange
`bigDivideUnsigned` demo theory), beside a bare `git init` repository and,
for adoption, a snapshot of the offer-exchange checkout at `319fed13e0`.
The runtime was a detached worktree of this repository at the candidate,
with its own Isabelle user home (`USER_HOME`, so the one registered ic2 was
the candidate's and the user's registration stayed untouched) and fresh
host configuration roots the user logged in to. Claude Code 2.1.284
(claude-opus-5-5, auto permission mode) and Codex CLI 0.155.1 (gpt-6-astra
at medium effort, workspace-write with automatic review) ran headless in
scratch clones; each behavioural scenario ran once per host, the user's
choice, with the ones confounded by a wrong brief or a permission denial
rerun.

Everything passed except as noted: installers, doctors and the command
interface (71 checks on the bare repository, 70 on the demo, at `5642dd1`
and again at `11a6bcb`); adoption; discovery of one copy of each skill,
worker profile and `iq` server from the root and a subdirectory on both
hosts; link mode with a fresh session seeing the edit; I/Q from both hosts,
Claude Code in auto mode included (after F1's fix); one digest route per host (the Claude
hook at session start and exactly once per new post on the next prompt,
the explicit digest on Codex); the ordinary task, resume, independent and
supervised workers, two disjoint supervised workers, scope expansion on
Claude Code, an unreachable coordinator, transfer to independent mode and
a non-worker brief, on both hosts; and the worker smoke proof on both
hosts, committed through the board protocol, with the Claude Code worker
seeing no I/Q tools. Four findings:

- F1: agents authenticated to I/Q by reading its token, which Claude
  Code's auto mode refused even with an allow rule, and which put the token
  into every transcript. `7a4f065` documented allow rules; `e25d1ef`
  replaced them: AutoCorrode `dbd474f`, a local commit on the fork's
  `6f69263`, lets the bridge authenticate every connection from the token
  file that `extension/bin/iq-bridge.sh` names, so agents never see the
  token and `authenticate` is no longer listed. The new AutoCorrode revision
  makes doctor ask for the I/Q plugin to be reinstalled (its stamp records
  the revision), though the plugin code is unchanged.
- F2: a jEdit started without `scripts/launch_jedit.sh` has a random I/Q
  token, so every `authenticate` fails. The setup skill now has a section
  on starting jEdit (`7a4f065`).
- F3: ic2 server names used the whole checkout basename, so a long
  worktree name or Isabelle home pushed the socket past ic2's 100 bytes and
  the worker could not start its prover. Names are capped at 37 characters,
  and doctor fails on a home too long for any socket (`7a4f065`).
- F4: Codex CLI 0.155 lists the main session's I/Q tools to a spawned
  `ic2_prover` despite the profile's `enabled = false`, forked or not; the
  worker did not call them. The profile no longer claims they are withheld
  (`11a6bcb`), and the contracts record the limitation.

Not established: the plan's three runs per scenario. Observations: Codex encrypts spawn messages in its rollouts, so
worker briefs could only be judged by behaviour, and it may give a worker
the parent's whole conversation; its scope-expansion coordinator took the
extra files itself, so no expansion request arose.

**Step 5, 2026-09-29: adoption in the offer-exchange checkout.** Retired:
the Claude Code plugin and its directory marketplace; the Codex plugin, its
personal marketplace `isabelle-formal-modeling-dev`
(`~/.agents/plugins/marketplace.json`) and the Git marketplace on
`release`; and `~/.codex/agents/ic2_prover.toml`, moved aside until the
checks passed and then deleted. The two allow rules for reading the I/Q
token left Claude Code's user settings. The runtime clone has `stable`
checked out (`19f79ff`, AutoCorrode `dbd474f`), with ic2 rebuilt and the
I/Q plugin reinstalled; `main` moved to the `-delivery` worktree and the
merged `delivery` branch was deleted. The agent-board checkout also has
`stable` (`bf1b1ff`), with `main` in `~/Documents/agent-board-main`.
`ISABELLE_TOOLING_ROOT` is exported in the user's bashrc, and
`agent-board` is linked from `~/.local/bin`.

In the checkout, `update stable` adopted the project files, and
`agent-board init` and `install-hook` added the board; the user's
uncommitted theory work stayed out. Both `sync --check` runs, Isabelle
doctor (23 checks, the host configuration included) and board doctor
passed, and from a linked worktree both guards refused a commit and a
branch claimed by another agent and allowed them after release. The
project files were committed (`9b5ba74cc6`) before the worker smoke proof
rather than after every check: while they were only staged, the Claude
Code coordinator asked which committed state to base the worker's worktree
on, as the proving skill says. In fresh sessions the user ran: Claude Code
from the root and from `formal/` saw one `iq` server, one `ic2-prover` and
one copy of each skill, received the digest from the hook at session
start, called I/Q without the token, and delegated the smoke proof to an
independent worker that saw no I/Q tools; Codex CLI from the root ran the
digest itself,
called I/Q, and delegated the smoke proof to a supervised `ic2_prover` in a
worktree under `/tmp`, inside its sandbox.

Observations:

- Context: a Claude Code session in this checkout starts at about 41k
  tokens, about 2.5k of them from the project. Delegating the one-line
  smoke proof took about 30k more, mostly for reading whole files: all of
  `isabelle-proving` for its delegation section, the board's
  `delegation.md`, and the worker profile. The Codex session ended at 22%
  of its window, about 65k tokens, including a request to list every tool.
  Splitting the proving skill, so that delegating does not load the proof
  pitfalls, is a candidate for step 6 or later.
- `scripts/install-iq-plugin.sh` ends with AutoCorrode's advice to start
  jEdit with a plain `isabelle jedit`, which gives the random token of F2.
- The Claude hook's digest reaches the agent, not the screen: the user
  asked the session how to see the board, and it answered with `digest`.
- Codex's sandbox refused the first board write (`.git` is read-only
  there) until automatic review allowed it, as in step 4.

**Step 6, 2026-09-29: the plugin and release machinery removed.**
`a65609b` deleted the two plugin manifests, the two marketplace files, the
plugin-only `iq` declarations and `scripts/release.sh`; moved the Codex
worker profile from `extension/codex/` to `extension/agents/`; dropped the
skills' `v0.7.1` markers; turned the host-parity test into one for the
project's two `iq` declarations; and made the Phase 4 host fixture install
the project files with `init`. The README keeps one paragraph on the plugin
route, whose code the `v0.x` tags keep.

The fixtures ran at `a65609b` with agent-board `bf1b1ff`, in the step-4
environment (the candidate worktree, its own Isabelle user home, fresh host
configuration roots). The mechanical checks passed, 76 on the bare
repository and 75 on the demo, except the one that pins the current
`stable` (`19f79ff`): its doctor rightly fails while the runtime is at the
candidate. Updating to the candidate passed from the offer-exchange
checkout's step-5 state and from its pre-adoption commit `319fed13e0`. On
both hosts: the worker smoke proof through ic2 and the board, from the
root; from `formal/`, one copy of each skill, one `iq` server and one
worker profile, and a read-only I/Q call; the Claude hook's digest at
session start, and the digest the Codex coordinator ran. Not rerun, since
nothing they exercise changed: the nine behavioural scenarios (the board
skill, the instruction blocks and the worker profile's text are as in
step 4) and link mode.

Observations and possible next steps:

- `git worktree add -b` of a branch the Claude Code coordinator had
  claimed was refused: the ref guard runs in the new worktree, where no
  agent is registered, so the handle was unknown. The branch had already
  been created, and the coordinator added the worktree for it with
  `AGENT_BOARD_AGENT` set. The board's Git reference covers a commit in
  another agent's worktree but not this case; that is agent-board work.
- Codex CLI again listed the 38 I/Q tools to its worker (F4), which did not
  call them.
- Deferred by the user: splitting `isabelle-proving` so that delegating
  does not load the proof pitfalls (step 5's context observation).
