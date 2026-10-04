# Plan: theory projects, the tooling without the code-level method

Proposed on 2026-10-01 and reviewed by Codex (`gpt-6-astra`, xhigh effort)
the same day; revised on 2026-10-03 after a review against the code at
`stable`. History has both reviews. Stages A to C done on 2026-10-03
(History, "Implementation" and "Validation"); stage D's adoption is
recorded outside this repository.

The occasion is a paper repository that is starting an Isabelle model of a
protocol and has no implementation to model. `isabelle-tooling init` there
installed the code-level conventions interview, the bit-precise modeling
standard, differential testing and a session that imports
`HOL-Library.Word`. None of it applies.

## Goal and definition of done

A project is one of two kinds:

- `code`, today's behaviour, models an implementation.
- `theory` gets the tooling's infrastructure and nothing that presumes code:
  ic2, I/Q, the proof worker, setup and the proving discipline.

Uses without code (protocol specifications, mathematics, a paper's
companion theories) are too varied for a shared method, so the project
supplies its own.

Done means:

- `isabelle-tooling init --session NAME --kind theory` writes:
  - a descriptor with `model_kind=theory`;
  - a session whose only theory is the blank `theory NAME imports Main
    begin end`, and whose `ROOT` makes `HOL-Library` importable;
  - a `formal/AGENTS.md` with no conventions block;
  - the skills `isabelle-setup` and `isabelle-proving` only;
  - the two worker profiles and the `iq` server, as today;
  - a root instruction block that names no code-level skill.
- In that project, doctor passes, `isabelle build -D formal` passes, and
  `sync --check` is clean.
- `init` without `--kind` renders exactly today's descriptor and session
  files.
- A descriptor without `model_kind` is a `code` project. It installs
  today's five skills, worker profiles and `iq` entries; only the root
  instruction block changes, to the kind-independent text (see "Selecting
  the skills by kind").
- A runtime older than kind support refuses a theory project's descriptor
  and changes nothing.
- A code project moves to the new revision with today's procedure: the
  runtime at the old pin runs `update NEW`, then the clone moves.
- Changing a project's kind is a documented migration (below).
- In either kind, `isabelle-proving` requires a proved model for every
  locale with assumptions (see "Skill text").
- Not in scope: an interview or a method for non-code projects, a new
  skill, and any change to ic2, I/Q, jEdit or doctor's environment checks.

The kind lives in the descriptor, not only in an `init` flag, because
`sync`, `update` and doctor recompute the expected project files from the
descriptor on every run.

## Compatibility across revisions

Revisions meet in four ways, and the design keeps each one working:

- **The runtime at the old pin reads the new revision's manifest** in
  `update NEW`, so it can never know about kinds. The new revision is
  therefore designed so that code projects need nothing kind-aware:
  - the root instruction block gains no placeholder, because the current
    runtime supplies only `FORMAL_REL` and refuses any template with a
    placeholder left over (`substitute` in `scripts/project_files.py`);
  - the new manifest fields are ones the old reader ignores (it reads only
    a skill entry's `name` and `source`), so it installs all five skills,
    which is right for a code project;
  - `update` changes only the revision line, so a code descriptor stays
    without `model_kind`.
- **The new runtime renders an older revision's templates** in
  `init --revision OLD`, because the renderer runs from the runtime and
  reads the templates at the revision (`scripts/new-project.sh`). So:
  - the code templates stay at `templates/formal/` and
    `templates/isabelle-tooling.conf`;
  - the theory ones are added under `templates/theory/`;
  - `init --kind theory` at a revision without `templates/theory/` is
    refused, naming the revision.
- **A theory project is moved to an older revision** with `update OLD`.
  - The manifest gains a top-level `"kinds"` list of the kinds a revision
    supports. A manifest without that list supports only projects that
    name no kind.
  - `update`, `sync` and `init` refuse a project whose kind the target
    revision does not support, so an older manifest can never install all
    five skills into a theory project.
  - A code project that names no kind moves back and forth as today.
  - Revisions before theory support cannot read a descriptor that names a
    kind. That is why `init` writes `model_kind` only for `theory`. An
    explicit `model_kind=code` is accepted, but it pins the project to
    revisions with kind support.
- **A runtime older than kind support meets a theory project**, for
  example a collaborator's clone that has not moved to the project's pin.
  Both of its descriptor parsers refuse `model_kind` as an unknown key, so
  `sync`, `update`, doctor and every script stop with `unknown key:
  model_kind` before changing anything. That message is all such a user
  sees, so the setup skill and the README say what it means: the clone
  predates kind support and must be checked out at the project's pin. No
  unit test can run an old runtime, so validation checks this with the
  real previous one.

## The descriptor

- **New key.** `model_kind` is optional and takes `code` or `theory`; when
  absent, the project is `code`. It is added to both parsers, and both
  refuse any other value:
  - `DESCRIPTOR_OPTIONAL_KEYS` in `scripts/common.sh`;
  - `OPTIONAL_KEYS` and `parse_descriptor` in `scripts/isabelle_tooling.py`.
- **When `init` writes it.** Only for `theory` (see "Compatibility across
  revisions"). `format_version` stays 1.
- **Differential keys.** `export_name`, `model_dispatch` and
  `audit_collection` stay valid in any kind. `model-runner.sh` and
  `export-check.sh` operate on an exported Isabelle program and an audit
  collection, not on an implementation, so a theory project may use them.
  The theory descriptor template only omits the commented differential
  block, and `isabelle-differential` stays code-only because its method
  compares against an implementation.
- **`source_rel`** stays required, and as today must name an existing
  directory: `resolve_project` in `scripts/common.sh` resolves it for
  doctor, ic2 and every script. `init`'s default `.` serves a theory
  project. Doctor's line that prints the source and formal roots also
  prints the kind, since in a theory project the source root is just the
  checkout.

## `init` and the renderer

- **Flag.** `isabelle-tooling init --kind {code,theory}`, default `code`,
  passed through to `scripts/new-project.sh --kind`.
- **Templates for `code`.** Unchanged and read from today's paths.
- **Templates for `theory`.** Read from `templates/theory/`. The
  substitutions stay the same, so there are no new placeholders.
  - `isabelle-tooling.conf`: today's, with `model_kind=theory` and without
    the commented differential block.
  - `formal/ROOT`:

    ```
    session @SESSION@ = HOL +
      description "Isabelle/HOL theories of @PROJECT_NAME@."
      options [timeout = 600, document = false]
      sessions
        "HOL-Library"
      theories
        @SESSION@
    ```

    The `sessions` entry is kept from the code template because it is not
    code-specific. It makes HOL-Library's theories importable, which theory
    projects often need (`Multiset`, `FSet`), and it loads nothing until a
    theory imports one. Without it, Isabelle2025-2 refuses such an import
    with `Bad import of theory "HOL-Library.FSet": need to include sessions
    "HOL-Library" in ROOT` (checked on 2026-10-03).

  - `formal/Session.thy`:

    ```
    theory @SESSION@
      imports Main
    begin

    end
    ```

  - `formal/AGENTS.md`:
    - the title and a two-sentence introduction saying that generic
      Isabelle rules come from the `isabelle-setup` and `isabelle-proving`
      skills;
    - today's "Editing theories" section (ASCII symbol escapes on disk),
      verbatim;
    - a "Layout" section naming the session directory;
    - "Notes specific to this project", left empty.

    It has no "Conventions" section, and its layout does not mention
    differential testing.
  - `formal/README.md`: today's, except that it calls the session the
    Isabelle/HOL theories of the project rather than a model, and says
    that `AGENTS.md` carries the project's notes rather than its modelling
    conventions.
  - `formal/ROOTS` and the `CLAUDE.md -> AGENTS.md` link: as today, from
    the shared `templates/formal/ROOTS`.

## Selecting the skills by kind

- **Manifest.** In `extension/project/manifest.json`:
  - the top-level `"kinds": ["code", "theory"]` lists the kinds the
    revision supports;
  - a skill entry may carry `"kinds": [...]`, and an entry without it
    applies to every kind;
  - `isabelle-modeling`, `isabelle-differential` and `isabelle-assurance`
    get `["code"]`.

  `kinds` is allowed only on skill entries. Worker profiles,
  configuration entries and blocks are the same for every kind.
- **The shared module.** `scripts/project_files.py` is an identical copy of
  agent-board's `src/project_files.py`, so the rule is generic there.
  - `desired_state` asks an optional hook, `spec.kind(values)`.
  - If the spec has no hook or the hook returns `None`, every entry is
    installed and the top-level list is not consulted. That is
    agent-board's case, and that of a code project that names no kind.
  - With a kind `K`, `desired_state` refuses unless the top-level list
    contains `K`. It installs a skill entry only if the entry has no
    `kinds` or its `kinds` contains `K`.
  - It also refuses `kinds` on any entry other than a skill.
  - `ToolingSpec.kind(values)` returns `values.get('model_kind')`.
- **The instruction block.** `extension/project/instructions-block.md`
  becomes kind-independent and names no skill but setup:

  ```markdown
  <!-- Managed by isabelle-tooling; change it with `isabelle-tooling update`. -->
  ## Isabelle formal model

  This repository has Isabelle theories under `@FORMAL_REL@/`; read
  `@FORMAL_REL@/AGENTS.md` before working on them. The workflow is in the
  `isabelle-*` skills; start with `isabelle-setup` until
  `"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" doctor` passes.
  ```

  The first line is unchanged: every installed block starts with it. Code
  projects receive the new text on their next `update`, through the old
  runtime as well.
- **`skills list`.** It prints each skill's kinds. Inside a project, it
  marks the skills the project's kind installs.

## Changing a project's kind

Changing kind is a migration, not just a key edit. The project-owned files
(`formal/AGENTS.md`, `ROOT`, the theories) are never re-rendered, and they
carry instructions for the old kind.

**From code to theory:**

1. Set `model_kind=theory` in `isabelle-tooling.conf`.
2. If `source_rel` names an implementation directory that will go away,
   set it to `.`.
3. Edit the project-owned files by hand, using the theory templates as
   the reference:
   - in `formal/AGENTS.md`, remove the "Conventions" section and the
     mentions of the code-level model and differential testing; keep
     "Notes specific to this project" and any other project content;
   - in `formal/README.md`, reword the sentence saying that `AGENTS.md`
     carries the modelling conventions;
   - in the session's entry theory, remove the `text` block asking for one
     theory per source module and one definition per source function, and
     the `HOL-Library.Word` import unless a theory still needs it;
   - in `ROOT`, reword the description, and keep `sessions "HOL-Library"`.
4. Run `isabelle-tooling sync`. It removes the three code-only skills and
   their Claude aliases. Its preflight looks only at the paths it changes,
   so the hand edits need not be staged first; it refuses if one of those
   skills is edited, unstaged or untracked.
5. Check that doctor passes and the session builds, stage the hand edits
   and the removals, and commit.

**From theory to code:**

1. Remove `model_kind`, or set it to `code`.
2. Run `sync`, which adds the three skills.
3. Check that `ROOT` still lists `sessions "HOL-Library"`, which the theory
   template writes: the code-level model imports `HOL-Library.Word`, and
   the build refuses that import without the entry. Review the `ROOT`
   description and `formal/README.md`, which the theory template words for
   theories rather than a code-level model.
4. `isabelle-modeling` §1 creates the conventions block in
   `formal/AGENTS.md` when it is missing. Today it says the template
   "already has the headings"; that sentence changes.

**Behaviour during a switch.** Until the sync, doctor reports the mismatch
through its `sync --check` finding. A switch never touches agent-board's
skill or blocks. An edited code-only skill blocks the switch to theory,
under the existing refusal for edited managed files. No new verb is
needed: `update` remains the only command that moves the pin, and the kind
is not the pin.

## Skill text

- **`isabelle-proving`, "Stating and proving a property":**
  - First bullet: "State a property over the model's definitions — in a
    code-level model, over the code-level definitions or a characterization
    already proved equal to them (`isabelle-modeling`)".
  - Second bullet: "fix the statement, never the model" applies to a
    code-level model, where the source is the fixed reference. Elsewhere a
    counterexample may expose a wrong definition: investigate both, and
    change definitions only within the task's scope.
  - Third bullet: the word-level and no-wrap advice is introduced as
    applying to code-level models.
  - Last bullet: the export check applies "where the project exports a
    model". A finished property also needs the model lemmas of the locales
    it lives in.
  - A new bullet, for both kinds, settled on 2026-10-03:

    > Every locale with assumptions, its own or inherited, has a model: a
    > lemma next to the locale proving that concrete parameters satisfy
    > them, such as `lemma child_model: "child 7 3" by unfold_locales
    > simp_all`. A locale whose assumptions contradict each other makes
    > every theorem in it provable, and neither `quickcheck` nor `nitpick`
    > can notice, because a counterexample must satisfy the assumptions. A
    > small finite instance is enough, and a model of a locale is a model
    > of every locale it extends. Prefer this lemma about the locale's
    > predicate to a global `interpretation`, which also copies the
    > locale's later theorems into the theory. While developing,
    > `nitpick [falsify = false]` on the assumptions finds a model or
    > reports that there is none. A locale still without a model is
    > unfinished work: say so in the report.

    Each claim in it was checked on Isabelle2025-2 (see History).
- **`isabelle-setup`:**
  - The opening, "this skill and the other four", becomes "this skill and
    the others the project's kind installs".
  - §6 describes `--kind`. When the checkout has no code under study, ask
    whether the project is `theory`.
  - §7: in a code project, hand over to the four skills as today; in a
    theory project, to `isabelle-proving`.
  - §1 explains `unknown key: model_kind`: the runtime clone predates kind
    support and must be checked out at the project's pin.
- **`isabelle-modeling` §1:** creates the conventions block when it is
  missing (see "Changing a project's kind").
- **Unchanged.** The `ic2-prover` profiles name none of the code-level
  skills. `isabelle-differential` and `isabelle-assurance` stay code-only.

## Documentation, in both repositories

- **`README.md`:**
  - The opening paragraph stops defining the tooling exclusively around
    bit-precise models of an implementation: it serves Isabelle projects,
    with a code-level method for those that model an implementation.
  - Quick start: `--kind theory`.
  - "init writes … the five skills" becomes "the skills of the project's
    kind".
  - The descriptor example and the key list in "Binding a project" gain
    `model_kind`.
  - "Differential testing" says the runner and the export check work in
    either kind.
  - "The extension directory" says which skills each kind receives.
  - The error a clone older than kind support gives for a theory project,
    as in the setup skill.
- **`docs/delivery-contracts.md`:**
  - Isabelle tooling, Manifest: the top-level and per-skill `kinds`, and
    the refusal.
  - Project files: the skill list depends on the kind.
  - The new instruction block text.
  - Shared rules, "Descriptors": `isabelle-tooling.conf` no longer has
    "unchanged keys"; it gains the optional `model_kind`.
  - Shared rules, "Skill directories": "the five `isabelle-*` names"
    becomes "the `isabelle-*` names its manifest lists".
  - Shared rules: the `spec.kind` hook, refusing `kinds` outside skill
    entries, and the support check.
- **agent-board.** `docs/project-integration.md` holds the board's copy of
  the shared rules, and the contracts require every change to them to be
  made in both repositories. It gets the same "Descriptors", "Skill
  directories" and `spec.kind` text.

## Tests

Each stage below lands with its tests.

**Stage A, the shared module:**

- In `tests/project_install_test.py` and agent-board's suite, with a fake
  spec:
  - without a kind, every entry is installed regardless of `kinds`;
  - with a kind, skills are filtered;
  - a kind is refused against a manifest that has no top-level list or
    does not include it;
  - `kinds` on a non-skill entry is refused.
- A byte comparison of the two copies of the module (see "Validation and
  `stable`").

**Stage B, theory support:**

- `tests/new_project_test.sh`:
  - a theory render: `Session.thy` is exactly the blank theory, with no
    `Word` import; `ROOT` lists `sessions "HOL-Library"`; `AGENTS.md` has
    no `## Conventions`; the descriptor parses with `model_kind=theory`;
  - a code render byte-identical to today's, with no `model_kind` line;
  - `--kind other` is refused;
  - `--kind theory` at a revision without `templates/theory/` is refused.
- `tests/descriptor_test.sh`, `tests/common_test.sh`:
  - both values are accepted, absent means `code`, and an unknown value is
    refused;
  - differential keys are accepted with `theory`;
  - the shell and Python parsers agree on every case.
- `tests/project_install_test.py`:
  - a theory init installs exactly `isabelle-setup` and `isabelle-proving`,
    their Claude aliases, the two profiles and `iq`, and `sync --check` is
    clean;
  - a legacy descriptor installs all five skills;
  - a theory project in link mode links exactly the two skills;
  - a theory project with `claude_skills: shared` installs exactly the two
    skills;
  - the migration from a real code scaffold, by the steps above, ends with
    a clean `sync --check`. The scaffold files are untouched except the
    hand edits, and agent-board's skill and blocks are preserved. The
    reverse switch adds the three skills again;
  - an edited code-only skill blocks the switch to theory;
  - `update` of a theory project to a revision without kind support is
    refused;
  - "Replacing an uncommitted code scaffold" below, on an untracked code
    scaffold whose root `AGENTS.md` has gained the project's own text and
    whose `.claude/` holds an unmanaged file: both survive, and the result
    matches a fresh theory init.
- `tests/extension_manifest_test.py`:
  - the top-level `kinds` is `["code", "theory"]`;
  - each skill's `kinds` is a subset of it;
  - every kind gets `isabelle-setup` and `isabelle-proving`;
  - no non-skill entry carries `kinds`.
- `tests/isabelle/template_build_test.sh`, a new `make check-isabelle`
  test, since neither template is build-tested today: render each kind's
  session and build it with `isabelle build`, then build the theory
  session once more with a theory that imports `HOL-Library.FSet`.
- `make validate` and `make check-isabelle`.

## Validation and `stable`

As in [validation.md](validation.md): the mechanical checks at the
candidate, then a validation record, then `stable` moves. The unit tests
build every revision from the working tree, so the checks between real
revisions are made here:

- **Upgrade with the real previous runtime.** With the runtime at the
  previous `stable`, `update CANDIDATE` on a code fixture succeeds and
  installs five skills and the new block text. After the clone moves,
  doctor passes.
- **Back to the previous revision.** From the candidate runtime:
  - `update PREVIOUS` on a code project succeeds;
  - on a theory project it is refused;
  - `init --revision PREVIOUS` for a code project still renders.
- **An older runtime meets a theory project.** With the runtime at the
  previous `stable`, `sync --check`, `sync`, `update CANDIDATE`, doctor and
  `scripts/ic2.sh start` on the theory fixture each fail with `unknown key:
  model_kind`, and `git status` shows no change.
- **Code fixtures.** Rerun the installer and doctor checks on the existing
  new-project fixtures.
- **Theory host fixture.** A fresh `git init` repository with
  `init --kind theory`, on Claude Code and Codex CLI:
  - discovery shows exactly the two skills, the `iq` server and the worker
    profile;
  - doctor passes and the session builds;
  - asked to add a small definition and a lemma about it, through ic2, the
    agent writes no conventions block, adds no `Word` import and cites no
    code-level skill;
  - asked to add a locale with assumptions and a lemma in it, the agent
    also adds a model lemma for the locale.
- **Both repositories.** The shared module is byte-identical (`cmp`) at
  both candidates. Each repository's validation record names both
  revisions, and the tooling and agent-board commits are paired.

## Order of work

1. **Stage A, the shared module.**
   - The `spec.kind` hook, the support check and the `kinds` validation,
     with tests.
   - Paired commits in the tooling and agent-board, including both
     repositories' shared-rules text.
   - No manifest uses `kinds` yet, so behaviour is unchanged.
2. **Stage B, theory support, landed together** so that no intermediate
   commit exposes `--kind theory` with five skills or code-specific setup
   text:
   - the descriptor key in both parsers;
   - `templates/theory/`, `new-project.sh --kind`, `init --kind`;
   - the manifest `kinds`, the new instruction block, `skills list`;
   - the skill text;
   - the README and the contracts;
   - all the stage B tests.

   `make validate` and `make check-isabelle` pass at its end.
3. **Stage C:** the validation above, the validation records, `stable`.
4. **Stage D:** adopt it in the paper repository that prompted it, by
   "Replacing an uncommitted code scaffold" below. Its project-specific
   steps are kept outside this repository, since these docs name no
   private projects or local paths.

## Replacing an uncommitted code scaffold

A project where `init` ran without `--kind`, and where nothing it wrote has
been committed, can start over as a theory project instead of migrating.
Deleting the untracked paths by hand is not safe: `.claude/` may hold the
host's own `settings.local.json`, and the root `AGENTS.md` may have gained
the project's own instructions since. `remove` deletes only what the
inventory records, so the recipe uses it. It was run on 2026-10-03 on a
copy of such a project, with a code-kind `init` standing in for step 5:

1. Check that the session holds no later work. Then stage, without
   committing, the descriptor, `.isabelle-tooling/`, the session files,
   the root `AGENTS.md` and `CLAUDE.md`, and the host paths `init` wrote:
   `.agents/`, `.claude/agents/`, `.claude/skills/`, `.codex/` and
   `.mcp.json`. `remove`'s preflight refuses untracked paths.
2. Run `isabelle-tooling remove`. It deletes the skills, profiles, owned
   entries and blocks, the inventory and the descriptor. The session, the
   project's own text in the root `AGENTS.md`, the `CLAUDE.md` link and
   every unmanaged file stay.
3. Delete the files `init` rendered under the formal directory, which a
   new `init` would refuse as collisions: `ROOTS`, `AGENTS.md`,
   `README.md`, the `CLAUDE.md` link and the session directory, from the
   index with `git rm --cached` and from disk. With the default `formal`,
   that is the whole directory.
4. Stage what `remove` printed, with the `git add -A` command it gives.
   `git status` then shows only the project's own changes, including the
   kept root `AGENTS.md` and `CLAUDE.md`.
5. Once `stable` has moved, run `isabelle-tooling init --session NAME
   --kind theory`, stage the printed paths, run doctor and
   `isabelle build -D FORMAL_REL`, and commit.

## Open questions

None.

## History

**2026-10-01.**

- Drafted after a paper repository's init. The user ruled out an
  interview or a method for non-code projects: such a project gets the
  tooling and a blank session importing `Main`.

**Review by Codex** (`gpt-6-astra`, xhigh effort, read-only), the same day.
It judged the core design sound and found ten problems, all adopted:

1. (High) A new `@SKILLS@` placeholder in the instruction block would make
   the old runtime's `update NEW` fail on the leftover placeholder. The
   block now names no skill list.
2. The first draft claimed older runtimes never meet `model_kind`, and left
   moving a project back to an older revision undefined. This gave the
   support check, and writing the key only for `theory`.
3. Moving the code templates would break `init --revision OLD`. They stay
   where they are.
4. A key edit plus `sync` is not a complete migration from code to theory,
   because `formal/AGENTS.md` still prescribes the code interview. This
   gave the documented migration.
5. A theory project does read `source_rel`: `resolve_project` requires an
   existing directory. The draft's claim that it never reads the key was
   wrong.
6. Banning the differential keys tied general Isabelle features to the code
   method. They are now allowed in either kind.
7. `isabelle-proving`'s "never the model" presumes code as the reference.
   It is now qualified.
8. The adoption recipe misdescribed `remove`, which deletes its blocks and
   refuses untracked paths. Adoption then deleted the verified untracked
   paths; the review of 2026-10-03 replaced that with staging and
   `remove`.
9. The order of work exposed `--kind theory` before filtering and the skill
   text existed, and it left tests to the end. Stage B now lands together,
   with tests in each stage, plus link-mode, shared-alias and
   board-preservation cases.
10. Documentation was missing: the setup skill's "other four", the README's
    opening, "the five `isabelle-*` names" in the shared rules, and
    agent-board's `docs/project-integration.md`, with paired commits and a
    byte comparison.

**2026-10-03.**

- The user chose `theory` as the kind's name over `plain` and `general`.
  The plan was renamed from `plain-projects-plan.md`, and the entries above
  use the new name; the branch is still `plain-projects`. In prose, "theory
  project" names the kind, since "theory" alone means an Isabelle theory.
- Theory projects do not get `isabelle-assurance`, as proposed. Its first
  question, the export link, the chain and most of its statement template
  presume an implementation, and `isabelle-proving` already requires a
  finished property to have no `sorry`, `oracle` or `axiomatization`.

**Review against the code**, the same day, at the user's request, at
`stable` `f013ec6`, two commits after the plan's base. The compatibility
claims held: the old manifest reader reads only a skill's `name` and
`source`; `substitute` supplies only `FORMAL_REL` and refuses leftovers;
`update` rewrites only the revision line; the renderer reads templates at
the target revision; `make_plan` already removes dropped skills and refuses
edited ones; the worker profiles, the model runner and the export check
presume no code; agent-board never parses the tooling's descriptor. These
changes were made:

1. (High) The adoption recipe deleted the root `AGENTS.md` and `.claude/`,
   which by then held the project's own instructions and the host's
   `settings.local.json`. It became "Replacing an uncommitted code
   scaffold", which stages the paths and uses `remove`, and it was run on
   a copy of the project.
2. (High) The plan named a private project and a local path, which the
   docs have avoided since `cabf405`. The occasion is now described
   generically, and that project's own adoption steps are kept outside
   the repository.
3. The definition of done said code projects install exactly what they do
   today, while the instruction block changes for them too.
4. The theory `ROOT` dropped `sessions "HOL-Library"`, so any
   `HOL-Library` import, including a later switch to code, failed to
   build. It keeps the entry, and both migrations now cover `ROOT`,
   `formal/README.md` and the entry theory.
5. The code-to-theory migration staged the hand edits on the grounds that
   `sync`'s preflight required it; the preflight looks only at the paths
   `sync` changes.
6. The new instruction block had lost the managed-by comment line.
7. The documentation list missed the shared rules' "unchanged keys" for
   the descriptor, in both repositories, and the README's section on the
   extension directory.
8. Nothing checked that a runtime older than kind support refuses a theory
   project. It is now a compatibility case, a validation check and a note
   in the setup skill. Doctor also prints the kind.
9. Neither template was build-tested. A `make check-isabelle` test now
   builds both.
10. The validation section named a `stable` commit that has since moved;
    it now says "the previous `stable`".

**Locale models**, the same day. The open question was settled wider than
proposed: instead of witnesses for headline theorems only, every locale
with assumptions gets a proved model, in either kind. Throwaway theories
built on Isabelle2025-2 confirmed the mechanics:

- a locale assuming `n > 5` and `n < 3` proves `n = 42` by `simp`, and
  `quickcheck` and `nitpick` find no counterexample to the same statement
  written with premises;
- `unfold_locales` proves a model lemma about a locale's predicate, also
  for a locale over a type parameter instantiated to `nat`;
- a child locale's predicate includes its parent's, so one model covers
  both, and a locale without assumptions has no predicate;
- `nitpick [falsify = false]` finds a model of satisfiable assumptions and
  none of contradictory ones.

A theorem's own premises outside any locale are not covered by the rule.

**Implementation**, 2026-10-03, at the user's request, in the order of
work: stage A as tooling `6e4050e` and agent-board `3b2ba94`, stage B as
`dcb7809`. The plan's two commits were squashed into one first, so the
branch history names no private project. Details settled on the way:

- A project kind the target revision does not support is a refusal (exit
  1, the message names the kind and the revision, and says when the
  revision predates kinds); malformed `kinds` in a manifest, or `kinds` on
  an entry other than a skill, is a broken manifest (exit 2), whether or
  not the project names a kind.
- The shared rules gained a generic "Project kinds" paragraph, and their
  "Descriptors" now says only that `isabelle-tooling.conf` has the keys the
  tooling defines. `model_kind` itself is described in the tooling's own
  part of the contracts, so agent-board's copy changed only in stage A.
- `skills list` prints `NAME [code, theory]: DESCRIPTION`, adds `; not
  installed here` in a project whose kind leaves a skill out, and ends its
  header with `, for a theory project`; a revision without kinds prints
  as before. Doctor's roots line starts `A theory project;`.
- The theory descriptor template carries a comment on `model_kind`; the
  code templates are unchanged, byte for byte.
- The descriptor tests went into `tests/descriptor_test.sh`, which tests
  `common.sh`'s parser, including a loop that runs both parsers on every
  descriptor of the test; `tests/common_test.sh` tests other helpers and
  is unchanged.
- The migrations and "Replacing an uncommitted code scaffold" are
  documented in the README's new "Project kinds" section, which the setup
  skill points to.
- `init --kind theory` without `--revision` pins `stable`, so it fails,
  naming the missing `templates/theory/`, until `stable` has moved.


**Validation**, the same day, at tooling `dcb7809` and agent-board
`3b2ba94`, in the fixture environment of the delivery plan's step 4 (a
detached runtime worktree with its own Isabelle user home, fresh host
configuration roots), with Claude Code 2.1.289 (claude-opus-5-5, auto
permission mode) and Codex CLI 0.160.0 (gpt-6-astra at medium effort,
workspace-write with automatic review). Everything passed:

- Between real revisions, 39 checks with the previous `stable` `f013ec6`.
  Its runtime updated a code project to the candidate: five skills, the
  new block, no `model_kind`, and doctor passed once the clone moved. From
  the candidate runtime, a code project moved back to `f013ec6`, a theory
  project's `update f013ec6` was refused naming the kind and the revision
  and changed nothing, `init --revision f013ec6` rendered a code project,
  and `init --kind theory --revision f013ec6` was refused. A code render at
  the candidate is byte-identical to one at `f013ec6`, the pin aside. With
  the runtime back at `f013ec6`, `sync --check`, `sync`, `update`, doctor
  and `scripts/ic2.sh start` on the theory project each stopped with
  `unknown key: model_kind`, and the project was unchanged.
- The mechanical checks: 76 on the bare repository and 75 on the
  stellar-core clone, all but the check of `init` at the previous
  `stable`, whose doctors fail while the runtimes are at the candidates.
- The shared module is byte-identical at both candidates.
- The theory host fixture, a fresh repository with `init --kind theory`,
  on both hosts. Discovery showed exactly the two project skills and the
  worker profile; Claude Code listed the `iq` server (not connected, with
  no jEdit running), and Codex, as in earlier discovery runs, listed no
  MCP server without a live I/Q. Asked for a recursive function and a
  lemma about it through ic2, each agent read only `isabelle-setup` and
  `isabelle-proving`, wrote no conventions block and no `Word` import,
  built the session and committed. Asked, in a fresh session, for a
  locale with two assumptions and a lemma in it, each added
  `lemma bounded_queue_model: "bounded_queue 1 0" by unfold_locales
  simp_all` unprompted, and Claude Code named the new rule in its report.
  Doctor passed and the session built in both projects afterwards.

Not rerun: the behavioural scenarios, link mode on a host and the worker
smoke proof. The worker profiles, the board skill and the link code did
not change; the instruction block and the setup and proving skills did,
and the theory host fixture exercised them on both hosts.
