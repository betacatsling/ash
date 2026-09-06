#!/usr/bin/env python3
"""Exercise read-only panel requests against disposable real files and Git repositories."""
import json, os, pathlib, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = pathlib.Path(os.environ.get('ASH_TEST_RUNTIME', ROOT / 'runtime/target/debug/ash-runtime'))

with tempfile.TemporaryDirectory(prefix='ash-panel-', dir='/tmp') as temp:
    temp = pathlib.Path(temp)
    repo = temp / 'repo'
    repo.mkdir()
    env = dict(os.environ, ASH_RUNTIME_HOME=str(temp / 'state'))

    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.PIPE).decode().strip()

    def request(action, ok=True, **kw):
        data = json.loads(subprocess.check_output([str(BIN), 'request'], input=json.dumps(dict(protocol=1, action=action, cwd=str(repo), **kw)).encode(), env=env))
        assert data['ok'] == ok, data
        return data.get('data', data.get('error'))

    git('init', '-q')
    git('config', 'user.email', 'panel-test@example.invalid')
    git('config', 'user.name', 'Panel test')
    (repo / 'first.txt').write_text('first\n')
    git('add', '.')
    assert request('reviewFiles')['files'] == [dict(path='first.txt', status='A')]
    assert '+first' in request('reviewDiff', path='first.txt')['text']
    git('commit', '-qm', 'base')
    base = git('rev-parse', 'HEAD')
    (repo / 'first.txt').write_text('second\n')
    git('commit', '-qam', 'second')
    assert request('reviewFiles')['files'] == []
    assert request('reviewFiles', base=base)['files'][0]['status'] == 'M'
    assert '+second' in request('reviewDiff', path='first.txt', base=base)['text']
    git('mv', 'first.txt', '重命名 file.txt')
    (repo / 'new\nfile.txt').write_text('new content\n')
    (repo / 'folder').mkdir()
    (repo / 'folder' / 'nested.txt').write_text('nested\n')
    (repo / 'binary').write_bytes(b'\x00\xff')
    (repo / 'large.txt').write_text('a' * 600_000)
    (temp / 'outside.txt').write_text('must not preview')
    (repo / 'escape').symlink_to(temp / 'outside.txt')
    (repo / 'pipe').mkfifo() if hasattr(pathlib.Path, 'mkfifo') else os.mkfifo(repo / 'pipe')
    before = git('status', '--porcelain=v1')
    entries = request('browseFiles')['entries']
    assert entries[0]['directory']
    names = [entry['name'] for entry in entries]
    assert '.git' not in names and 'escape' not in names and 'pipe' not in names
    assert request('browseFiles', path='folder')['entries'][0]['name'] == 'nested.txt'
    assert request('readFile', path='folder/nested.txt')['text'] == 'nested\n'
    request('readFile', path='../outside.txt', ok=False)
    request('readFile', path='escape', ok=False)
    request('readFile', path='pipe', ok=False)
    request('readFile', path='missing', ok=False)
    assert request('readFile', path='binary')['binary']
    assert request('readFile', path='large.txt')['truncated']
    files = {f['path']: f['status'] for f in request('reviewFiles')['files']}
    assert files['first.txt'] == 'D' and files['重命名 file.txt'] == 'A' and files['new\nfile.txt'] == '?'
    assert '+new content' in request('reviewDiff', path='new\nfile.txt')['text']
    assert '-second' in request('reviewDiff', path='first.txt')['text']
    request('reviewDiff', path='../outside.txt', ok=False)
    request('reviewFiles', base='--output=/tmp/inject', ok=False)
    assert git('status', '--porcelain=v1') == before
    git('add', 'large.txt')
    assert request('reviewDiff', path='large.txt')['truncated']
    print('PASS: file tree, Unicode paths, new/staged/deleted files, baseline, unborn HEAD, binary/size limits, path confinement, read-only Git')
