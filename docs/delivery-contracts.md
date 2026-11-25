# Project delivery contracts

The installer, setup checks and [validation fixtures](validation.md#fixtures)
follow these interfaces. The original delivery plan is in Git history.

## Project files

**Terms.** The *checkout root* is `git rev-parse --show-toplevel` of the
checkout the command runs in or the checkout chosen with `--project-root DIR`.
The *runtime checkout* is the tooling clone that `ISABELLE_TOOLING_ROOT` names.
A *managed path* is one recorded in the inventory.

**Descriptor.** The checkout root contains `isabelle-tooling.conf`
(`format_version=1`). It is UTF-8 data with one `key=value` per line and
support for `#` comments and blank lines. Lines end at LF alone, blank
means spaces and tabs, and both parsers reject carriage returns, NUL bytes
and unknown keys. `tooling_revision` holds the full 40-hex commit.

**Inventory.** `.isabelle-tooling/inventory.json` uses
`json.dumps(indent=2, sort_keys=True)` and a final newline. For example:

```json
{
  "format": 1,
  "component": "isabelle-tooling",
  "revision": "<40-hex commit>",
  "mode": "copy",
  "link_source": null,
  "claude_skills": "aliases",
  "directories": [".agents/skills/isabelle-setup"],
  "files": {
    ".agents/skills/isabelle-setup/SKILL.md":
      {"sha256": "<hex>", "executable": false}
  },
  "symlinks": {
    ".claude/skills/isabelle-setup": "../../.agents/skills/isabelle-setup"
  },
  "json_entries": [
    {"file": ".mcp.json", "pointer": "/mcpServers/iq",
     "element": false, "sha256": "<hex>"}
  ],
  "blocks": [
    {"file": "AGENTS.md", "syntax": "markdown", "sha256": "<hex>"}
  ]
}
```

- `mode` is `copy` or `link`; `link_source` is the absolute source checkout
  in link mode and `null` otherwise.
- `claude_skills` is `aliases` (per-skill symlinks under `.claude/skills/`)
  or `shared` (see "Skill directories").
- `directories` are wholly owned: any entry inside one that `files` does
  not list is drift.
- Paths are relative to the checkout root, with `/` separators.
- The inventory never records itself or the descriptor.

**Owned JSON entries.** An entry is either an object member, recorded by
the JSON Pointer of the member (`/mcpServers/iq`), or one element of an
array, recorded by the array's pointer with `"element": true`. The hash is
SHA-256 of `json.dumps(value, sort_keys=True, separators=(",", ":"),
ensure_ascii=False)` encoded as UTF-8.

- Array elements are identified by a marker string in the manifest.
  Exactly one element per recorded array may contain the marker, and its
  hash must match.
- Writes load the file with the standard library, change only the owned
  entry, keep member and array order, and write `json.dumps(indent=2,
  ensure_ascii=False)` plus a newline. Adding a new member or element
  appends it.
- `remove` deletes the owned member or element, then prunes containers left
  empty along its pointer, and deletes the file when `{}` remains.
- An unmanaged member with the owned name, or an unmanaged element carrying
  the marker, is a collision: install refuses.

**Owned TOML block.** Only `.codex/config.toml`, owned by
`isabelle-tooling`. The block is the text between the whole lines
`# BEGIN isabelle-tooling` and `# END isabelle-tooling`, both included; the
file may contain exactly one of each, in that order. The first install
appends the block at the end of the file (creating the file when absent,
separated from existing text by one blank line); later writes replace it in
place, and all text outside it is kept byte for byte. `check` parses the
whole file with `tomllib` (Python 3.11 or later) and requires the parsed
`mcp_servers.iq` to equal the block parsed alone. That catches
duplicate tables, and bare keys after `# END` that TOML would attach to the
block's last table. An `[mcp_servers.iq]` table outside the block is a
collision.

**Owned Markdown blocks.** In root instruction files, the text between the
whole lines `<!-- BEGIN NAME -->` and `<!-- END NAME -->` (`NAME` is the
component), at most one pair per component per file. The first install
appends the block, separated by one blank line; later writes replace it in
place. The hash covers the lines strictly between the markers. The block's
first line is a comment naming the command that changes it.

**Root instruction files.** Only `AGENTS.md` and `CLAUDE.md` at the checkout
root. Before writing, resolve each existing one through symlinks; a target
that is not a regular file inside the checkout is refused. The block goes
into the set of resolved files:

- neither exists: create `AGENTS.md`, and `CLAUDE.md` as the relative
  symlink `CLAUDE.md -> AGENTS.md`; the set is `{AGENTS.md}`;
- both resolve to the same file: that file, recorded once;
- only `AGENTS.md` exists: it, and create the `CLAUDE.md` symlink;
- only `CLAUDE.md` exists: its target, and create `AGENTS.md` as a regular
  file holding only the block;
- both exist and resolve differently: both.

A file or symlink an installer creates here belongs to the project, not
the component: the inventory records only blocks, and `remove` leaves the
files in place, even empty.

**Skill directories.** Skill content lives in `.agents/skills/NAME/`, which
Codex discovers; Claude Code sees it through a relative symlink
`.claude/skills/NAME -> ../../.agents/skills/NAME`. When `.claude/skills`
itself resolves to the same directory as `.agents/skills` (a project-wide
alias), no per-skill symlinks are made and the inventory records
`claude_skills: shared`. When `.agents`, `.claude`, `.agents/skills` or
`.claude/skills` is a symlink resolving outside the checkout, install
refuses. The manifest lists the skill names `isabelle-tooling` owns. Any
other skill directory belongs to the project. An unmanaged directory with
a managed name is a collision.

**Project kinds.** The descriptor may name a project kind. The
manifest's top-level `"kinds"` lists the kinds its revision supports. A
skill entry may carry `"kinds"`, the kinds it is installed for; a skill
entry without it is installed for every kind, and no other entry may carry
it. A project that names no kind gets every skill, whatever the lists say.
For a project that names a kind, `init`, `sync`, `update` and `check`
refuse a revision whose top-level list lacks it, including every revision
from before kinds, and install only the skills for that kind. In
`project_files.py` the kind comes from the spec's optional `kind(values)`
hook, given the parsed descriptor.

**Link mode.** `sync --link [--source DIR]` replaces each managed skill
directory in `.agents/skills/` with an absolute symlink to
`DIR/<source skill path>`, records `mode: link` and `link_source`, and
leaves the Claude aliases, which still resolve through `.agents/skills`.
`DIR` defaults to the runtime checkout, but is normally a development
worktree, so the runtime checkout stays clean at its pin. Only skills are
linked; configuration entries and worker profiles stay copies. Link mode
is development state: the working tree is dirty on purpose, `check`
reports it, and doctor fails on it unless given `--allow-dirty`. Plain
`sync` restores the copies. Nothing in link mode may be committed.

**Installer lock.** Every writing verb (`init`, `sync`, `update`, `remove`)
holds an exclusive `flock` on `$(git rev-parse --git-path project-files.lock)`
from preflight until publication finishes. The lock is per worktree and
lies outside the working tree. Its path is an interface: another installer
that writes the same root instruction files or skill directories takes the
same lock to serialize with this one. `check` and `doctor` report the state
they see without taking the lock.

**Preflight: the index is the checkpoint.** Before writing, an installer
lists every path it would create, modify or delete, and refuses if any of
them has unstaged changes (the working tree differs from the index),
exists untracked, or is ignored by Git. The one exception: in link mode,
`sync` may replace the symlinks and the inventory that `link` wrote. Staged
changes are accepted, so changes made by hand or by another installer can be
staged before an install runs, with no commit in between. Every successful
install prints its touched paths and the `git add -- …` command. An
installer never stages or commits.

**Writing and failure.** The complete result is first built in a
temporary directory and validated: JSON and TOML parse, block markers are
unique, and the inventory and descriptor agree. Each destination is then
rechecked against its preflight state and published by writing a
temporary file in the destination's own directory, `fsync`ing it and
renaming it over the destination, so no rename crosses filesystems. The
order is managed files, then shared entries and blocks, then the
inventory, then the descriptor last. An update writes the revision and any
explicitly requested release change, keeping the other keys and comments
byte for byte.

If any write fails, the installer stops. It prints the leaf paths it
touched, each shell-quoted, with the commands that restore them:
`git restore -- PATHS` for paths the index knows, `rm -f -- PATHS` for new
files and symlinks, then `rmdir` for the directories it created, deepest
first. It then exits 2. Until the tree is restored, `check` reports the
disagreement between files, inventory and descriptor, and doctor fails.

**Project operations.** Run these commands from the project checkout, or
name it with `--project-root DIR` from anywhere:

`init [--revision REV]`
: Refuse if the descriptor exists. Resolve `REV` (default `stable`) in the
  runtime checkout to a full commit, and install exactly that revision:
  files, entries, the root instruction block, inventory, then the
  descriptor. `isabelle-tooling init` also renders the session scaffold
  that `new-project.sh` writes today, from the same Git object, and
  publishes it with the integration under the same rules, descriptor last.
  `new-project.sh` becomes that renderer, taking the resolved commit and
  reading its templates with `git show`; its options pass through `init`.

`sync`
: Install exactly the descriptor's revision in copy mode, reading every
  file from that Git object (`git show REV:PATH`), never a working tree.
  Idempotent. Refuses drift in managed content rather than overwriting it.
  Without an inventory it refuses and names `update`.

`sync --link [--source DIR]`, `sync --check`
: Link mode, above; and the read-only check, which exits 0 when files,
  inventory and descriptor agree with the pinned object and 1 otherwise.

`update REV`
: The only verb that changes the pin. Stage the target revision's files,
  merge the owned entries and blocks into the staged copies, validate,
  install, write the descriptor last. `update stable` moves to the current
  validated commit. Without an inventory, `update` is the adoption path
  for a project whose descriptor predates project delivery, such as the
  offer-exchange checkout. It validates the descriptor, requires every
  managed target to be absent (anything present, including an existing
  block, is a collision), and installs; the inventory is written, and then
  the new revision line last.

`remove`
: Delete the unchanged managed files, entries and blocks, the inventory
  directory and the descriptor. Refuse and list anything edited. The
  Isabelle session and the root instruction files belong to the project.

`doctor [--allow-dirty]`
: Run the full read-only setup check described below.

All of these exit 0 on success, 1 when they refuse or a check finds a
problem, and 2 on a usage error, a missing prerequisite or a failed write.
The installable set is read from the manifest at the target revision.
The descriptor's Isabelle release selects the manifest.

**`stable` and the validation record.** The `stable` branch moves only by
fast-forward, and only to a validation record commit: a commit whose parent
is the validated commit, and whose only change appends an entry to
`docs/validation.md`. The entry records the date, the candidate revisions,
the host versions and the fixture results. The record commit is made on
`main`, the mechanical checks are rerun at exactly
that commit (the repository's tests, the installer tests, and doctor on a
fixture project pinned to it), and only then does `stable` fast-forward.
`init` and `update stable` pin that record commit. The runtime checkout has `stable` checked out, and
development happens on `main` in a linked worktree. The runtime moves with
`git -C RUNTIME merge --ff-only COMMIT`, followed by
`git submodule update` and, if the AutoCorrode pin changed, the ic2 build
and I/Q plugin installation.

**Machine paths.** No committed file contains an absolute path or
credential. Machine paths come from the environment (`ISABELLE_TOOLING_ROOT`
or `PATH`) or from host-local configuration. Link-mode
symlinks are the only files that record absolute paths, and they are never
committed.

## Isabelle tooling

**Entry point.** `bin/isabelle-tooling` in the tooling repository, with
`skills list`, `skills show NAME`, and the project verbs. It needs Python
3.11 or later for `tomllib`.

**Instruction revision selection.** Inside a project, `skills list` and
`skills show` read the Git object named by the descriptor's
`tooling_revision`, as `sync` does, never a newer tool on `PATH`, the working
tree or a linked skill, and only the skills of the project's Isabelle
release. Outside a project they read `stable`, report the commit it resolves
to, and cover every release with a manifest there; `skills list` marks a
skill that only one release installs. A malformed descriptor or a missing
pinned object is an error, not a reason to fall back. Reading needs no
prover, host plugin or network, and does not show that the runtime matches;
that is doctor's job.

**Manifest.** The manifest at each revision lists the skills, managed
files, JSON entries and block templates it installs.
`extension/project/manifest.json` covers the default workflow.
`extension/project/manifest-pide-ai.json` covers Isabelle2026. The
synchronizer reads the manifest from the target revision. The manifests
list the kinds `["code", "theory"]`, and
`isabelle-modeling`, `isabelle-differential` and `isabelle-assurance`
carry `"kinds": ["code"]` (see "Project kinds" above).

**Project kinds.** The descriptor's optional `model_kind` is `code` or
`theory`, and both descriptor parsers refuse any other value. Absent, the
project is `code`, and `ToolingSpec.kind` returns `None`, so such a project
installs every skill at any revision, as before kinds. `init --kind
theory` writes `model_kind=theory` and renders `templates/theory/`
(`isabelle-tooling.conf`, and `formal/AGENTS.md`, `README.md`, `ROOT` and
`Session.thy`; `ROOTS` is shared), and refuses a revision without that
directory; `init` without `--kind` renders exactly what it did before
kinds. A tooling clone from before kinds stops at the descriptor of a
theory project with `unknown key: model_kind`, before any change.

**Project files for the default workflow.**

- `isabelle-tooling.conf`, whose `tooling_revision` is the pin.
- `.isabelle-tooling/inventory.json`.
- `.agents/skills/isabelle-{setup,modeling,proving,differential,assurance}/`
  in a code project and `.agents/skills/isabelle-{setup,proving}/` in a
  theory project, each copied whole from `extension/skills/` at the pin,
  with their Claude aliases.
- `.claude/agents/ic2-prover.md`, from `extension/agents/ic2-prover.md`.
- `.codex/agents/ic2_prover.toml`, from `extension/agents/ic2_prover.toml`.
- In `.mcp.json`, the member `/mcpServers/iq`:

  ```json
  {"command": "${ISABELLE_TOOLING_ROOT}/extension/bin/iq-bridge.sh",
   "args": [], "env": {"IQ_MCP_BRIDGE_PORT": "8765"}}
  ```

- In `.codex/config.toml`, the block. Codex CLI 0.155.1 parsed this form in
  a user-level configuration on 2026-09-28, and exposed `env_vars`; the
  project-level layering is still a fixture check:

  ```toml
  # BEGIN isabelle-tooling
  # Managed by isabelle-tooling; change it with `isabelle-tooling update`.
  [mcp_servers.iq]
  command = "bash"
  args = ["-c", "exec \"$ISABELLE_TOOLING_ROOT/extension/bin/iq-bridge.sh\""]
  env_vars = ["ISABELLE_TOOLING_ROOT"]

  [mcp_servers.iq.env]
  IQ_MCP_BRIDGE_PORT = "8765"
  # END isabelle-tooling
  ```

- The `isabelle-tooling` block in the root instruction files, with
  `FORMAL_REL` substituted from the descriptor. It is the same in both
  kinds, and names no skill but setup, so that a runtime from before kinds
  can still install it:

  ```markdown
  <!-- BEGIN isabelle-tooling -->
  <!-- Managed by isabelle-tooling; change it with `isabelle-tooling update`. -->
  ## Isabelle formal model

  This repository has Isabelle theories under `FORMAL_REL/`; read
  `FORMAL_REL/AGENTS.md` before working on them. The workflow is in the
  `isabelle-*` skills; start with `isabelle-setup` until
  `"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" doctor` passes.
  <!-- END isabelle-tooling -->
  ```

The server name `iq` is fixed. The Claude worker profile's
`disallowedTools: mcp__iq` matches exactly the tools of a server named
`iq`. It would not have matched the retired plugin's server, whose tools
were named `mcp__plugin_<plugin>_iq__*`; with the project server, the
acceptance fixtures found that a Claude Code worker sees no I/Q tools.
The Codex profile disables `iq` by the same name, but Codex CLI 0.155 does
not honour that for a spawned agent: the acceptance fixtures found the main
session's I/Q tools listed to the worker, spawned with or without the
parent's conversation. There the worker's instructions, which forbid every
I/Q call, are the only barrier.

**Doctor additions.** Besides today's checks, Isabelle doctor fails on:

- the Isabelle formal-modeling host plugin, or its marketplace, in either
  host's configuration;
- an `iq` MCP declaration at user level for either host (the project's is
  the one allowed);
- a user-level `ic2_prover` or `ic2-prover` profile, since it would
  duplicate the project's;
- any `sync --check` finding (link mode under `--allow-dirty` is a note);
- a runtime checkout, ic2 registration or jEdit I/Q plugin that does not
  match the pin.

It reads host configuration from `CLAUDE_CONFIG_DIR` and `CODEX_HOME` when
set, else `~/.claude`, `~/.claude.json` and `~/.codex`, so the fixtures can
isolate them. Doctor reads these files and produces a human-readable
report.

## Delegation

A proof worker's brief gives the assigned ic2 worktree, proof target,
allowed file edits, commit authority and the report or check-in boundary.
The worker stops and reports back when it needs broader scope, and
reports its changes and validation results to the coordinating agent.

## Decisions made in implementation

Recorded on 2026-09-28, when the installer was implemented.

- `sync --check` exits 1 in link mode, since the files are not the pinned
  ones. `sync --check --allow-dirty` makes link mode a note, as does
  doctor with the same flag. A runtime checkout not at the pin fails,
  with or without `--allow-dirty`.
- The inventory records a `marker` with each array-element entry, so an
  entry that a later manifest drops can still be found and removed.
- Installed files get Git's checkout modes, 0777 or 0666 less the umask, so
  a `git restore` after a failure gives the same modes.
- Restore commands are printed as `rm -f`, then `rmdir`, then `git
  restore`, run from the checkout root, so that `git restore` never writes
  through a symlink an install created. A link-mode symlink removed by a
  failed install is not recreated by them; the message says to rerun
  `sync --link`.
- `update` refuses in link mode; `sync` first restores the copies.
- `remove` without an inventory refuses, and `remove` also refuses when
  the inventory directory holds files it did not install.
- An emptied JSON file is deleted, and so is a TOML file left empty by
  removing its block; directories left empty by deletions are removed,
  never the checkout root.
- The synchronizer the delivery plan called `scripts/sync-extension.sh` is
  `scripts/isabelle_tooling.py` with `project_files.py`;
  `bin/isabelle-tooling` sends `doctor` to `doctor.sh` and the rest there.
- `new-project.sh` takes `--revision COMMIT --stage DIR` and renders into an
  empty directory; it no longer writes into a checkout itself. The
  session README no longer embeds the revision, which `update` would make
  stale; it points at `tooling_revision`.
- `skills list` prints its revision on its first stdout line; `skills
  show` keeps stdout to the file's bytes. Inside a project means below the
  nearest `isabelle-tooling.conf`, as `ic2.sh` resolves it.
- Doctor also fails when `ISABELLE_TOOLING_ROOT` is unset or names another
  checkout, and on a local-scope `iq` server that `~/.claude.json` records
  for the project. The extension `REVISION` comparison is gone already,
  since an installed plugin now fails doctor.
- The renderer puts the same proof-worker instructions in both host
  profiles. The proving skill describes how to brief a worker.
