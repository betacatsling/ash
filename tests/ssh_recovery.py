#!/usr/bin/env python3
"""Exercises production AppStore + real OpenSSH + remote tmux, without personal hosts."""
import json, os, pathlib, pwd, shlex, shutil, socket, subprocess, tempfile, time, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]
TMP = pathlib.Path(tempfile.mkdtemp(prefix='ash-recover-', dir='/tmp'))
BIN = ROOT/'runtime/target/debug/ash-runtime'
server = None
connections = []
def wait_for(fn, timeout=8):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if fn(): return
        time.sleep(.15)
    raise AssertionError('Recovery condition timed out')
try:
    for name in ['host','client']:
        subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(TMP/name)],check=True)
    with socket.socket() as s: s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
    config=TMP/'sshd_config'
    config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {TMP}/host
PidFile {TMP}/sshd.pid
AuthorizedKeysFile {TMP}/client.pub
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
LogLevel ERROR
''')
    log=open(TMP/'server.log','w+')
    def start_server():
        global server
        server=subprocess.Popen(['/usr/sbin/sshd','-D','-e','-f',str(config)],stderr=log)
        time.sleep(.3)
        if server.poll() is not None:
            log.seek(0); raise RuntimeError(log.read())
    start_server()
    public=(TMP/'host.pub').read_text().split()
    (TMP/'known_hosts').write_text(f'[127.0.0.1]:{port} {public[0]} {public[1]}\n')
    client_config=TMP/'client_config'
    client_config.write_text(f'''Host ash-recovery
  HostName 127.0.0.1
  User {pwd.getpwuid(os.getuid()).pw_name}
  Port {port}
  IdentityFile {TMP}/client
  IdentitiesOnly yes
  UserKnownHostsFile {TMP}/known_hosts
  StrictHostKeyChecking yes
''')
    remote_cmd=f'export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; ASH_RUNTIME_HOME={shlex.quote(str(TMP/"state"))} {shlex.quote(str(BIN))} request'
    wrapper=TMP/'runtime-wrapper'
    wrapper.write_text('#!/bin/sh\n'+remote_cmd+'\n'); wrapper.chmod(0o755)
    # A custom client config is used by the actual Swift RuntimeClient. No ~/.ssh/config edits.
    env=dict(os.environ,ASH_APP_HOME=str(TMP/'client-state'),ASH_SSH_CONFIG=str(client_config),ASH_RUNTIME_BIN=str(BIN),ASH_RUNTIME_HOME=str(TMP/'local-state'))
    def req(action,**kw):
        raw=subprocess.check_output(['ssh','-F',str(client_config),'-o','BatchMode=yes','-T','ash-recovery',remote_cmd],input=json.dumps(dict(protocol=1,action=action,**kw)).encode(),timeout=15)
        value=json.loads(raw); assert value['ok'],value; return value['data']
    health=req('health')
    runs=[req('start',id=str(uuid.uuid4()),workspaceId='ssh-workspace',cwd=str(TMP),title='Persistent Shell',agent='command',arguments=['/bin/sh']) for _ in range(2)]
    first=runs[0]
    record=dict(id='ssh-workspace',name='服务器上的研发工作区',path=str(TMP),branch=None,split=True,selectedRunId=first['id'],secondaryRunId=runs[1]['id'],archived=False)
    req('workspace',workspace=record)
    def attach(run):
        command=' '.join(map(lambda s: "'"+s.replace("'", "'\\''")+"'",[health['tmux'],'-S',health['socket'],'attach-session','-t','='+run['session']]))
        p=subprocess.Popen(['ssh','-F',str(client_config),'-tt','ash-recovery',command],stdin=subprocess.PIPE,stdout=open(TMP/"attach.log","ab"),stderr=open(TMP/"attach.log","ab"),env=dict(os.environ,TERM="xterm-256color"))
        connections.append(p)
        def ready():
            if p.poll() is not None: raise RuntimeError((TMP/"attach.log").read_text() + str(req("list")))
            value=subprocess.check_output([health['tmux'],'-S',health['socket'],'display-message','-p','-t','='+run['session']+':0.0','#{session_attached}']).strip()
            return value==b'1'
        try: wait_for(ready)
        except Exception:
            print((TMP/"attach.log").read_text())
            print(subprocess.check_output([health["tmux"],"-S",health["socket"],"list-clients"]).decode())
            raise
        return p
    conn=attach(first)
    conn.stdin.write(b"ASH_SESSION_TOKEN='same-live-shell'; export ASH_SESSION_TOKEN; printf 'BEFORE_%s\\n' \"$$\"\n");conn.stdin.flush()
    wait_for(lambda: 'BEFORE_' in req('transcript',id=first['id'])['text'])
    pane=f"={first['session']}:0.0"
    pid=subprocess.check_output([health['tmux'],'-S',health['socket'],'display-message','-p','-t',pane,'#{pane_pid}']).strip()
    conn.terminate();conn.wait(timeout=5)
    # A fresh client knows the SSH host but has no workspace list or session cache.
    state=pathlib.Path(env['ASH_APP_HOME']);state.mkdir()
    (state/'state.json').write_text(json.dumps(dict(hosts=[dict(id='ssh-recovery',name='Recovery host',address='ash-recovery',managed=True,runtimePath=str(wrapper))],workspaces=[],fontSize=13,appearance='system',showInspector=True)))
    checks=ROOT/'.build/appstore-recovery-checks'
    subprocess.run([str(checks),'restore'],env=env,check=True,timeout=30)
    # Kill the private listener and the client's private multiplexed connection.
    control=str(pathlib.Path.home()/'.local/share/ash/ssh/%C')
    subprocess.run(['ssh','-F',str(client_config),'-o',f'ControlPath={control}','-O','exit','ash-recovery'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    server.terminate();server.wait()
    subprocess.run([str(checks),'offline'],env=env,check=True,timeout=25)
    start_server()
    subprocess.run([str(checks),'restore-edits'],env=env,check=True,timeout=30)
    conn=attach(first)
    conn.stdin.write(b"printf 'RESTORED_%s\\n' \"$ASH_SESSION_TOKEN\"\n");conn.stdin.flush()
    wait_for(lambda: 'RESTORED_same-live-shell' in req('transcript',id=first['id'])['text'])
    after=subprocess.check_output([health['tmux'],'-S',health['socket'],'display-message','-p','-t',pane,'#{pane_pid}']).strip()
    assert pid==after
    snapshot=req('list'); assert {r['id'] for r in snapshot['runs']}=={r['id'] for r in runs}
    print('PASS reconnect restores the same shell PID, environment and exact session IDs')
    print('PASS no commands or agent tasks were relaunched during workspace recovery')
finally:
    for conn in connections:
        if conn.poll() is None: conn.terminate();conn.wait(timeout=5)
    if 'client_config' in locals():
        subprocess.run(['ssh','-F',str(client_config),'-o',f'ControlPath={pathlib.Path.home()}/.local/share/ash/ssh/%C','-O','exit','ash-recovery'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for state in ['state','local-state']:
        subprocess.run([shutil.which('tmux'),'-S',str(TMP/state/'t.sock'),'kill-server'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if server is not None and server.poll() is None: server.terminate();server.wait()
    shutil.rmtree(TMP)
