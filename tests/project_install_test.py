#!/usr/bin/env python3
"""bin/isabelle-tooling and its installer, scripts/project_files.py.

ToolingTests drive the command line: skill inspection, the project
operations (init, sync, update, remove and sync --check) and doctor's
project and host checks. Each test runs a scratch runtime checkout built
from this working tree (without the AutoCorrode submodule): `stable` at its
first commit, `next` one commit later with a supporting reference file in a
skill and an edited skill, `before-kinds`, off `stable`, with the manifest
and templates of a revision from before project kinds, and `extras`, off
`stable`, whose manifest adds an owned array element and an executable
file. Projects are disposable, with isolated Git and host configuration.

They cover the installer cases in docs/validation.md and the installer's
rules in depth: the session scaffold; owned JSON members and array
elements, TOML and Markdown blocks merged into project files and removed
again; executable files; root AGENTS.md and CLAUDE.md in each combination;
the Claude Code skill aliases or a shared skills directory; unmanaged
collisions; edited managed files, entries and blocks, and files added to a
managed skill directory; preflight against the index (unstaged, untracked
and ignored paths); skill parents that are symlinks out of the checkout;
malformed descriptors, missing pinned commits and revisions without a
manifest; the pin that only update moves; adoption of a descriptor without
an inventory; link mode; project kinds and Isabelle release switches;
--project-root from another directory; the installer lock; publication
across filesystems; an injected failure after each publication step of
init, update and remove, whose printed commands restore the tree and the
index; and a read-only doctor.

KindTests check how manifest kinds select skills, through a fake spec on a
scratch runtime; KeyValueTests check the descriptor's key=value lines.
Both call scripts/project_files.py directly.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import tomllib
import unittest

SOURCE = Path(__file__).resolve().parents[1]
MODULE_DIR = SOURCE / 'scripts'
SKILLS = ('isabelle-setup', 'isabelle-modeling', 'isabelle-proving', 'isabelle-differential',
          'isabelle-assurance')
THEORY_SKILLS = ('isabelle-proving', 'isabelle-setup')
CODE_ONLY = ('isabelle-assurance', 'isabelle-differential', 'isabelle-modeling')
DRIVER = '''
import sys
sys.path.insert(0, sys.argv[1])
import project_files
import isabelle_tooling
limit = int(sys.argv[2])
def fail(step, op):
    if step == limit:
        raise OSError(f'injected failure after step {step}')
project_files.after_step = fail
sys.exit(isabelle_tooling.main(sys.argv[3:]))
'''


def snapshot(root, skip_git=True):
    found = {}
    for directory, dirs, files in os.walk(root):
        if skip_git and '.git' in dirs and Path(directory) == Path(root):
            dirs.remove('.git')
        for name in dirs + files:
            path = Path(directory) / name
            info = os.lstat(path)
            rel = str(path.relative_to(root))
            if path.is_symlink():
                found[rel] = ('link', os.readlink(path))
            elif path.is_dir():
                found[rel] = ('dir', oct(info.st_mode))
            else:
                found[rel] = ('file', hashlib.sha256(path.read_bytes()).hexdigest(), oct(info.st_mode),
                              info.st_mtime_ns)
    return found


class ToolingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='tooling-project-')
        cls.base = Path(cls.tmp.name)
        home = cls.base / 'home'
        (home / '.claude').mkdir(parents=True)
        (home / '.codex').mkdir()
        bindir = cls.base / 'bin'
        bindir.mkdir()
        shutil.copy(SOURCE / 'tests/fixtures/isabelle', bindir / 'isabelle')
        cls.runtime = cls.base / 'runtime'
        cls.env = {k: v for k, v in os.environ.items()
                   if not k.startswith(('GIT_', 'ISABELLE_', 'CLAUDE_', 'CODEX_'))}
        cls.env.update(HOME=str(home), GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                       GIT_TERMINAL_PROMPT='0', GIT_AUTHOR_NAME='test', GIT_AUTHOR_EMAIL='test@example.invalid',
                       GIT_COMMITTER_NAME='test', GIT_COMMITTER_EMAIL='test@example.invalid',
                       PYTHONDONTWRITEBYTECODE='1', PATH=f"{bindir}:{os.environ['PATH']}",
                       ISABELLE_TOOLING_ROOT=str(cls.runtime), MOCK_ISABELLE_STATE_DIR=str(cls.base / 'mock'),
                       XDG_CONFIG_HOME=str(home / '.config'))
        cls.git_in(cls.base, 'init', '-q', '-b', 'main', str(cls.runtime))
        listed = subprocess.run(['git', '-C', str(SOURCE), 'ls-files', '-z', '-co', '--exclude-standard'],
                                capture_output=True, check=True).stdout.decode().split('\0')
        for rel in filter(None, listed):
            source, target = SOURCE / rel, cls.runtime / rel
            if rel == 'AutoCorrode' or rel.startswith('AutoCorrode/') or not os.path.lexists(source) or \
                    (source.is_dir() and not source.is_symlink()):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_symlink():
                os.symlink(os.readlink(source), target)
            else:
                shutil.copy2(source, target)
        cls.git_in(cls.runtime, 'add', '-A')
        cls.git_in(cls.runtime, 'commit', '-qm', 'scratch runtime')
        cls.rev1 = cls.git_in(cls.runtime, 'rev-parse', 'HEAD').strip()
        cls.git_in(cls.runtime, 'branch', 'stable')
        cls.git_in(cls.runtime, 'checkout', '-q', '-b', 'next')
        reference = cls.runtime / 'extension/skills/isabelle-proving/references/next-only.md'
        reference.parent.mkdir(parents=True)
        reference.write_text('A supporting reference file only the next revision has.\n')
        skill = cls.runtime / 'extension/skills/isabelle-setup/SKILL.md'
        skill.write_text(skill.read_text() + '\nA line only the next revision has.\n')
        cls.git_in(cls.runtime, 'add', '-A')
        cls.git_in(cls.runtime, 'commit', '-qm', 'next')
        cls.rev2 = cls.git_in(cls.runtime, 'rev-parse', 'HEAD').strip()
        cls.git_in(cls.runtime, 'checkout', '-q', '-b', 'before-kinds', 'stable')
        manifest_path = cls.runtime / 'extension/project/manifest.json'
        manifest = json.loads(manifest_path.read_text())
        del manifest['kinds']
        for skill in manifest['skills']:
            skill.pop('kinds', None)
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        cls.git_in(cls.runtime, 'rm', '-rq', 'templates/theory')
        cls.git_in(cls.runtime, 'commit', '-qam', 'before kinds')
        cls.rev0 = cls.git_in(cls.runtime, 'rev-parse', 'HEAD').strip()
        # extras, off stable: an owned array element and an executable file, which the real manifest lacks.
        cls.git_in(cls.runtime, 'checkout', '-q', '-b', 'extras', 'stable')
        manifest = json.loads(manifest_path.read_text())
        manifest['files'].append(dict(path='bin/session-hook.sh', source='extras/session-hook.sh', executable=True))
        manifest['json_entries'].append(dict(file='.claude/settings.json', pointer='/hooks/SessionStart',
                                             element=True, marker='bin/session-hook.sh',
                                             source='extras/session-hook.json'))
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        (cls.runtime / 'extras').mkdir()
        (cls.runtime / 'extras/session-hook.sh').write_text('#!/bin/sh\nexit 0\n')
        (cls.runtime / 'extras/session-hook.json').write_text(json.dumps(
            {'hooks': [{'type': 'command', 'command': '"$CLAUDE_PROJECT_DIR/bin/session-hook.sh"'}]}))
        cls.git_in(cls.runtime, 'add', '-A')
        cls.git_in(cls.runtime, 'commit', '-qm', 'extras')
        cls.git_in(cls.runtime, 'checkout', '-q', 'main')
        cls.cli = cls.runtime / 'bin/isabelle-tooling'

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def git_in(cls, cwd, *args):
        return subprocess.run(['git', *args], cwd=cwd, env=cls.env, capture_output=True, text=True,
                              check=True).stdout

    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix='project-', dir=self.base))
        self.project = self.work / 'demo'
        self.project.mkdir()
        self.git('init', '-q', '-b', 'main')

    def tearDown(self):
        shutil.rmtree(self.work)
        if self.git_in(self.runtime, 'rev-parse', 'HEAD').strip() != self.rev1:
            self.git_in(self.runtime, 'checkout', '-q', 'main')
        self.git_in(self.runtime, 'checkout', '-q', '--', '.')

    def git(self, *args, cwd=None):
        return self.git_in(cwd or self.project, *args)

    def commit_all(self):
        self.git('add', '-A')
        self.git('commit', '-qm', 'state', '--allow-empty')

    def fresh_project(self, name):
        """Point the helpers at a new empty repository NAME beside the first."""
        self.project = self.work / name
        self.project.mkdir()
        self.git('init', '-q', '-b', 'main')

    def it(self, *args, code=0, cwd=None, env=None):
        result = subprocess.run([str(self.cli), *args], cwd=cwd or self.project, env=env or self.env,
                                capture_output=True, timeout=120)
        result.stdout, result.err = result.stdout, result.stderr.decode(errors='replace')
        result.out = result.stdout.decode(errors='replace')
        if code is not None:
            self.assertEqual(result.returncode, code, result.out + result.err)
        return result

    def check(self, code=0):
        return self.it('sync', '--check', code=code).out

    def read(self, rel):
        return (self.project / rel).read_text()

    def state(self):
        """The whole working tree and the Git status, to show that a refused operation changed nothing."""
        return snapshot(self.project), self.git('status', '--porcelain', '--ignored', '--untracked-files=all')

    def blob(self, rev, path):
        return subprocess.run(['git', '-C', str(self.runtime), 'cat-file', 'blob', f'{rev}:{path}'],
                              capture_output=True, check=True).stdout

    # --- init ---------------------------------------------------------------------------

    def test_init_installs_the_complete_integration_at_stable(self):
        out = self.it('init', '--session', 'Demo').out
        self.assertIn(f'isabelle-tooling {self.rev1} is installed (copy mode)', out)
        changed = out.split('Changed:\n')[1].split('Review them')[0].split()
        self.assertEqual(changed[-2:], ['.isabelle-tooling/inventory.json', 'isabelle-tooling.conf'])
        self.assertLess(changed.index('formal/Demo/Demo.thy'), changed.index('.agents/skills/isabelle-setup/SKILL.md'))
        descriptor = self.read('isabelle-tooling.conf')
        self.assertIn(f'tooling_revision={self.rev1}\n', descriptor)
        self.assertIn('build_session=Demo\n', descriptor)
        self.assertNotIn('model_kind', descriptor)
        for rel in ('formal/ROOTS', 'formal/AGENTS.md', 'formal/README.md', 'formal/Demo/ROOT', 'formal/Demo/Demo.thy'):
            self.assertTrue((self.project / rel).is_file(), rel)
            self.assertNotRegex(self.read(rel), '@[A-Z_]+@')
        self.assertEqual(os.readlink(self.project / 'formal/CLAUDE.md'), 'AGENTS.md')
        for name in SKILLS:
            self.assertEqual((self.project / f'.agents/skills/{name}/SKILL.md').read_bytes(),
                             self.blob(self.rev1, f'extension/skills/{name}/SKILL.md'))
            self.assertEqual(os.readlink(self.project / f'.claude/skills/{name}'), f'../../.agents/skills/{name}')
        self.assertEqual((self.project / '.claude/agents/ic2-prover.md').read_bytes(),
                         self.blob(self.rev1, 'extension/agents/ic2-prover.md'))
        self.assertEqual((self.project / '.codex/agents/ic2_prover.toml').read_bytes(),
                         self.blob(self.rev1, 'extension/agents/ic2_prover.toml'))
        self.assertEqual(json.loads(self.read('.mcp.json')), {'mcpServers': {'iq': {
            'command': '${ISABELLE_TOOLING_ROOT}/extension/bin/iq-bridge.sh', 'args': [],
            'env': {'IQ_MCP_BRIDGE_PORT': '8765'}}}})
        codex = self.read('.codex/config.toml')
        self.assertTrue(codex.startswith('# BEGIN isabelle-tooling\n# Managed by isabelle-tooling'))
        self.assertTrue(codex.endswith('IQ_MCP_BRIDGE_PORT = "8765"\n# END isabelle-tooling\n'))
        agents = self.read('AGENTS.md')
        self.assertIn('under `formal/`; read\n`formal/AGENTS.md`', agents)
        self.assertEqual(os.readlink(self.project / 'CLAUDE.md'), 'AGENTS.md')
        inventory = json.loads(self.read('.isabelle-tooling/inventory.json'))
        self.assertEqual(inventory['revision'], self.rev1)
        self.assertEqual(inventory['directories'], [f'.agents/skills/{name}' for name in sorted(SKILLS)])
        self.assertEqual([(b['file'], b['syntax']) for b in inventory['blocks']],
                         [('.codex/config.toml', 'toml'), ('AGENTS.md', 'markdown')])
        # The session scaffold belongs to the project; the inventory never records itself.
        self.assertFalse([rel for rel in inventory['files'] if rel.startswith(('formal/', '.isabelle-tooling/'))])
        self.check()
        for text in [self.read(p) for p in ('.mcp.json', '.codex/config.toml', 'AGENTS.md', 'isabelle-tooling.conf',
                                            '.isabelle-tooling/inventory.json')]:
            self.assertNotIn(str(self.base), text)  # no machine paths in committed files
        self.assertEqual(self.git('diff', '--cached', '--name-only'), '')  # the installer stages nothing
        self.assertIn('already exists', self.it('init', '--session', 'Demo', code=1).err)
        self.commit_all()
        self.assertIn('Nothing changed', self.it('sync').out)
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_layout_c_puts_the_block_in_the_scaffold_agents_md(self):
        (self.project / 'X').mkdir()
        (self.project / 'X/code.c').write_text('int x;\n')
        self.commit_all()
        self.it('init', '--session', 'Model', '--formal-rel', '.', '--source-rel', 'X', '--project-name', 'The X')
        agents = self.read('AGENTS.md')
        self.assertTrue(agents.startswith('# Agent instructions for the formal model of The X'))
        self.assertIn('<!-- BEGIN isabelle-tooling -->', agents)
        self.assertEqual(os.readlink(self.project / 'CLAUDE.md'), 'AGENTS.md')
        self.assertIn('source_rel=X\n', self.read('isabelle-tooling.conf'))
        self.check()

    def test_init_rejects_bad_options_and_existing_session_files(self):
        self.assertIn('session name', self.it('init', '--session', 'bad name', code=2).err)
        self.assertIn("'..' component", self.it('init', '--session', 'Ok', '--formal-rel', '../up', code=2).err)
        (self.project / 'formal').mkdir()
        (self.project / 'formal/ROOTS').write_text('Mine\n')
        self.commit_all()
        self.assertIn('collision: formal/ROOTS exists', self.it('init', '--session', 'Ok', code=1).err)
        self.assertFalse((self.project / 'isabelle-tooling.conf').exists())

    # --- the command interface ------------------------------------------------------------

    def test_skills_show_and_list_read_the_pinned_object(self):
        outside = self.it('skills', 'show', 'isabelle-setup', cwd=self.work)
        self.assertEqual(outside.stdout, self.blob(self.rev1, 'extension/skills/isabelle-setup/SKILL.md'))
        self.assertIn(f'at {self.rev1} (stable)', outside.err)
        # Outside a project, every release's skills, marked when only one release installs them.
        listed = self.it('skills', 'list', cwd=self.work).out.splitlines()
        self.assertEqual([line.split(' [')[0] for line in listed[1:]], [*SKILLS, 'isabelle-pide-ai'])
        self.assertIn('isabelle-setup [code, theory; Isabelle2025-2 only]: ', listed[1])
        self.assertIn('isabelle-modeling [code]: ', listed[2])
        self.assertIn('isabelle-pide-ai [code, theory; Isabelle2026 only]: ', listed[-1])
        self.assertEqual(self.it('skills', 'show', 'isabelle-pide-ai', cwd=self.work).stdout,
                         self.blob(self.rev1, 'extension/skills/isabelle-pide-ai/SKILL.md'))
        self.it('init', '--session', 'Demo', '--revision', 'next')
        # The runtime's HEAD and working tree differ from the pin; neither matters.
        (self.runtime / 'extension/skills/isabelle-setup/SKILL.md').write_text('uncommitted edit\n')
        shown = self.it('skills', 'show', 'isabelle-setup', cwd=self.project / 'formal')
        self.assertEqual(shown.stdout, self.blob(self.rev2, 'extension/skills/isabelle-setup/SKILL.md'))
        self.assertIn(f'at {self.rev2} (pinned by {self.project}/isabelle-tooling.conf)', shown.err)
        listed = self.it('skills', 'list').out.splitlines()
        self.assertEqual(listed[0], f'isabelle-tooling skills at {self.rev2} (pinned by '
                                    f'{self.project}/isabelle-tooling.conf), for a code project')
        self.assertEqual([line.split(' [')[0] for line in listed[1:]], list(SKILLS))
        self.assertIn('isabelle-setup [code, theory]: Set up and check the Isabelle', listed[1])
        # A revision from before kinds lists the skills as it always did.
        old = self.work / 'old'
        old.mkdir()
        self.git('init', '-q', cwd=old)
        self.it('init', '--session', 'Old', '--revision', 'before-kinds', cwd=old)
        listed = self.it('skills', 'list', cwd=old).out.splitlines()
        self.assertTrue(listed[0].endswith('isabelle-tooling.conf)'), listed[0])
        self.assertEqual([line.split(':')[0] for line in listed[1:]], list(SKILLS))
        unknown = self.it('skills', 'show', 'no-such-skill', code=1)
        self.assertEqual((unknown.stdout, 'skills list' in unknown.err), (b'', True))
        # No prover is needed to read.
        env = dict(self.env, PATH='/usr/bin:/bin')
        self.assertEqual(self.it('skills', 'show', 'isabelle-proving', env=env).stdout,
                         self.blob(self.rev2, 'extension/skills/isabelle-proving/SKILL.md'))

    def test_skills_refuse_a_malformed_descriptor_or_missing_object(self):
        (self.project / 'isabelle-tooling.conf').write_text('format_version=1\nnot a line\n')
        self.assertIn('expected key=value', self.it('skills', 'list', code=1).err)
        (self.project / 'isabelle-tooling.conf').write_bytes(b'format_version=1\r\n')
        self.assertIn('isabelle-tooling.conf:1: carriage return', self.it('skills', 'list', code=1).err)
        descriptor = self.blob(self.rev1, 'templates/isabelle-tooling.conf').decode()
        for key, value in dict(SOURCE_REL='.', FORMAL_REL='formal', SESSION='Demo', MAX_HEAP='2G',
                               ISABELLE_VERSION='Isabelle2025-2', TOOLING_REVISION='0' * 40).items():
            descriptor = descriptor.replace(f'@{key}@', value)
        (self.project / 'isabelle-tooling.conf').write_text(descriptor)
        self.assertIn('is missing from', self.it('skills', 'show', 'isabelle-setup', code=2).err)
        (self.project / 'isabelle-tooling.conf').write_text(descriptor.replace('0' * 40, 'stable'))
        self.assertIn('full 40-hex commit', self.it('skills', 'show', 'isabelle-setup', code=1).err)

    def test_project_root_from_another_directory(self):
        elsewhere = self.work / 'elsewhere'
        elsewhere.mkdir()
        root = str(self.project)
        self.it('init', '--session', 'Demo', '--project-root', root, cwd=elsewhere)
        self.assertIn('[mcp_servers.iq]', self.read('.codex/config.toml'))
        self.assertEqual(os.listdir(elsewhere), [])
        self.commit_all()
        self.it('sync', '--check', '--project-root', root, cwd=elsewhere)
        self.assertIn('Nothing changed', self.it('sync', '--project-root', root, cwd=elsewhere).out)
        self.it('remove', '--project-root', root, cwd=elsewhere)
        self.assertFalse((self.project / 'isabelle-tooling.conf').exists())

    # --- shared files ------------------------------------------------------------------------

    def test_isabelle2026_opt_in_and_rollback_preserve_project_files(self):
        self.it('init', '--session', 'Demo', '--kind', 'theory', '--isabelle-version', 'Isabelle2026')
        self.assertIn('isabelle_version=Isabelle2026\n', self.read('isabelle-tooling.conf'))
        self.assertEqual(set(json.loads(self.read('.mcp.json'))['mcpServers']), {'isabelle-pide-mcp'})
        self.assertEqual(set(tomllib.loads(self.read('.codex/config.toml'))['mcp_servers']), {'isabelle-pide-mcp'})
        self.assertEqual(self.skill_dirs(), (('isabelle-pide-ai',), ('isabelle-pide-ai',)))
        self.assertFalse((self.project / '.codex/agents/ic2_prover.toml').exists())
        self.assertIn('isabelle-pide-ai', self.it('skills', 'list').out)
        self.assertIn('isabelle-pide-mcp', self.read('AGENTS.md'))
        original_theory = self.read('formal/Demo/Demo.thy')
        self.it('sync')
        self.check()
        report = self.doctor(env=dict(self.env, MOCK_ISABELLE_VERSION='Isabelle2026'))
        self.assertIn('setup-pide-ai.sh', report)
        self.assertNotIn('I/Q token', report)
        self.assertNotIn('ic2 component', report)
        self.commit_all()
        self.it('update', 'stable', '--isabelle-version', 'Isabelle2025-2')
        self.assertEqual(set(json.loads(self.read('.mcp.json'))['mcpServers']), {'iq'})
        self.assertEqual(self.skill_dirs(), (THEORY_SKILLS, THEORY_SKILLS))
        self.assertEqual(self.read('formal/Demo/Demo.thy'), original_theory)
        self.commit_all()
        self.it('update', 'stable', '--isabelle-version', 'Isabelle2026')
        self.check()
        self.commit_all()
        self.it('remove')
        self.assertFalse((self.project / '.mcp.json').exists())
        self.assertEqual(self.read('formal/Demo/Demo.thy'), original_theory)

    def test_mcp_and_codex_configuration_are_merged_and_restored(self):
        mcp = {'mcpServers': {'other': {'command': 'other-server'}}, 'extra': [1, 2]}
        (self.project / '.mcp.json').write_text(json.dumps(mcp))
        (self.project / '.codex').mkdir()
        codex = 'model = "x"   # keep this comment and spacing\n\n[mcp_servers.other]\ncommand = "o"\n'
        (self.project / '.codex/config.toml').write_text(codex)
        self.commit_all()
        self.it('init', '--session', 'Demo')
        merged = json.loads(self.read('.mcp.json'))
        self.assertEqual(list(merged['mcpServers']), ['other', 'iq'])
        self.assertEqual(merged['extra'], [1, 2])
        text = self.read('.codex/config.toml')
        self.assertTrue(text.startswith(codex + '\n# BEGIN isabelle-tooling\n'))
        self.check()
        self.commit_all()
        (self.project / '.codex/config.toml').write_text(text + 'stray = 1\n')
        self.git('add', '-A')
        self.assertIn('keys after the block attach to its last table', self.check(1))
        self.assertIn('keys after the block', self.it('sync', code=1).err)
        self.git('checkout', 'HEAD', '--', '.')
        self.it('remove')
        self.assertEqual(json.loads(self.read('.mcp.json')), mcp)
        self.assertEqual(self.read('.codex/config.toml'), codex)
        self.assertTrue((self.project / 'formal/Demo/Demo.thy').is_file())  # the session stays

    def test_unmanaged_iq_declarations_collide(self):
        (self.project / '.codex').mkdir()
        (self.project / '.codex/config.toml').write_text('[mcp_servers.iq]\ncommand = "mine"\n')
        self.commit_all()
        self.assertIn('defines [mcp_servers.iq] outside the isabelle-tooling block',
                      self.it('init', '--session', 'Demo', code=1).err)
        (self.project / '.codex/config.toml').unlink()
        (self.project / '.mcp.json').write_text('{"mcpServers": {"iq": {"command": "mine"}}}\n')
        self.commit_all()
        self.assertIn('collision: .mcp.json /mcpServers/iq', self.it('init', '--session', 'Demo', code=1).err)

    def test_edited_owned_entries_refuse(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        data = json.loads(self.read('.mcp.json'))
        data['mcpServers']['iq']['args'] = ['--changed']
        (self.project / '.mcp.json').write_text(json.dumps(data))
        self.git('add', '-A')
        self.assertIn('edited owned entry: .mcp.json /mcpServers/iq', self.it('update', 'next', code=1).err)
        self.git('checkout', 'HEAD', '--', '.')
        (self.project / '.codex/config.toml').write_text(self.read('.codex/config.toml').replace('8765', '9999'))
        self.git('add', '-A')
        self.assertIn('edited owned block: .codex/config.toml', self.it('remove', code=1).err)

    def test_unmanaged_collisions_and_edited_skills_and_blocks_refuse(self):
        skill = self.project / '.agents/skills/isabelle-setup/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('our own setup notes\n')
        (self.project / '.claude/agents').mkdir(parents=True)
        (self.project / '.claude/agents/ic2-prover.md').write_text('our own worker\n')
        self.commit_all()
        before = self.state()
        err = self.it('init', '--session', 'Demo', code=1).err
        self.assertIn('nothing was changed', err)
        self.assertIn('collision: .agents/skills/isabelle-setup exists and is not managed by isabelle-tooling', err)
        self.assertIn('collision: .claude/agents/ic2-prover.md exists and is not managed by isabelle-tooling', err)
        self.assertEqual(self.state(), before)
        self.git('rm', '-rq', '.agents', '.claude')
        self.it('init', '--session', 'Demo')
        self.commit_all()
        # An edited skill file: sync refuses, and check reports it.
        skill.write_text(skill.read_text() + 'edited\n')
        self.git('add', '-A')
        self.assertIn('edited managed file: .agents/skills/isabelle-setup/SKILL.md', self.it('sync', code=1).err)
        self.assertIn('edited managed file: .agents/skills/isabelle-setup/SKILL.md', self.check(1))
        self.git('checkout', 'HEAD', '--', '.')
        # A file added to a managed skill directory.
        stray = skill.parent / 'stray.md'
        stray.write_text('stray\n')
        self.git('add', '-A')
        self.assertIn('unmanaged file in the managed directory .agents/skills/isabelle-setup: '
                      '.agents/skills/isabelle-setup/stray.md', self.it('sync', code=1).err)
        self.git('rm', '-q', '--cached', '.agents/skills/isabelle-setup/stray.md')
        stray.unlink()
        # An edited root instruction block.
        (self.project / 'AGENTS.md').write_text(self.read('AGENTS.md').replace('read\n', 'always read\n'))
        self.git('add', '-A')
        self.assertIn('edited owned block: AGENTS.md', self.it('update', 'next', code=1).err)
        self.assertIn('edited owned block: AGENTS.md', self.check(1))
        self.git('checkout', 'HEAD', '--', '.')
        self.check()

    def test_root_instruction_files(self):
        # Distinct regular AGENTS.md and CLAUDE.md: each gets the block, and remove gives both back.
        (self.project / 'AGENTS.md').write_text('# Project\n\nOur rules.\n')
        (self.project / 'CLAUDE.md').write_text('Claude-only notes.\n')
        self.commit_all()
        self.it('init', '--session', 'Demo')
        agents, claude = self.read('AGENTS.md'), self.read('CLAUDE.md')
        self.assertTrue(agents.startswith('# Project\n\nOur rules.\n\n<!-- BEGIN isabelle-tooling -->\n'), agents)
        self.assertTrue(claude.startswith('Claude-only notes.\n\n<!-- BEGIN isabelle-tooling -->\n'), claude)
        self.assertEqual(agents.split('\n\n', 2)[2], claude.split('\n\n', 1)[1])
        self.assertFalse(os.path.islink(self.project / 'CLAUDE.md'))
        blocks = json.loads(self.read('.isabelle-tooling/inventory.json'))['blocks']
        self.assertEqual([b['file'] for b in blocks if b['syntax'] == 'markdown'], ['AGENTS.md', 'CLAUDE.md'])
        self.check()
        self.commit_all()
        self.it('remove')
        self.assertEqual(self.read('AGENTS.md'), '# Project\n\nOur rules.\n')
        self.assertEqual(self.read('CLAUDE.md'), 'Claude-only notes.\n')
        for gone in ('isabelle-tooling.conf', '.isabelle-tooling', '.agents', '.claude', '.codex', '.mcp.json'):
            self.assertFalse(os.path.lexists(self.project / gone), gone)
        # CLAUDE.md alone: it gets the block, and a regular AGENTS.md is created beside it.
        self.fresh_project('claude-only')
        (self.project / 'CLAUDE.md').write_text('only Claude\n')
        self.commit_all()
        self.it('init', '--session', 'Demo')
        self.assertTrue(self.read('CLAUDE.md').startswith('only Claude\n\n<!-- BEGIN isabelle-tooling -->\n'))
        self.assertTrue(self.read('AGENTS.md').startswith('<!-- BEGIN isabelle-tooling -->\n'))
        self.assertFalse(os.path.islink(self.project / 'AGENTS.md'))
        self.check()
        # AGENTS.md alone: it gets the block and a CLAUDE.md symlink, which remove leaves in place.
        self.fresh_project('agents-only')
        (self.project / 'AGENTS.md').write_text('rules\n')
        self.commit_all()
        self.it('init', '--session', 'Demo')
        self.assertEqual(os.readlink(self.project / 'CLAUDE.md'), 'AGENTS.md')
        self.check()
        err = self.it('remove', code=1).err  # the new files are not staged yet
        self.assertIn('nothing was changed', err)
        self.assertIn('.isabelle-tooling/inventory.json is untracked', err)
        self.commit_all()
        self.it('remove')
        self.assertEqual(self.read('AGENTS.md'), 'rules\n')
        self.assertEqual(os.readlink(self.project / 'CLAUDE.md'), 'AGENTS.md')

    def test_owned_array_elements_and_executable_files(self):
        self.git_in(self.runtime, 'checkout', '-q', 'extras')
        mine = json.loads((self.runtime / 'extras/session-hook.json').read_text())
        ours = {'hooks': {'SessionStart': [{'hooks': [{'type': 'command', 'command': 'our-hook'}]}]}, 'model': 'x'}
        original = json.dumps(ours, indent=2) + '\n'
        settings, hook = self.project / '.claude/settings.json', self.project / 'bin/session-hook.sh'
        settings.parent.mkdir()
        settings.write_text(original)
        self.commit_all()
        # The element joins the project's own array, and the file is executable.
        self.it('init', '--session', 'Demo', '--revision', 'extras')
        data = json.loads(settings.read_text())
        self.assertEqual(data['hooks']['SessionStart'], ours['hooks']['SessionStart'] + [mine])
        self.assertEqual(data['model'], 'x')
        self.assertTrue(os.access(hook, os.X_OK))
        self.check()
        self.commit_all()
        # An edited, a missing and a duplicated element; a cleared executable bit.
        entry = '.claude/settings.json /hooks/SessionStart'
        duplicated = '2 elements of /hooks/SessionStart carry bin/session-hook.sh'
        for change, says in ((lambda a: a[-1].update(timeout=5), f'edited owned entry: {entry}'),
                             (lambda a: a.pop(), f'missing owned entry: {entry}'),
                             (lambda a: a.append(dict(a[-1])), duplicated)):
            changed = json.loads(settings.read_text())
            change(changed['hooks']['SessionStart'])
            settings.write_text(json.dumps(changed))
            self.git('add', '-A')
            with self.subTest(says=says):
                self.assertIn(says, self.check(1))
                self.assertIn(says, self.it('sync', code=1).err)
            self.git('checkout', 'HEAD', '--', '.')
        hook.chmod(0o644)
        self.git('add', '-A')
        self.assertIn('edited managed file: bin/session-hook.sh', self.check(1))
        self.git('checkout', 'HEAD', '--', '.')
        self.check()
        # Remove gives the project's own array back, byte for byte.
        self.it('remove')
        self.assertEqual(settings.read_text(), original)
        self.assertFalse(os.path.lexists(self.project / 'bin'))
        # Without a settings file: an unmanaged element carrying the marker collides; init creates the file,
        # and remove deletes it again.
        self.fresh_project('no-settings')
        settings = self.project / '.claude/settings.json'
        settings.parent.mkdir()
        settings.write_text(json.dumps({'hooks': {'SessionStart': [mine]}}))
        self.commit_all()
        self.assertIn('collision: .claude/settings.json /hooks/SessionStart already has an entry not managed by',
                      self.it('init', '--session', 'Demo', '--revision', 'extras', code=1).err)
        self.git('rm', '-q', '.claude/settings.json')
        self.it('init', '--session', 'Demo', '--revision', 'extras')
        self.assertEqual(json.loads(settings.read_text()), {'hooks': {'SessionStart': [mine]}})
        self.check()
        self.commit_all()
        self.it('remove')
        self.assertFalse(os.path.lexists(settings))

    # --- preflight ----------------------------------------------------------------------------

    def test_preflight_uses_the_index(self):
        (self.project / 'AGENTS.md').write_text('rules\n')
        self.commit_all()
        (self.project / '.mcp.json').write_text('{}\n')
        before = self.state()
        err = self.it('init', '--session', 'Demo', code=1).err
        self.assertIn('.mcp.json is untracked; stage or remove it first', err)
        self.assertIn('nothing was changed', err)
        self.assertEqual(self.state(), before)
        (self.project / '.mcp.json').unlink()
        (self.project / '.gitignore').write_text('.isabelle-tooling/\n')
        self.commit_all()
        before = self.state()
        err = self.it('init', '--session', 'Demo', code=1).err
        self.assertIn('.isabelle-tooling/inventory.json is ignored by Git', err)
        self.assertEqual(self.state(), before)
        self.git('rm', '-q', '.gitignore')
        (self.project / 'AGENTS.md').write_text('rules, edited\n')
        self.assertIn('AGENTS.md has unstaged changes', self.it('init', '--session', 'Demo', code=1).err)
        self.git('add', 'AGENTS.md')  # staged changes are accepted
        self.it('init', '--session', 'Demo')
        self.assertTrue(self.read('AGENTS.md').startswith('rules, edited\n\n<!-- BEGIN isabelle-tooling -->\n'))
        self.check()

    def test_a_skill_parent_symlinked_outside_the_checkout_is_refused(self):
        outside = self.work / 'elsewhere'
        outside.mkdir()
        for parent in ('.agents', '.claude/skills'):
            link = self.project / parent
            link.parent.mkdir(exist_ok=True)
            os.symlink(outside, link)
            self.commit_all()
            err = self.it('init', '--session', 'Demo', code=1).err
            self.assertIn(f'{parent} is a symlink resolving outside the checkout', err)
            self.assertEqual(os.listdir(outside), [])
            self.assertFalse((self.project / 'isabelle-tooling.conf').exists())
            self.git('rm', '-q', parent)

    # --- revisions and adoption --------------------------------------------------------------

    def test_sync_keeps_the_pin_and_update_installs_whole_skill_directories(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        self.git_in(self.runtime, 'checkout', '-q', 'next')
        self.assertIn('Nothing changed', self.it('sync').out)
        self.assertIn(f'tooling_revision={self.rev1}\n', self.read('isabelle-tooling.conf'))
        self.assertIn('is at', self.check(1))
        out = self.it('update', 'next').out
        self.assertIn('.agents/skills/isabelle-proving/references/next-only.md', out)
        self.assertTrue((self.project / '.claude/skills/isabelle-proving/references/next-only.md').is_file())
        self.assertIn(f'tooling_revision={self.rev2}\n', self.read('isabelle-tooling.conf'))
        self.check()
        self.commit_all()
        self.git_in(self.runtime, 'checkout', '-q', 'main')
        self.it('update', 'stable')
        self.assertFalse((self.project / '.agents/skills/isabelle-proving/references').exists())
        self.check()

    def test_malformed_descriptors_and_missing_pins_refuse(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        descriptor = self.project / 'isabelle-tooling.conf'
        good = descriptor.read_text()
        before = snapshot(self.project)
        for text, says, code in ((good.replace(self.rev1, 'abc'), 'tooling_revision must be a full 40-hex commit', 1),
                                 (good + 'extra=1\n', 'unknown key: extra', 1),
                                 (good.replace(self.rev1, '0' * 40), f'the pinned commit {"0" * 40} is missing from', 2)):
            with self.subTest(says=says):
                descriptor.write_text(text)
                self.assertIn(says, self.check(1))
                self.assertIn(says, self.it('sync', code=code).err)
        descriptor.write_text(good)
        self.assertEqual({k: v[:3] for k, v in snapshot(self.project).items()}, {k: v[:3] for k, v in before.items()})
        self.check()

    def test_a_revision_without_a_manifest_cannot_be_installed(self):
        self.git_in(self.runtime, 'checkout', '-q', '--detach', 'stable')
        self.git_in(self.runtime, 'rm', '-q', 'extension/project/manifest.json')
        self.git_in(self.runtime, 'commit', '-qm', 'no manifest')
        bare = self.git_in(self.runtime, 'rev-parse', 'HEAD').strip()
        self.git_in(self.runtime, 'checkout', '-q', 'main')
        err = self.it('init', '--session', 'Demo', '--revision', bare, code=2).err
        self.assertIn(f'{bare} has no extension/project/manifest.json; that revision cannot be installed', err)
        self.assertEqual(os.listdir(self.project), ['.git'])
        err = self.it('init', '--session', 'Demo', '--revision', 'no-such-ref', code=2).err
        self.assertIn('no-such-ref does not name a commit', err)
        self.assertEqual(os.listdir(self.project), ['.git'])
        self.it('init', '--session', 'Demo')
        self.commit_all()
        before = snapshot(self.project)
        self.assertIn('that revision cannot be installed', self.it('update', bare, code=2).err)
        self.assertIn('does not name a commit', self.it('update', 'no-such-ref', code=2).err)
        self.assertEqual(snapshot(self.project), before)
        self.check()

    def adopt_fixture(self):
        """A snapshot shaped like the offer-exchange checkout: a descriptor that predates project delivery."""
        descriptor = self.blob(self.rev1, 'templates/isabelle-tooling.conf').decode()
        for key, value in dict(SOURCE_REL='.', FORMAL_REL='formal', SESSION='Demo', MAX_HEAP='2G',
                               ISABELLE_VERSION='Isabelle2025-2', TOOLING_REVISION='f' * 40).items():
            descriptor = descriptor.replace(f'@{key}@', value)
        (self.project / 'isabelle-tooling.conf').write_text(descriptor)
        (self.project / 'formal/Demo').mkdir(parents=True)
        (self.project / 'formal/ROOTS').write_text('Demo\n')
        (self.project / 'formal/AGENTS.md').write_text('project notes\n')
        (self.project / 'AGENTS.md').write_text('Read formal/AGENTS.md.\n')
        os.symlink('AGENTS.md', self.project / 'CLAUDE.md')
        (self.project / '.claude/skills/their-skill').mkdir(parents=True)
        (self.project / '.claude/skills/their-skill/SKILL.md').write_text('theirs\n')
        (self.project / '.claude/settings.local.json').write_text('{"enabledMcpjsonServers": ["iq"]}\n')
        self.commit_all()

    def test_adoption_through_update(self):
        self.adopt_fixture()
        self.assertIn('no .isabelle-tooling/inventory.json', self.check(1))
        self.assertIn('run `isabelle-tooling update REV`', self.it('sync', code=1).err)
        self.it('update', 'stable')
        descriptor = self.read('isabelle-tooling.conf')
        self.assertIn(f'tooling_revision={self.rev1}\n', descriptor)
        self.assertEqual(descriptor.replace(self.rev1, 'f' * 40),
                         self.blob(self.rev1, 'templates/isabelle-tooling.conf').decode()
                         .replace('@TOOLING_REVISION@', 'f' * 40).replace('@SOURCE_REL@', '.')
                         .replace('@FORMAL_REL@', 'formal').replace('@SESSION@', 'Demo')
                         .replace('@MAX_HEAP@', '2G').replace('@ISABELLE_VERSION@', 'Isabelle2025-2'))
        self.assertTrue(self.read('AGENTS.md').startswith('Read formal/AGENTS.md.\n\n<!-- BEGIN isabelle-tooling'))
        self.assertTrue((self.project / '.claude/skills/their-skill/SKILL.md').is_file())
        self.assertEqual(self.read('.claude/settings.local.json'), '{"enabledMcpjsonServers": ["iq"]}\n')
        self.check()

    def test_adoption_refuses_existing_targets(self):
        self.adopt_fixture()
        (self.project / 'AGENTS.md').write_text('<!-- BEGIN isabelle-tooling -->\nold\n<!-- END isabelle-tooling -->\n')
        self.commit_all()
        self.assertIn('collision: AGENTS.md already has an unrecorded isabelle-tooling block',
                      self.it('update', 'stable', code=1).err)

    def test_link_mode_and_copy_restore_a_clean_tree(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        dev = self.work / 'dev'
        self.git_in(self.runtime, 'worktree', 'add', '-q', '--detach', str(dev), 'HEAD')
        self.addCleanup(self.git_in, self.runtime, 'worktree', 'remove', '--force', str(dev))
        self.it('sync', '--link', '--source', str(dev))
        (dev / 'extension/skills/isabelle-modeling/SKILL.md').write_text('an unmistakable development edit\n')
        self.assertEqual(self.read('.claude/skills/isabelle-modeling/SKILL.md'), 'an unmistakable development edit\n')
        self.assertIn('[FAIL] link mode', self.check(1))
        self.assertIn('[NOTE] link mode', self.it('sync', '--check', '--allow-dirty').out)
        self.assertIn('the skills are in link mode; run `isabelle-tooling sync` first',
                      self.it('update', 'next', code=1).err)
        self.it('sync')
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.check()

    # --- project kinds --------------------------------------------------------------------------

    def skill_dirs(self, root=None):
        root = root or self.project
        return tuple(sorted(os.listdir(root / '.agents/skills'))), tuple(sorted(os.listdir(root / '.claude/skills')))

    def set_kind(self, kind, root=None):
        """Edit the descriptor's model_kind as a user would; None removes it."""
        descriptor = (root or self.project) / 'isabelle-tooling.conf'
        lines = [line for line in descriptor.read_text().splitlines(keepends=True)
                 if not line.startswith('model_kind=')]
        if kind:
            at = next(i for i, line in enumerate(lines) if line.startswith('format_version=')) + 1
            lines.insert(at, f'model_kind={kind}\n')
        descriptor.write_text(''.join(lines))

    def test_theory_init_installs_setup_and_proving_only(self):
        self.it('init', '--session', 'Notes', '--kind', 'theory')
        self.assertIn('\nmodel_kind=theory\n', self.read('isabelle-tooling.conf'))
        self.assertNotIn('export_name', self.read('isabelle-tooling.conf'))
        self.assertEqual(self.read('formal/Notes/Notes.thy'), 'theory Notes\n  imports Main\nbegin\n\nend\n')
        self.assertIn('  sessions\n    "HOL-Library"\n', self.read('formal/Notes/ROOT'))
        self.assertNotIn('Conventions', self.read('formal/AGENTS.md'))
        self.assertEqual(self.skill_dirs(), (THEORY_SKILLS, THEORY_SKILLS))
        for name in THEORY_SKILLS:
            self.assertEqual((self.project / f'.agents/skills/{name}/SKILL.md').read_bytes(),
                             self.blob(self.rev1, f'extension/skills/{name}/SKILL.md'))
            self.assertEqual(os.readlink(self.project / f'.claude/skills/{name}'), f'../../.agents/skills/{name}')
        self.assertEqual((self.project / '.claude/agents/ic2-prover.md').read_bytes(),
                         self.blob(self.rev1, 'extension/agents/ic2-prover.md'))
        self.assertEqual((self.project / '.codex/agents/ic2_prover.toml').read_bytes(),
                         self.blob(self.rev1, 'extension/agents/ic2_prover.toml'))
        self.assertIn('iq', json.loads(self.read('.mcp.json'))['mcpServers'])
        self.assertIn('[mcp_servers.iq]', self.read('.codex/config.toml'))
        agents = self.read('AGENTS.md')
        self.assertIn('Isabelle theories under `formal/`', agents)
        for name in CODE_ONLY:
            self.assertNotIn(name, agents)
        inventory = json.loads(self.read('.isabelle-tooling/inventory.json'))
        self.assertEqual(inventory['directories'], [f'.agents/skills/{n}' for n in THEORY_SKILLS])
        self.check()
        listed = self.it('skills', 'list').out.splitlines()
        self.assertTrue(listed[0].endswith('isabelle-tooling.conf), for a theory project'), listed[0])
        self.assertTrue(listed[1].startswith('isabelle-setup [code, theory]: Set up'), listed[1])
        self.assertTrue(listed[2].startswith('isabelle-modeling [code; not installed here]: '), listed[2])
        self.assertEqual(sum('not installed here' in line for line in listed), 3)
        self.assertIn('[OK]   A theory project; source root', self.doctor())
        self.commit_all()
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_a_project_without_a_kind_is_a_code_project(self):
        self.it('init', '--session', 'Demo', '--kind', 'code')
        self.assertNotIn('model_kind', self.read('isabelle-tooling.conf'))
        self.assertEqual(self.skill_dirs(), (tuple(sorted(SKILLS)), tuple(sorted(SKILLS))))
        listed = self.it('skills', 'list').out.splitlines()
        self.assertTrue(listed[0].endswith(', for a code project'), listed[0])
        self.assertTrue(listed[2].startswith('isabelle-modeling [code]: '), listed[2])
        self.assertIn('[OK]   A code project; source root', self.doctor())
        self.commit_all()
        # An explicit model_kind=code installs the same files.
        self.set_kind('code')
        self.assertIn('Nothing changed', self.it('sync').out)
        self.check()
        self.assertIn('--kind', self.it('init', '--session', 'X', '--kind', 'other', code=2).err)
        self.set_kind('plain')
        self.assertIn('unknown model_kind: plain', self.it('sync', code=1).err)

    def test_a_descriptor_with_crlf_line_endings_is_refused(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        descriptor = self.project / 'isabelle-tooling.conf'
        descriptor.write_bytes(descriptor.read_bytes().replace(b'\n', b'\r\n'))
        before = snapshot(self.project)
        for args in (('sync', '--check'), ('sync',), ('update', 'stable'), ('skills', 'list')):
            result = self.it(*args, code=1)
            self.assertIn('isabelle-tooling.conf:1: carriage return (the descriptor must have LF line endings)',
                          result.out + result.err)
        self.assertIn('isabelle-tooling.conf:1: carriage return', self.doctor())
        self.assertEqual(snapshot(self.project), before)

    def test_theory_link_mode_and_shared_alias(self):
        self.it('init', '--session', 'Notes', '--kind', 'theory')
        self.commit_all()
        dev = self.work / 'dev'
        self.git_in(self.runtime, 'worktree', 'add', '-q', '--detach', str(dev), 'HEAD')
        self.addCleanup(self.git_in, self.runtime, 'worktree', 'remove', '--force', str(dev))
        self.it('sync', '--link', '--source', str(dev))
        links = {name: os.readlink(self.project / '.agents/skills' / name)
                 for name in os.listdir(self.project / '.agents/skills')}
        self.assertEqual(links, {name: f'{os.path.realpath(dev)}/extension/skills/{name}' for name in THEORY_SKILLS})
        self.it('sync')
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.check()
        # A project whose .claude/skills is .agents/skills gets the two skills and no aliases.
        shared = self.work / 'shared'
        (shared / '.agents/skills').mkdir(parents=True)
        (shared / '.claude').mkdir()
        os.symlink('../.agents/skills', shared / '.claude/skills')
        self.git('init', '-q', cwd=shared)
        self.git('add', '-A', cwd=shared)
        self.it('init', '--session', 'Notes', '--kind', 'theory', cwd=shared)
        inventory = json.loads((shared / '.isabelle-tooling/inventory.json').read_text())
        self.assertEqual((inventory['claude_skills'], inventory['symlinks']), ('shared', {}))
        self.assertEqual(self.skill_dirs(shared), (THEORY_SKILLS, THEORY_SKILLS))
        self.it('sync', '--check', cwd=shared)

    def test_switching_a_project_between_kinds(self):
        self.it('init', '--session', 'Demo')
        # Project-owned files beside the tooling's: never touched by a switch.
        local_skill = self.project / '.agents/skills/custom-workflow/SKILL.md'
        local_skill.parent.mkdir()
        local_skill.write_text('a project skill\n')
        os.symlink('../../.agents/skills/custom-workflow', self.project / '.claude/skills/custom-workflow')
        with open(self.project / 'AGENTS.md', 'a') as agents:
            agents.write('\n<!-- BEGIN custom-workflow -->\na project instruction block\n<!-- END custom-workflow -->\n')
        self.commit_all()
        before = snapshot(self.project)
        # Code to theory, by the README's steps; the hand edits are left unstaged.
        self.set_kind('theory')
        (self.project / 'formal/AGENTS.md').write_text(
            self.blob(self.rev1, 'templates/theory/formal/AGENTS.md').decode()
            .replace('@PROJECT_NAME@', 'demo').replace('@SESSION@', 'Demo'))
        readme = self.read('formal/README.md').replace('the project-specific modelling conventions', "the project's notes")
        (self.project / 'formal/README.md').write_text(readme)
        (self.project / 'formal/Demo/Demo.thy').write_text('theory Demo\n  imports Main\nbegin\n\nend\n')
        root = self.read('formal/Demo/ROOT')
        (self.project / 'formal/Demo/ROOT').write_text(
            root.replace('"Code-level Isabelle/HOL model of demo and the properties proved about it."',
                         '"Isabelle/HOL theories of demo."'))
        edited = {'isabelle-tooling.conf', 'formal/AGENTS.md', 'formal/README.md', 'formal/Demo/Demo.thy',
                  'formal/Demo/ROOT'}
        self.assertIn('differs from what', self.check(1))
        out = self.it('sync').out
        for name in CODE_ONLY:
            self.assertIn(f'.agents/skills/{name}/SKILL.md', out)
            self.assertIn(f'.claude/skills/{name}', out)
        self.assertEqual(self.skill_dirs(), (('custom-workflow',) + THEORY_SKILLS,) * 2)
        self.check()
        after = snapshot(self.project)
        changed = {rel for rel in before.keys() | after.keys() if before.get(rel, ())[:3] != after.get(rel, ())[:3]}
        removed = {rel for rel in changed if any(rel == f'{base}/{name}' or rel.startswith(f'.agents/skills/{name}/')
                                                 for base in ('.agents/skills', '.claude/skills')
                                                 for name in CODE_ONLY)}
        self.assertEqual(changed - removed, edited | {'.isabelle-tooling/inventory.json'})
        self.assertEqual(local_skill.read_text(), 'a project skill\n')
        self.assertIn('<!-- BEGIN custom-workflow -->\na project instruction block\n', self.read('AGENTS.md'))
        self.commit_all()
        self.assertEqual(self.git('status', '--porcelain'), '')
        # And back to code: the three skills return.
        self.set_kind(None)
        self.it('sync')
        self.assertEqual(self.skill_dirs(), (('custom-workflow',) + tuple(sorted(SKILLS)),) * 2)
        self.check()

    def test_switching_kinds_through_update(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        # Code to theory and stable to next in one update, which writes the descriptor and so needs it staged.
        self.set_kind('theory')
        self.assertIn('isabelle-tooling.conf has unstaged changes', self.it('update', 'next', code=1).err)
        self.git('add', 'isabelle-tooling.conf')
        self.git_in(self.runtime, 'checkout', '-q', 'next')
        out = self.it('update', 'next').out
        for name in CODE_ONLY:
            self.assertIn(f'.agents/skills/{name}/SKILL.md', out)
            self.assertIn(f'.claude/skills/{name}', out)
        self.assertEqual(self.skill_dirs(), (THEORY_SKILLS, THEORY_SKILLS))
        self.assertTrue((self.project / '.claude/skills/isabelle-proving/references/next-only.md').is_file())
        self.assertIn(f'tooling_revision={self.rev2}\n', self.read('isabelle-tooling.conf'))
        self.assertIn('model_kind=theory\n', self.read('isabelle-tooling.conf'))
        self.check()
        self.commit_all()
        # And back to code at stable.
        self.set_kind(None)
        self.git('add', 'isabelle-tooling.conf')
        self.git_in(self.runtime, 'checkout', '-q', 'main')
        self.it('update', 'stable')
        self.assertEqual(self.skill_dirs(), (tuple(sorted(SKILLS)),) * 2)
        self.assertFalse((self.project / '.agents/skills/isabelle-proving/references').exists())
        self.check()

    def test_switching_kinds_in_link_mode(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        before = snapshot(self.project)
        dev = self.work / 'dev'
        self.git_in(self.runtime, 'worktree', 'add', '-q', '--detach', str(dev), 'HEAD')
        self.addCleanup(self.git_in, self.runtime, 'worktree', 'remove', '--force', str(dev))
        # Each way linked, then back to copies, staged before the next switch as in copy mode.
        for kind, names in (('theory', THEORY_SKILLS), (None, tuple(sorted(SKILLS)))):
            self.set_kind(kind)
            self.it('sync', '--link', '--source', str(dev))
            links = {name: os.readlink(self.project / '.agents/skills' / name)
                     for name in os.listdir(self.project / '.agents/skills')}
            self.assertEqual(links, {name: f'{os.path.realpath(dev)}/extension/skills/{name}' for name in names})
            self.assertEqual(self.skill_dirs(), (names, names))
            self.it('sync')
            self.check()
            self.git('add', '-A')
        self.assertEqual({rel: entry[:3] for rel, entry in snapshot(self.project).items()},
                         {rel: entry[:3] for rel, entry in before.items()})

    def test_an_edited_code_only_skill_blocks_the_switch_to_theory(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        (self.project / '.agents/skills/isabelle-modeling/SKILL.md').write_text('our own conventions\n')
        self.git('add', '-A')
        self.set_kind('theory')
        err = self.it('sync', code=1).err
        self.assertIn('edited managed file: .agents/skills/isabelle-modeling/SKILL.md', err)
        self.assertEqual(self.skill_dirs(), (tuple(sorted(SKILLS)), tuple(sorted(SKILLS))))

    def test_revisions_before_kinds(self):
        # A theory project cannot move to a revision from before kinds, nor start at one.
        self.it('init', '--session', 'Notes', '--kind', 'theory')
        self.commit_all()
        before = snapshot(self.project)
        err = self.it('update', 'before-kinds', code=1).err
        self.assertIn('this project is of kind theory', err)
        self.assertIn(f'{self.rev0} does not support (it predates project kinds)', err)
        self.assertEqual(snapshot(self.project), before)
        other = self.work / 'other'
        other.mkdir()
        self.git('init', '-q', cwd=other)
        err = self.it('init', '--session', 'Notes', '--kind', 'theory', '--revision', 'before-kinds', cwd=other,
                      code=2).err
        self.assertIn(f'{self.rev0} has no templates/theory/', err)
        self.assertEqual(os.listdir(other), ['.git'])
        # A code project moves there and back, and can start there.
        self.it('init', '--session', 'Demo', '--revision', 'before-kinds', cwd=other)
        self.assertEqual(self.skill_dirs(other), (tuple(sorted(SKILLS)), tuple(sorted(SKILLS))))
        self.git('add', '-A', cwd=other)
        self.it('update', 'stable', cwd=other)
        self.git('add', '-A', cwd=other)
        # An explicit model_kind=code ties it to revisions with kinds.
        self.set_kind('code', other)
        before = snapshot(other)
        err = self.it('update', 'before-kinds', cwd=other, code=1).err
        self.assertIn(f'this project is of kind code, which isabelle-tooling {self.rev0} does not support '
                      '(it predates project kinds)', err)
        self.assertEqual(snapshot(other), before)
        self.set_kind(None, other)
        self.it('update', 'before-kinds', cwd=other)
        self.assertIn(f'tooling_revision={self.rev0}\n', (other / 'isabelle-tooling.conf').read_text())

    def test_replacing_an_uncommitted_code_scaffold(self):
        self.commit_all()
        self.it('init', '--session', 'Notes')
        # Since init: the project's own instructions, and Claude Code's local settings.
        (self.project / 'AGENTS.md').write_text('Project rules.\n\n' + self.read('AGENTS.md'))
        (self.project / '.claude/settings.local.json').write_text('{"enabledMcpjsonServers": ["iq"]}\n')
        self.git('add', '--', 'isabelle-tooling.conf', '.isabelle-tooling', 'formal', 'AGENTS.md', 'CLAUDE.md',
                 '.agents', '.claude/agents', '.claude/skills', '.codex', '.mcp.json')
        out = self.it('remove').out
        self.git('rm', '-r', '-q', '--cached', '--', 'formal')
        shutil.rmtree(self.project / 'formal')
        command = next(line.strip() for line in out.splitlines() if line.strip().startswith('git add -A -- '))
        subprocess.run(['bash', '-ec', command], cwd=self.project, env=self.env, check=True)
        self.assertEqual(self.git('status', '--porcelain', '--untracked-files=all').splitlines(),
                         ['A  AGENTS.md', 'A  CLAUDE.md', '?? .claude/settings.local.json'])
        self.assertEqual(self.read('AGENTS.md'), 'Project rules.\n')
        self.it('init', '--session', 'Notes', '--kind', 'theory')
        self.git('add', '-A', '--', '.', ':!.claude/settings.local.json')
        self.check()
        fresh = self.work / 'fresh'
        fresh.mkdir()
        self.git('init', '-q', cwd=fresh)
        self.it('init', '--session', 'Notes', '--kind', 'theory', '--project-name', 'demo', cwd=fresh)
        mine = {k: v[:2] for k, v in snapshot(self.project).items()}
        theirs = {k: v[:2] for k, v in snapshot(fresh).items()}
        self.assertEqual(mine.pop('.claude/settings.local.json')[0], 'file')
        self.assertEqual(self.read('AGENTS.md'), 'Project rules.\n\n' + (fresh / 'AGENTS.md').read_text())
        mine.pop('AGENTS.md'), theirs.pop('AGENTS.md')
        self.assertEqual(mine, theirs)

    # --- failures ---------------------------------------------------------------------------

    def failure_loop(self, args, finished_code=0):
        """Inject a failure after each publication step of ARGS in turn, on copies of the project.

        Each time, `sync --check` fails without reporting that the project files match and reads
        differently from the finished tree, the printed commands restore the tree and the index,
        and a rerun then succeeds and checks with FINISHED_CODE. Return the number of steps."""
        template = self.work / 'template'
        shutil.rmtree(template, ignore_errors=True)
        shutil.copytree(self.project, template, symlinks=True)
        checks = []
        for limit in range(1, 200):
            shutil.rmtree(self.project)
            shutil.copytree(template, self.project, symlinks=True)
            before = snapshot(self.project)
            status = self.git('status', '--porcelain', '--ignored', '--untracked-files=all')
            result = subprocess.run(['python3', '-c', DRIVER, str(self.runtime / 'scripts'), str(limit), *args],
                                    cwd=self.project, env=self.env, capture_output=True, text=True, timeout=120)
            if result.returncode == 0:
                # Only a failure after the last step, the descriptor, leaves a tree that checks as finished.
                *partial, finished = checks
                self.assertEqual(finished.returncode, finished_code, finished.out)
                for step, partial_check in enumerate(partial, 1):
                    self.assertEqual(partial_check.returncode, 1, f'step {step}: {partial_check.out}')
                    self.assertNotIn('project files match', partial_check.out, f'step {step}')
                    self.assertNotEqual(partial_check.out, finished.out, f'step {step} checks as finished')
                return limit - 1
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn(f'injected failure after step {limit}', result.stderr)
            checks.append(self.it('sync', '--check', code=None))
            lines = result.stderr.splitlines()
            start = next(i for i, line in enumerate(lines) if line.startswith('Restore them from'))
            commands = []
            for line in lines[start + 1:]:
                if not line.startswith('  '):
                    break
                commands.append(line.strip())
            subprocess.run(['bash', '-ec', '\n'.join(commands)], cwd=self.project, env=self.env, check=True)
            self.assertEqual({k: v[:3] for k, v in snapshot(self.project).items()},
                             {k: v[:3] for k, v in before.items()}, f'step {limit}: {commands}')
            self.assertEqual(self.git('status', '--porcelain', '--ignored', '--untracked-files=all'), status)
            self.it(*args)
            self.check(finished_code)
        self.fail(f'{args[0]} never completed')

    def test_failure_after_each_step_of_init_including_the_scaffold(self):
        (self.project / 'AGENTS.md').write_text('rules\n')
        (self.project / '.mcp.json').write_text('{"mcpServers": {}}\n')
        self.commit_all()
        self.assertGreaterEqual(self.failure_loop(['init', '--session', 'Demo']), 20)

    def test_failure_after_each_step_of_update_and_remove(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        # The runtime at the target, so that the finished update checks.
        self.git_in(self.runtime, 'checkout', '-q', 'next')
        self.assertGreaterEqual(self.failure_loop(['update', 'next']), 4)
        self.assertIn(f'tooling_revision={self.rev2}\n', self.read('isabelle-tooling.conf'))
        self.commit_all()
        self.assertGreaterEqual(self.failure_loop(['remove'], finished_code=1), 15)
        self.assertFalse((self.project / 'isabelle-tooling.conf').exists())
        self.assertTrue((self.project / 'formal/Demo/Demo.thy').is_file())

    def test_two_installers_and_another_filesystem(self):
        import fcntl
        import time
        lock = Path(self.git('rev-parse', '--path-format=absolute', '--git-path', 'project-files.lock').strip())
        logs = [self.work / f'installer-{i}.err' for i in range(2)]
        with open(lock, 'w') as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            runs = []
            for log in logs:
                with open(log, 'w') as err:
                    runs.append(subprocess.Popen([str(self.cli), 'init', '--session', 'Demo'], cwd=self.project,
                                                 env=self.env, stdout=subprocess.DEVNULL, stderr=err))
            deadline = time.monotonic() + 60
            while not all('waiting for another installer in this worktree' in log.read_text() for log in logs):
                self.assertEqual([r.poll() for r in runs], [None, None], [log.read_text() for log in logs])
                self.assertLess(time.monotonic(), deadline, 'the installers never reached the lock')
                time.sleep(0.05)
            self.assertEqual([r.poll() for r in runs], [None, None])
            self.assertEqual(os.listdir(self.project), ['.git'])  # neither wrote while it waited
        self.assertEqual(sorted(r.wait(timeout=120) for r in runs), [0, 1])
        self.check()
        shm = Path('/dev/shm')
        if shm.is_dir() and os.stat(shm).st_dev != os.stat(self.project).st_dev:
            other = self.work / 'other'
            other.mkdir()
            self.git('init', '-q', cwd=other)
            self.it('init', '--session', 'Demo', cwd=other, env=dict(self.env, TMPDIR=str(shm)))
            self.it('sync', '--check', cwd=other)

    # --- doctor ------------------------------------------------------------------------------

    def doctor(self, *args, env=None):
        result = subprocess.run([str(self.cli), 'doctor', '--project-root', str(self.project), *args],
                                env=env or self.env, capture_output=True, text=True, timeout=120)
        return result.stdout + result.stderr

    def test_doctor_host_configuration(self):
        self.it('init', '--session', 'Demo')
        clean = self.doctor()
        self.assertIn('[OK]   Host configuration: no Isabelle plugin, marketplace', clean)
        self.assertIn('[OK]   Project files: the isabelle-tooling project files match', clean)
        self.assertIn('[OK]   ISABELLE_TOOLING_ROOT names this tooling checkout', clean)
        claude, codex = self.work / 'claude-config', self.work / 'codex-home'
        (claude / 'plugins').mkdir(parents=True)
        (claude / 'agents').mkdir()
        (codex / 'agents').mkdir(parents=True)
        (claude / 'plugins/installed_plugins.json').write_text(json.dumps(
            {'plugins': {'isabelle-formal-modeling@isabelle-formal-modeling-tooling': []}}))
        (claude / 'plugins/known_marketplaces.json').write_text(json.dumps({'isabelle-formal-modeling-tooling': {}}))
        (claude / '.claude.json').write_text(json.dumps({'mcpServers': {'iq': {}},
                                                         'projects': {str(self.project): {'mcpServers': {'iq': {}}}}}))
        (claude / 'agents/prover.md').write_text('---\nname: ic2-prover\n---\n')
        (codex / 'config.toml').write_text(textwrap.dedent('''\
            [plugins."isabelle-formal-modeling@isabelle-formal-modeling-dev"]
            enabled = false
            [marketplaces.isabelle-formal-modeling-tooling]
            source = "x"
            [mcp_servers.iq]
            command = "x"
            '''))
        (codex / 'agents/ic2_prover.toml').write_text('name = "ic2_prover"\n')
        out = self.doctor(env=dict(self.env, CLAUDE_CONFIG_DIR=str(claude), CODEX_HOME=str(codex)))
        for expected in ('Claude Code has the plugin isabelle-formal-modeling@isabelle-formal-modeling-tooling',
                         'Claude Code knows the marketplace isabelle-formal-modeling-tooling',
                         'Claude Code declares a user-level iq MCP server',
                         f'Claude Code declares a local iq MCP server for {self.project}',
                         'a user-level Claude Code proof-worker profile',
                         'Codex CLI has the plugin isabelle-formal-modeling@isabelle-formal-modeling-dev',
                         'Codex CLI knows the marketplace isabelle-formal-modeling-tooling',
                         'Codex CLI declares a user-level iq MCP server',
                         'a user-level Codex CLI proof-worker profile'):
            self.assertIn(f'[FAIL] Host configuration: {expected}', out)
        self.assertIn('[FAIL] ISABELLE_TOOLING_ROOT is not set',
                      self.doctor(env={k: v for k, v in self.env.items() if k != 'ISABELLE_TOOLING_ROOT'}))

    def test_doctor_wrong_release_hints_follow_the_lookup_order(self):
        # Isabelle2025-2 projects take `isabelle` from PATH first; Isabelle2026 ones read their variable first.
        self.it('init', '--session', 'Demo')
        report = self.doctor(env=dict(self.env, MOCK_ISABELLE_VERSION='Isabelle2026'))
        self.assertIn('Expected Isabelle2025-2, found Isabelle2026 at ', report)
        self.assertIn('Put the bin/ of Isabelle2025-2 first on PATH; ISABELLE_TOOLING_ISABELLE is read only when '
                      'no isabelle is on PATH.', report)
        self.fresh_project('pide')
        self.it('init', '--session', 'Demo', '--isabelle-version', 'Isabelle2026')
        report = self.doctor()
        self.assertIn('Expected Isabelle2026, found Isabelle2025-2 at ', report)
        self.assertIn('Set ISABELLE_TOOLING_ISABELLE2026 to its installation directory or executable.', report)

    def test_doctor_isabelle_home_too_long_for_ic2(self):
        self.it('init', '--session', 'Demo')
        self.assertNotIn('too long for ic2', self.doctor())
        deep = self.base / ('d' * 60) / 'mock'
        out = self.doctor(env=dict(self.env, MOCK_ISABELLE_STATE_DIR=str(deep)))
        self.assertRegex(out, r'\[FAIL\] ISABELLE_HOME_USER \(.*\) is too long for ic2: server sockets there reach \d+ bytes')

    def test_doctor_is_read_only(self):
        self.it('init', '--session', 'Demo')
        self.commit_all()
        # Stale stat information: a status that may refresh the index would rewrite it.
        os.utime(self.project / 'AGENTS.md', (1, 1))
        os.utime(self.runtime / 'README.md', (1, 1))
        before = snapshot(self.project, skip_git=False), snapshot(self.runtime, skip_git=False)
        self.doctor()
        self.doctor('--allow-dirty')
        self.check()
        after = snapshot(self.project, skip_git=False), snapshot(self.runtime, skip_git=False)
        for old, new in zip(before, after):
            self.assertEqual(set(old) ^ set(new), set())
            self.assertEqual({k for k in old if old[k] != new[k]}, set())


class KindTests(unittest.TestCase):
    """Exercise project kinds through a fake spec on a scratch runtime."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(MODULE_DIR))
        sys.dont_write_bytecode = True
        import project_files
        cls.pf = project_files
        cls.tmp = tempfile.TemporaryDirectory(prefix='kinds-')
        cls.runtime = Path(cls.tmp.name)
        cls.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        cls.env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null', GIT_AUTHOR_NAME='test',
                       GIT_AUTHOR_EMAIL='test@example.invalid', GIT_COMMITTER_NAME='test',
                       GIT_COMMITTER_EMAIL='test@example.invalid')
        cls.git('init', '-q', '-b', 'main')
        for name in ('everywhere', 'only-x'):
            (cls.runtime / 'skills' / name).mkdir(parents=True)
            (cls.runtime / 'skills' / name / 'SKILL.md').write_text(f'# {name}\n')
        (cls.runtime / 'file.txt').write_text('a file\n')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def git(cls, *args):
        return subprocess.run(['git', *args], cwd=cls.runtime, env=cls.env, capture_output=True, text=True,
                              check=True).stdout

    def revision(self, kinds=None, skill_kinds=(['x'],), file_kinds=None):
        """Commit a manifest with the skill `everywhere` (no kinds) and `only-x`; return the revision."""
        manifest = dict(format=1, component='fake', skills=[dict(name='everywhere', source='skills/everywhere')],
                        files=[dict(path='out/file.txt', source='file.txt')])
        for value in skill_kinds:
            manifest['skills'].append(dict(name='only-x', source='skills/only-x', kinds=value))
        if kinds is not None:
            manifest['kinds'] = kinds
        if file_kinds is not None:
            manifest['files'][0]['kinds'] = file_kinds
        (self.runtime / 'manifest.json').write_text(json.dumps(manifest))
        self.git('add', '-A')
        self.git('commit', '-qm', 'manifest', '--allow-empty')
        return self.git('rev-parse', 'HEAD').strip()

    def spec(self, hook=True):
        pf, runtime = self.pf, self.pf.Runtime(self.runtime)

        class Spec:
            name, manifest, descriptor = 'fake', 'manifest.json', 'fake.conf'

            def __init__(self):
                self.runtime = runtime

            def substitutions(self, values):
                return {}

        class KindSpec(Spec):
            def kind(self, values):
                return values.get('kind')

        return KindSpec() if hook else Spec()

    def skills(self, revision, values, hook=True, shared=False):
        desired = self.pf.desired_state(self.spec(hook), revision, values, shared=shared)
        return [name for name, _ in desired.skills], sorted(desired.symlinks)

    def test_without_a_kind_every_entry_is_installed(self):
        for kinds in (None, ['x', 'y']):
            revision = self.revision(kinds)
            both = ['everywhere', 'only-x']
            self.assertEqual(self.skills(revision, {}, hook=False),
                             (both, ['.claude/skills/everywhere', '.claude/skills/only-x']))
            self.assertEqual(self.skills(revision, {'kind': 'y'}, hook=False)[0], both)
            self.assertEqual(self.skills(revision, {})[0], both)

    def test_a_kind_selects_the_skills(self):
        revision = self.revision(['x', 'y'])
        self.assertEqual(self.skills(revision, {'kind': 'x'})[0], ['everywhere', 'only-x'])
        self.assertEqual(self.skills(revision, {'kind': 'y'}), (['everywhere'], ['.claude/skills/everywhere']))
        self.assertEqual(self.skills(revision, {'kind': 'y'}, shared=True), (['everywhere'], []))
        desired = self.pf.desired_state(self.spec(), revision, {'kind': 'y'}, 'link', '/src')
        self.assertEqual(sorted(desired.symlinks), ['.agents/skills/everywhere', '.claude/skills/everywhere'])
        self.assertEqual(sorted(desired.files), ['out/file.txt'])

    def test_a_kind_the_revision_does_not_support_is_refused(self):
        for kinds, says in ((None, 'predates project kinds'), (['x'], 'it supports x')):
            revision = self.revision(kinds)
            with self.assertRaises(self.pf.Refused) as caught:
                self.skills(revision, {'kind': 'y'})
            self.assertIn('kind y', str(caught.exception))
            self.assertIn(says, str(caught.exception))

    def test_malformed_kinds_are_refused(self):
        cases = [dict(file_kinds=['x']), dict(kinds='x'), dict(kinds=['x', '']), dict(skill_kinds=('x',)),
                 dict(skill_kinds=([],)), dict(skill_kinds=([1],))]
        for case in cases:
            revision = self.revision(**dict(dict(kinds=['x']), **case))
            for hook, values in ((True, {'kind': 'x'}), (True, {}), (False, {})):
                with self.subTest(case=case, hook=hook, values=values), self.assertRaises(self.pf.Broken):
                    self.skills(revision, values, hook=hook)


class KeyValueTests(unittest.TestCase):
    """Check that descriptors split at LF alone, like the shell parser."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(MODULE_DIR))
        sys.dont_write_bytecode = True
        import project_files
        cls.pf = project_files

    def test_lines_end_at_lf_alone(self):
        separators = '\v\f\x1c\x1d\x1e\x85\u2028\u2029'
        self.assertEqual(self.pf.parse_key_values(f'# c\n\t# indented\n \t\na=1{separators}b=2\nc=3', 'x.conf'),
                         {'a': f'1{separators}b=2', 'c': '3'})
        for text, says in (('a=1\r\n', 'x.conf:1: carriage return (the descriptor must have LF line endings)'),
                           ('a=1\nb=2\rc=3\n', 'x.conf:2: carriage return'),
                           ('a=1\n# \0\n', 'x.conf: contains a NUL byte'),
                           ('\f\n', 'x.conf:1: expected key=value'), ('\xa0\n', 'x.conf:1: expected key=value')):
            with self.subTest(text=text), self.assertRaises(self.pf.Refused) as caught:
                self.pf.parse_key_values(text, 'x.conf')
            self.assertIn(says, str(caught.exception))

    def test_set_key_changes_only_its_line(self):
        text = 'a=1\x1cb=2\n# key=0\nkey=old\x85x\nz=9'
        self.assertEqual(self.pf.set_key(text, 'key', 'new'), 'a=1\x1cb=2\n# key=0\nkey=new\nz=9')
        self.assertEqual(self.pf.set_key(text, 'a', '5'), 'a=5\n# key=0\nkey=old\x85x\nz=9')
        self.assertEqual(self.pf.set_key('a=1', 'b', '2'), 'a=1\nb=2\n')


if __name__ == '__main__':
    unittest.main()
