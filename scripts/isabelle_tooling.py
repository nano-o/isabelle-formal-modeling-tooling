#!/usr/bin/env python3
"""The Isabelle tooling's command interface: skill inspection and project files.

bin/isabelle-tooling is the entry point; it sends `doctor` to doctor.sh and
everything else here. The installer rules shared with agent-board live in
project_files.py, an identical copy of agent-board's src/project_files.py.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

if sys.version_info < (3, 11):
    sys.exit('isabelle-tooling: needs Python 3.11 or later (tomllib)')

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import project_files  # noqa: E402
from project_files import Broken, Refused  # noqa: E402

TOOLING_ROOT = Path(__file__).resolve().parents[1]
DESCRIPTOR = 'isabelle-tooling.conf'
REQUIRED_KEYS = ('format_version', 'source_rel', 'formal_rel', 'build_session', 'session_dir',
                 'ic2_base_session', 'isabelle_version')
OPTIONAL_KEYS = ('tooling_revision', 'ic2_max_heap', 'export_name', 'model_dispatch', 'audit_collection')
PATH_KEYS = ('source_rel', 'formal_rel', 'session_dir', 'model_dispatch')


def parse_descriptor(text, where=DESCRIPTOR):
    """The rules of common.sh's parse_descriptor: known keys, required keys, relative paths."""
    values = project_files.parse_key_values(text, where)
    for key in values:
        if key not in REQUIRED_KEYS + OPTIONAL_KEYS:
            raise Refused(f'{where}: unknown key: {key}')
    for key in REQUIRED_KEYS:
        if key not in values:
            raise Refused(f'{where}: missing required key: {key}')
    if values['format_version'] != '1':
        raise Refused(f"{where}: unsupported format_version: {values['format_version']} (expected 1)")
    for key in PATH_KEYS:
        value = values.get(key)
        if value is None:
            continue
        if not value or value.startswith('/') or '..' in value.split('/'):
            raise Refused(f'{where}: {key} must be a relative path without a .. component: {value!r}')
    return values


class ToolingSpec:
    """The Isabelle tooling's part of the project files."""
    name = command = 'isabelle-tooling'
    descriptor = DESCRIPTOR
    revision_key = 'tooling_revision'
    inventory_dir = '.isabelle-tooling'
    manifest = 'extension/project/manifest.json'

    def __init__(self):
        self.runtime = project_files.Runtime(TOOLING_ROOT)

    def read_descriptor(self, text):
        return parse_descriptor(text)

    def substitutions(self, values):
        return {'FORMAL_REL': values['formal_rel']}


# --- skills list and show ----------------------------------------------------------------------

def nearest_descriptor(start):
    directory = Path(start).resolve()
    for candidate in (directory, *directory.parents):
        if (candidate / DESCRIPTOR).is_file():
            return candidate / DESCRIPTOR
    return None


def skill_revision(spec, project_root):
    """The revision skills are read from: the project's pin, else `stable`. Never a working tree."""
    if project_root:
        descriptor = Path(project_root) / DESCRIPTOR
        if not descriptor.is_file():
            raise Broken(f'--project-root: no {DESCRIPTOR} in {project_root}')
    else:
        descriptor = nearest_descriptor(os.getcwd())
    if descriptor is None:
        return spec.runtime.commit('stable'), 'stable'
    values = parse_descriptor(descriptor.read_text(), str(descriptor))
    revision = values.get('tooling_revision', '')
    if not project_files.FULL_REVISION.fullmatch(revision):
        raise Refused(f'{descriptor}: tooling_revision must be a full 40-hex commit, found {revision!r}')
    if not spec.runtime.has(revision):
        raise Broken(f'the pinned commit {revision} is missing from {spec.runtime.path}')
    return revision, f'pinned by {descriptor}'


def manifest_skills(spec, revision):
    import json
    try:
        manifest = json.loads(spec.runtime.blob(revision, spec.manifest))
    except Broken:
        raise Broken(f'{revision} has no {spec.manifest}') from None
    return [(s['name'], s['source']) for s in manifest.get('skills', [])]


def description(text):
    lines = text.splitlines()
    if lines and lines[0] == '---':
        for line in lines[1:]:
            if line == '---':
                break
            if line.startswith('description:'):
                return line.split(':', 1)[1].strip()
    return ''


def skills(args, spec):
    revision, where = skill_revision(spec, args.project_root)
    available = manifest_skills(spec, revision)
    if args.skills_action == 'list':
        out = f'isabelle-tooling skills at {revision} ({where})\n'
        for name, source in available:
            text = spec.runtime.blob(revision, f'{source}/SKILL.md').decode()
            out += f'{name}: {description(text)}\n'
        sys.stdout.write(out)
        return 0
    source = dict(available).get(args.name)
    if source is None:
        print(f'isabelle-tooling: no skill named {args.name!r} at {revision}; `isabelle-tooling skills list` '
              'names them', file=sys.stderr)
        return 1
    data = spec.runtime.blob(revision, f'{source}/SKILL.md')
    print(f'isabelle-tooling: {args.name} at {revision} ({where})', file=sys.stderr)
    sys.stdout.buffer.write(data)
    sys.stdout.flush()
    return 0


# --- the project operations -------------------------------------------------------------------

def scaffold(revision, args, root):
    """Render the descriptor and session with new-project.sh from REVISION's templates."""
    with tempfile.TemporaryDirectory(prefix='isabelle-tooling-init.') as stage:
        command = [str(TOOLING_ROOT / 'scripts/new-project.sh'), '--revision', revision, '--stage', stage,
                   '--session', args.session, '--project-name', args.project_name or root.name,
                   '--formal-rel', args.formal_rel, '--source-rel', args.source_rel, '--max-heap', args.max_heap]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise Broken(result.stderr.strip().removeprefix('ERROR: ') or 'new-project.sh failed')
        files = {}
        for directory, dirs, names in os.walk(stage):
            for name in names + [d for d in dirs if os.path.islink(os.path.join(directory, d))]:
                path = os.path.join(directory, name)
                rel = os.path.relpath(path, stage).replace(os.sep, '/')
                files[rel] = ('link', os.readlink(path)) if os.path.islink(path) else ('file', Path(path).read_bytes())
    descriptor = files.pop(DESCRIPTOR)[1].decode()
    return descriptor, files


def project(args, spec):
    root = project_files.checkout_root(args.project_root)
    action = args.action
    if action == 'init':
        revision = spec.runtime.commit(args.revision)
        descriptor, files = scaffold(revision, args, root)
        return project_files.init(root, spec, revision, descriptor, files)
    if action == 'sync':
        if args.check:
            if args.link or args.source:
                raise Broken('sync --check takes neither --link nor --source')
            findings, _ = project_files.check(root, spec, args.allow_dirty)
            sys.stdout.write(project_files.render_findings(findings))
            return 1 if any(f[0] == 'fail' for f in findings) else 0
        if args.allow_dirty:
            raise Broken('--allow-dirty goes with sync --check')
        if args.source and not args.link:
            raise Broken('--source goes with sync --link')
        return project_files.sync(root, spec, args.link, args.source)
    if action == 'update':
        return project_files.update(root, spec, args.revision)
    out = project_files.remove(root, spec)
    return out + ('The Isabelle session, and the instruction files outside the managed blocks, stay; '
                  'they belong to the project.\n')


def parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument('--project-root', metavar='DIR', help='the project checkout (default: the current one)')
    p = argparse.ArgumentParser(prog='isabelle-tooling', description='The Isabelle formal-modeling tooling: '
                                'skill inspection and project-local delivery. `isabelle-tooling doctor` runs '
                                'the read-only setup check (scripts/doctor.sh).')
    sub = p.add_subparsers(dest='action', required=True)
    q = sub.add_parser('skills', help='List or print the skills of the pinned revision (or stable)')
    s = q.add_subparsers(dest='skills_action', required=True)
    s.add_parser('list', parents=[common], help='Skill names and descriptions, with the revision read')
    r = s.add_parser('show', parents=[common], help='Print SKILL.md unchanged on stdout')
    r.add_argument('name', metavar='NAME')
    q = sub.add_parser('init', parents=[common], help='Create the descriptor, session and project files, '
                       'pinned at --revision (default stable)')
    q.add_argument('--session', required=True, help='Isabelle session name; also its directory')
    q.add_argument('--revision', default='stable')
    q.add_argument('--formal-rel', default='formal', help='formal artifacts, relative to the checkout (formal)')
    q.add_argument('--source-rel', default='.', help='code under study, relative to the checkout (.)')
    q.add_argument('--project-name', help='name used in generated text (default: the checkout directory name)')
    q.add_argument('--max-heap', default='12G', help='ic2 prover memory bound (12G)')
    q = sub.add_parser('sync', parents=[common], help='Reinstall the pinned project files; --link symlinks the '
                       'skills to --source; --check only checks')
    q.add_argument('--link', action='store_true')
    q.add_argument('--source', metavar='DIR')
    q.add_argument('--check', action='store_true')
    q.add_argument('--allow-dirty', action='store_true', help='with --check: link mode is a note, not a failure')
    q = sub.add_parser('update', parents=[common], help='Pin REV (a commit, or stable) and install its files')
    q.add_argument('revision', metavar='REV')
    sub.add_parser('remove', parents=[common], help='Remove the unchanged project files, the inventory and '
                   'the descriptor; the session stays')
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    spec = ToolingSpec()
    try:
        if args.action == 'skills':
            return skills(args, spec)
        result = project(args, spec)
        if isinstance(result, int):
            return result
        sys.stdout.write(result)
        return 0
    except Refused as exc:
        print(exc if str(exc).startswith('isabelle-tooling') else f'isabelle-tooling: {exc}', file=sys.stderr)
        return 1
    except (Broken, OSError, ValueError) as exc:
        print(exc if str(exc).startswith('isabelle-tooling') else f'isabelle-tooling: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
