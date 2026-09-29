#!/usr/bin/env python3
"""bin/isabelle-tooling: skill inspection, the project operations, and doctor's new checks.

Every test runs a scratch runtime checkout built from this working tree
(without the AutoCorrode submodule): `stable` at its first commit, `next`
one commit later with a supporting reference file in a skill and an edited
skill. Projects are disposable, with isolated Git and host configuration.
The rules shared with agent-board (scripts/project_files.py) are tested in
depth there; these tests cover what the Isabelle tooling adds and the plan's
installer cases.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

SOURCE = Path(__file__).resolve().parents[1]
SKILLS = ('isabelle-setup', 'isabelle-modeling', 'isabelle-proving', 'isabelle-differential',
          'isabelle-assurance')
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
                   if not k.startswith(('GIT_', 'AGENT_BOARD_', 'ISABELLE_', 'CLAUDE_', 'CODEX_'))}
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
                         self.blob(self.rev1, 'extension/codex/ic2_prover.toml'))
        self.assertEqual(json.loads(self.read('.mcp.json')), {'mcpServers': {'iq': {
            'command': '${ISABELLE_TOOLING_ROOT}/extension/bin/iq-bridge.sh', 'args': [],
            'env': {'IQ_MCP_BRIDGE_PORT': '8765'}}}})
        codex = self.read('.codex/config.toml')
        self.assertTrue(codex.startswith('# BEGIN isabelle-tooling\n# Managed by isabelle-tooling'))
        self.assertTrue(codex.endswith('IQ_MCP_BRIDGE_PORT = "8765"\n# END isabelle-tooling\n'))
        agents = self.read('AGENTS.md')
        self.assertIn('under `formal/`; read\n`formal/AGENTS.md`', agents)
        self.assertEqual(os.readlink(self.project / 'CLAUDE.md'), 'AGENTS.md')
        self.check()
        for text in [self.read(p) for p in ('.mcp.json', '.codex/config.toml', 'AGENTS.md', 'isabelle-tooling.conf',
                                            '.isabelle-tooling/inventory.json')]:
            self.assertNotIn(str(self.base), text)  # no machine paths in committed files
        self.assertIn('already exists', self.it('init', '--session', 'Demo', code=1).err)
        self.commit_all()
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
        self.it('init', '--session', 'Demo', '--revision', 'next')
        # The runtime's HEAD and working tree differ from the pin; neither matters.
        (self.runtime / 'extension/skills/isabelle-setup/SKILL.md').write_text('uncommitted edit\n')
        shown = self.it('skills', 'show', 'isabelle-setup', cwd=self.project / 'formal')
        self.assertEqual(shown.stdout, self.blob(self.rev2, 'extension/skills/isabelle-setup/SKILL.md'))
        self.assertIn(f'at {self.rev2} (pinned by {self.project}/isabelle-tooling.conf)', shown.err)
        listed = self.it('skills', 'list').out.splitlines()
        self.assertEqual(listed[0], f'isabelle-tooling skills at {self.rev2} (pinned by '
                                    f'{self.project}/isabelle-tooling.conf)')
        self.assertEqual([line.split(':')[0] for line in listed[1:]], list(SKILLS))
        self.assertIn('isabelle-setup: Set up and check the Isabelle', listed[1])
        unknown = self.it('skills', 'show', 'no-such-skill', code=1)
        self.assertEqual((unknown.stdout, 'skills list' in unknown.err), (b'', True))
        # No prover is needed to read.
        env = dict(self.env, PATH='/usr/bin:/bin')
        self.assertEqual(self.it('skills', 'show', 'isabelle-proving', env=env).stdout,
                         self.blob(self.rev2, 'extension/skills/isabelle-proving/SKILL.md'))

    def test_skills_refuse_a_malformed_descriptor_or_missing_object(self):
        (self.project / 'isabelle-tooling.conf').write_text('format_version=1\nnot a line\n')
        self.assertIn('expected key=value', self.it('skills', 'list', code=1).err)
        descriptor = self.blob(self.rev1, 'templates/isabelle-tooling.conf').decode()
        for key, value in dict(SOURCE_REL='.', FORMAL_REL='formal', SESSION='Demo', MAX_HEAP='2G',
                               ISABELLE_VERSION='Isabelle2025-2', TOOLING_REVISION='0' * 40).items():
            descriptor = descriptor.replace(f'@{key}@', value)
        (self.project / 'isabelle-tooling.conf').write_text(descriptor)
        self.assertIn('is missing from', self.it('skills', 'show', 'isabelle-setup', code=2).err)
        (self.project / 'isabelle-tooling.conf').write_text(descriptor.replace('0' * 40, 'stable'))
        self.assertIn('full 40-hex commit', self.it('skills', 'show', 'isabelle-setup', code=1).err)

    # --- shared files ------------------------------------------------------------------------

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
        self.it('sync')
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.check()

    # --- failures ---------------------------------------------------------------------------

    def test_failure_after_each_step_of_init_including_the_scaffold(self):
        (self.project / 'AGENTS.md').write_text('rules\n')
        (self.project / '.mcp.json').write_text('{"mcpServers": {}}\n')
        self.commit_all()
        template = self.work / 'template'
        shutil.copytree(self.project, template, symlinks=True)
        args = ['init', '--session', 'Demo']
        checks = []
        for limit in range(1, 200):
            shutil.rmtree(self.project)
            shutil.copytree(template, self.project, symlinks=True)
            before = snapshot(self.project)
            result = subprocess.run(['python3', '-c', DRIVER, str(self.runtime / 'scripts'), str(limit), *args],
                                    cwd=self.project, env=self.env, capture_output=True, text=True, timeout=120)
            if result.returncode == 0:
                self.assertEqual(checks[:-1], [1] * (limit - 2))
                self.assertGreater(limit, 20)
                return
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            checks.append(self.it('sync', '--check', code=None).returncode)
            lines = result.stderr.splitlines()
            start = next(i for i, line in enumerate(lines) if line.startswith('Restore them from'))
            commands = []
            for line in lines[start + 1:]:
                if not line.startswith('  '):
                    break
                commands.append(line.strip())
            subprocess.run(['bash', '-ec', '\n'.join(commands)], cwd=self.project, env=self.env, check=True)
            self.assertEqual({k: v[:3] for k, v in snapshot(self.project).items()},
                             {k: v[:3] for k, v in before.items()}, f'step {limit}')
            self.it(*args)
            self.check()
        self.fail('init never completed')

    def test_two_installers_and_another_filesystem(self):
        import fcntl
        import time
        lock = Path(self.git('rev-parse', '--path-format=absolute', '--git-path', 'project-files.lock').strip())
        with open(lock, 'w') as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            runs = [subprocess.Popen([str(self.cli), 'init', '--session', 'Demo'], cwd=self.project, env=self.env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
            time.sleep(0.5)
            self.assertEqual([r.poll() for r in runs], [None, None])
        self.assertEqual(sorted(r.communicate(timeout=120) and r.returncode for r in runs), [0, 1])
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
        self.assertIn('No agent-board.conf', clean)
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

    def board_stub(self, version, doctor_output, doctor_code=0):
        stub = self.work / 'agent-board-stub'
        stub.write_text(textwrap.dedent(f'''\
            #!/usr/bin/env bash
            printf '%s\n' "$*" >>"{self.work}/board-calls"
            case "$1" in
              version) printf '%s\\n' {json.dumps(json.dumps(version))} ;;
              doctor) printf '%s\\n' {json.dumps(doctor_output)}; exit {doctor_code} ;;
            esac
            '''))
        stub.chmod(0o755)
        return dict(self.env, AGENT_BOARD_COMMAND=str(stub))

    def test_doctor_board_adapter(self):
        self.it('init', '--session', 'Demo')
        (self.project / 'agent-board.conf').write_text('format_version=1\n')
        good = dict(interface=1, state_format=2, capabilities=['bounded-digest', 'doctor', 'project'])
        report = json.dumps(dict(interface=1, ok=False, checks=[
            dict(id='files', status='ok', message='match'), dict(id='guard.pre-commit', status='fail',
                                                                 message='no guard\nat all')]))
        out = self.doctor(env=self.board_stub(good, report, 1))
        self.assertEqual((self.work / 'board-calls').read_text(),
                         f'version --json\ndoctor --json --project-root {self.project}\n')
        self.doctor('--allow-dirty', env=self.board_stub(good, report, 1))
        self.assertTrue((self.work / 'board-calls').read_text().endswith(
            f'doctor --json --project-root {self.project} --allow-dirty\n'))
        self.assertIn('[OK]   board: files: match', out)
        self.assertIn('[FAIL] board: guard.pre-commit: no guard at all', out)
        out = self.doctor(env=self.board_stub(dict(good, interface=2), report))
        self.assertIn('[FAIL] board: ', out)
        self.assertIn('has interface 2; this tooling supports interface 1', out)
        out = self.doctor(env=self.board_stub(dict(good, capabilities=['doctor']), report))
        self.assertIn('lacks the capabilities: project', out)
        self.assertIn('doctor could not run (exit 2)', self.doctor(env=self.board_stub(good, report, 2)))
        self.assertIn('doctor could not run (exit 0)', self.doctor(env=self.board_stub(good, 'not json')))
        env = dict(self.env, AGENT_BOARD_COMMAND='')
        env['PATH'] = f"{self.base / 'bin'}:/usr/bin:/bin"
        self.assertIn('agent-board does not resolve', self.doctor(env=env))
        (self.project / 'agent-board.conf').unlink()
        self.assertIn('No agent-board.conf', self.doctor(env=self.board_stub(good, report)))

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


if __name__ == '__main__':
    unittest.main()
