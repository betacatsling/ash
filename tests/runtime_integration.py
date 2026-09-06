#!/usr/bin/env python3
"""Exercises real SQLite, tmux, processes and Git. No model requests or personal repos."""
import concurrent.futures, json, os, pathlib, shutil, subprocess, tempfile, time, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = pathlib.Path(os.environ.get('ASH_TEST_RUNTIME', ROOT / 'runtime/target/debug/ash-runtime'))
TMP = pathlib.Path(tempfile.mkdtemp(prefix='ash-test-', dir='/tmp'))
ENV = dict(os.environ, ASH_RUNTIME_HOME=str(TMP / 'state'))
TMUX = shutil.which('tmux')
checks = []
def request(action, **kw):
    raw = subprocess.check_output([str(BIN), 'request'], input=json.dumps(dict(protocol=1, action=action, **kw)).encode(), env=ENV)
    result = json.loads(raw)
    assert result['ok'], result
    return result['data']
def start(code='sleep 1', **kw):
    return request('start', **dict(id=str(uuid.uuid4()), workspaceId='test', cwd=str(TMP), title='Integration test', agent='command', arguments=['/bin/sh','-c',code], **kw))
def until(id, statuses, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        r = next(r for r in request('list')['runs'] if r['id'] == id)
        if r['status'] in statuses: return r
        time.sleep(.15)
    raise AssertionError((id, r))
def check(name): checks.append(name); print('PASS',name,flush=True)
try:
    h = request('health'); assert h['protocol'] == 1; check('protocol handshake and host discovery')
    r = start("printf 'hello 中文\\n'; exit 7")
    done = until(r['id'], ['exited']); assert done['exitCode'] == 7
    assert '中文' in request('transcript',id=r['id'])['text']; check('real execution, Unicode transcript and exit code')
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda _: request('start', id=r['id']), range(4)))
    assert all(v['id'] == r['id'] for v in results)
    assert sum(v['id'] == r['id'] for v in request('list')['runs']) == 1; check('concurrent duplicate launch is idempotent')
    request('settings',concurrency=1)
    a = start('sleep 30'); b = start('printf queued')
    assert b['status'] == 'queued'; check('host concurrency limit queues work')
    result = request('cancel',id=a['id']); assert result['status'] == 'cancelled'
    assert until(b['id'],['exited'])['exitCode'] == 0; check('confirmed cancellation frees a queue slot')
    # Requests are new processes: their exit never owns the managed process lifetime.
    a = start('sleep 30'); assert until(a['id'],['running'])
    subprocess.run([TMUX,'-S',h['socket'],'kill-session','-t','=ash-scheduler'],check=True)
    assert next(r for r in request('list')['runs'] if r['id']==a['id'])['status']=='running'
    b = start('printf restart'); request('cancel',id=a['id']); until(b['id'],['exited']); check('scheduler restart preserves sessions and resumes queue')
    repo = TMP / "repo 'with spaces"; repo.mkdir()
    def git(*args): return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.STDOUT).decode().strip()
    git('init'); git('config','user.email','test@localhost'); git('config','user.name','Ash Test')
    (repo/'file.txt').write_text('base\n'); git('add','.'); git('commit','-m','base')
    (repo/'file.txt').write_text('uncommitted\n')
    worktree=request('worktree',cwd=str(repo),id='isolated-test')
    assert pathlib.Path(worktree['path'],'file.txt').read_text()=='base\n'
    assert (repo/'file.txt').read_text()=='uncommitted\n'; check('worktree isolates HEAD and preserves original dirty checkout')
    diff=request('changes',cwd=str(repo)); assert '+uncommitted' in diff['diff']; check('Git result inspection handles quoted paths')
    fake = TMP/'bin'; fake.mkdir()
    for agent in ['pi','codex','claude']:
        p=fake/agent; p.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n'); p.chmod(0o755)
    ENV['PATH']=str(fake)+':'+ENV['PATH']
    # Restart only our test worker so it receives the updated test environment.
    subprocess.run([TMUX,'-S',h['socket'],'kill-session','-t','=ash-scheduler'],check=True)
    prompt="quotes ' and $(touch /tmp/ash-should-not-exist)\n中文"
    for agent in ['pi','codex','claude']:
        r=request('start',id=str(uuid.uuid4()),workspaceId='test',cwd=str(TMP),title='Adapter test',agent=agent,prompt=prompt)
        until(r['id'],['exited'])
        assert 'touch /tmp/ash-should-not-exist' in request('transcript',id=r['id'])['text']
    assert not pathlib.Path('/tmp/ash-should-not-exist').exists(); check('all three CLI adapters pass prompts literally without shell evaluation')
    r=start('sleep 30'); until(r['id'],['running'])
    subprocess.run([TMUX,'-S',h['socket'],'kill-session','-t','='+r['session']],check=True)
    assert until(r['id'],['lost'])['status']=='lost'; check('missing sessions reconcile as interrupted, never completed')
    request('archive',id=r['id']); assert next(v for v in request('list')['runs'] if v['id']==r['id'])['archived']; check('archiving preserves run records')
    stubborn = start('trap "" TERM HUP; echo $$ > stubborn.pid; while :; do sleep 1; done')
    until(stubborn['id'], ['running'])
    deadline=time.monotonic()+5
    while not (TMP/'stubborn.pid').exists() and time.monotonic()<deadline: time.sleep(.05)
    stubborn_pid=int((TMP/'stubborn.pid').read_text())
    request('cancel',id=stubborn['id'])
    time.sleep(.15)
    try:
        os.kill(stubborn_pid,0)
        state=subprocess.check_output(['ps','-o','stat=','-p',str(stubborn_pid)]).decode().strip()
        assert state.startswith('Z'), state
    except (ProcessLookupError, subprocess.CalledProcessError): pass
    check('cancellation escalates for foreground programs that ignore TERM and HUP')
    workspace=dict(id='durable-workspace',name='远端工作区',path=str(TMP),branch=None,split=True,selectedRunId=r['id'],secondaryRunId=None,archived=False)
    assert request('workspace',workspace=workspace)==workspace
    assert next(w for w in request('list')['workspaces'] if w['id']==workspace['id'])==workspace
    check('server workspace metadata and layout survive independent runtime processes')
    workspace['paneRunIds'] = ['pane-c', 'pane-a', 'pane-b']
    assert request('workspace', workspace=workspace) == workspace
    assert next(w for w in request('list')['workspaces'] if w['id'] == workspace['id'])['paneRunIds'] == ['pane-c', 'pane-a', 'pane-b']
    invalid_workspace = dict(workspace, paneRunIds=['pane-a', 'pane-a'])
    invalid = json.loads(subprocess.check_output([str(BIN), 'request'], input=json.dumps(dict(protocol=1, action='workspace', workspace=invalid_workspace)).encode(), env=ENV))
    assert not invalid['ok']
    check('ordered multi-pane layouts persist and duplicate pane IDs are rejected')
    assert any(w['id']=='test' for w in request('list')['workspaces'])
    check('pre-registry sessions are migrated into the server workspace inventory')
    print(f'All {len(checks)} integration checks passed.')
finally:
    subprocess.run([TMUX,'-S',str(TMP/'state/t.sock'),'kill-server'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(TMP)
