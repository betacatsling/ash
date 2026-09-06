#!/usr/bin/env python3
"""Real tmux/process/file inspection with local fixtures; never invokes a model."""
import json, os, pathlib, shlex, shutil, subprocess, tempfile, time, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = pathlib.Path(os.environ.get('ASH_TEST_RUNTIME', ROOT / 'runtime/target/debug/ash-runtime'))
TMP = pathlib.Path(tempfile.mkdtemp(prefix='ash-agents-', dir='/tmp'))
ENV = dict(os.environ, ASH_RUNTIME_HOME=str(TMP/'state'))
TMUX = shutil.which('tmux')
def request(action, **kw):
    raw = subprocess.check_output([str(BIN), 'request'], input=json.dumps(dict(protocol=1, action=action, **kw)).encode(), env=ENV)
    result = json.loads(raw)
    assert result['ok'], result
    return result['data']
def shell():
    return request('start', id=str(uuid.uuid4()), workspaceId='fixture', cwd=str(TMP), title='Agent inspector test', agent='shell')
def write_log(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(r)+'\n' for r in rows))
def plan(title, status='in_progress'):
    return [dict(type='response_item', payload=dict(type='function_call', name='update_plan', call_id='one', arguments=json.dumps(dict(plan=[dict(step=title,status=status)])))),
            dict(type='response_item', payload=dict(type='function_call_output',call_id='one',output='Plan updated'))]
def inspect(run, title):
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        snapshot=request('agentTasks', id=run['id'])
        if any(t['title']==title for s in snapshot['sessions'] for t in s['tasks']): return snapshot
        time.sleep(.2)
    raise AssertionError(snapshot)
try:
    # The executable name and open file descriptors match real CLI discovery.
    source=TMP/'fixture.c'
    source.write_text('#include <stdio.h>\n#include <unistd.h>\nint main(int n,char **a){FILE *f=fopen(a[1],"r"); if(!f)return 1; for(;;)sleep(1);}')
    subprocess.run(['cc',str(source),'-o',str(TMP/'codex')],check=True)
    shutil.copy2(TMP/'codex',TMP/'claude')
    h=request('health')
    a,b,c=shell(),shell(),shell()
    assert request('agentTasks',id=a['id'])['sessions']==[]
    def launch(run, agent, file):
        command=f'{shlex.quote(str(TMP/agent))} {shlex.quote(str(file))}'
        subprocess.run([TMUX,'-S',h['socket'],'send-keys','-t',f"={run['session']}:0.0",'-l',command],check=True)
        subprocess.run([TMUX,'-S',h['socket'],'send-keys','-t',f"={run['session']}:0.0",'Enter'],check=True)
    one,two=TMP/'rollout-one.jsonl',TMP/'rollout-two.jsonl'
    write_log(one,plan('第一项任务')); write_log(two,plan('另一个终端'))
    launch(a,'codex',one); launch(b,'codex',two)
    snapshot=inspect(a,'第一项任务')
    assert len(snapshot['sessions'])==1
    assert all(t['title']!='另一个终端' for s in snapshot['sessions'] for t in s['tasks'])
    inspect(b,'另一个终端')
    write_log(one,plan('第一项任务','completed'))
    assert inspect(a,'第一项任务')['sessions'][0]['tasks'][0]['status']=='completed'
    print('PASS manual shell launch, live Codex plan updates and same-cwd session isolation')
    config=TMP/'claude-config'
    log=config/'projects'/'workspace'/'test-session.jsonl'
    write_log(log,[{'message':{'content':[{'type':'tool_use','id':'a','name':'TodoWrite','input':{'todos':[{'content':'Claude 清单','status':'pending'}]}}]}},
                   {'message':{'content':[{'type':'tool_result','tool_use_id':'a','content':'ok'}]}}])
    debug=config/'debug'/'test-session.txt'; debug.parent.mkdir(); debug.write_text('')
    launch(c,'claude',debug)
    inspect(c,'Claude 清单')
    taskdir=config/'tasks'/'test-session';taskdir.mkdir(parents=True)
    (taskdir/'7.json').write_text(json.dumps(dict(id='7',subject='共享任务更新',status='completed')))
    snapshot=inspect(c,'共享任务更新')
    assert snapshot['sessions'][0]['tasks'][0]['status']=='completed'
    print('PASS Claude exact debug-session binding, TodoWrite and current task files')
    # Registry binding works even when neither transcript nor debug log is open.
    ENV['CLAUDE_CONFIG_DIR']=str(config)
    d=shell()
    plain=TMP/'unrelated.txt';plain.write_text('')
    launch(d,'claude',plain)
    deadline=time.monotonic()+5
    pid=None
    while time.monotonic()<deadline:
        ps=subprocess.check_output(['ps','-axo','pid=,args=']).decode()
        for line in ps.splitlines():
            fields=line.split(None,1)
            if len(fields)==2 and fields[1]==f'{TMP/"claude"} {plain}': pid=int(fields[0])
        if pid: break
        time.sleep(.1)
    assert pid
    registry=config/'sessions';registry.mkdir()
    birth=subprocess.check_output(['ps','-o','lstart=','-p',str(pid)],env=dict(os.environ,LC_ALL='C',TZ='UTC')).decode().strip()
    meta=registry/f'{pid}.json'
    meta.write_text(json.dumps(dict(pid=pid,sessionId='test-session',procStart=birth)))
    inspect(d,'共享任务更新')
    meta.write_text(json.dumps(dict(pid=pid,sessionId='test-session',procStart='stale process')))
    assert all(not s['tasks'] for s in request('agentTasks',id=d['id'])['sessions'])
    print('PASS Claude PID registry binds current process and rejects stale process identity')
    request('cancel',id=a['id'])
    assert request('agentTasks',id=a['id'])['sessions']==[]
    assert request('agentTasks',id=b['id'])['sessions']
    print('PASS stopped agent clears tasks without affecting another terminal')
finally:
    subprocess.run([TMUX,'-S',str(TMP/'state/t.sock'),'kill-server'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(TMP,ignore_errors=True)
