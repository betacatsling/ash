#!/usr/bin/env python3
"""Isolated loopback OpenSSH test; never connects to a user's saved remote host."""
import json, os, pathlib, pwd, shutil, socket, subprocess, tempfile, time, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
TMP=pathlib.Path(tempfile.mkdtemp(prefix='ash-ssh-',dir='/tmp'))
BIN=ROOT/'runtime/target/debug/ash-runtime'
server=None
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
    server=subprocess.Popen(['/usr/sbin/sshd','-D','-e','-f',str(config)],stderr=log)
    time.sleep(.4)
    if server.poll() is not None:
        log.seek(0); raise RuntimeError(log.read())
    # Pre-pin our generated host key instead of disabling host verification.
    public=(TMP/'host.pub').read_text().split()
    (TMP/'known_hosts').write_text(f'[127.0.0.1]:{port} {public[0]} {public[1]}\n')
    opts=['-F','/dev/null','-p',str(port),'-i',str(TMP/'client'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o',f'UserKnownHostsFile={TMP}/known_hosts','-o','StrictHostKeyChecking=yes']
    dest=pwd.getpwuid(os.getuid()).pw_name+'@127.0.0.1'
    import shlex
    command=f'export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; ASH_RUNTIME_HOME={shlex.quote(str(TMP/"state"))} {shlex.quote(str(BIN))} request'
    def req(action,**kw):
        raw=subprocess.check_output(['ssh',*opts,'-T',dest,command],input=json.dumps(dict(protocol=1,action=action,**kw)).encode(),timeout=20)
        v=json.loads(raw); assert v['ok'],v; return v['data']
    health=req('health'); print('PASS real SSH authentication, pinned host key and runtime handshake',flush=True)
    run=req('start',id=str(uuid.uuid4()),workspaceId='ssh-test',cwd=str(TMP),title='SSH test',agent='command',arguments=['/bin/sh','-c','printf "SSH_TRANSPORT_OK\\n"; sleep 60'])
    attach=' '.join(map(lambda s: "'"+s.replace("'", "'\\''")+"'",[health['tmux'],'-S',health['socket'],'attach-session','-t','='+run['session']]))
    conn=subprocess.Popen(['ssh',*opts,'-tt',dest,attach],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=dict(os.environ,TERM="xterm-256color"))
    time.sleep(.5)
    assert conn.poll() is None, conn.stderr.read().decode()
    attached=subprocess.check_output([health['tmux'],'-S',health['socket'],'display-message','-p','-t','='+run['session']+':0.0','#{session_attached}']).strip()
    assert attached==b'1', attached
    conn.terminate(); conn.wait(timeout=5)
    listed=req('list')['runs']; assert next(r for r in listed if r['id']==run['id'])['status']=='running'
    assert 'SSH_TRANSPORT_OK' in req('transcript',id=run['id'])['text']
    print('PASS SSH attach/disconnect leaves the remote task running',flush=True)
    assert req('cancel',id=run['id'])['status']=='cancelled'
    print('PASS cancellation is acknowledged by the remote runtime',flush=True)
finally:
    subprocess.run([shutil.which('tmux'),'-S',str(TMP/'state/t.sock'),'kill-server'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if server: server.terminate(); server.wait()
    shutil.rmtree(TMP)
