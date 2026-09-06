#!/usr/bin/env python3
"""Real SSH installation and upgrades in a private temporary root, never a saved host."""
import hashlib, json, os, pathlib, pwd, shlex, shutil, socket, subprocess, tempfile, time, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]
TMP = pathlib.Path(tempfile.mkdtemp(prefix='ash-boot-', dir='/tmp'))
server = None
packages = ROOT/'dist/runtime-packages'
manifest = json.loads((packages/'manifest.json').read_text())
package = next(p for p in manifest['packages'] if p['target'] == 'macos-aarch64')
payload = (packages/package['file']).read_bytes()
script = (ROOT/'scripts/remote-bootstrap.sh').read_text()
launcher = TMP/"bin with 'quote"/'ash-runtime'
state = TMP/'state'
def quote(s): return "'"+str(s).replace("'", "'\\''")+"'"
def wait(fn):
    for _ in range(50):
        if fn(): return
        time.sleep(.1)
    raise AssertionError('Condition timed out')
try:
    for name in ['host','client']:
        subprocess.run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(TMP/name)],check=True)
    with socket.socket() as s: s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
    (TMP/'sshd_config').write_text(f'''Port {port}
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
    server=subprocess.Popen(['/usr/sbin/sshd','-D','-e','-f',str(TMP/'sshd_config')],stderr=log)
    time.sleep(.3)
    assert server.poll() is None
    key=(TMP/'host.pub').read_text().split()
    (TMP/'known_hosts').write_text(f'[127.0.0.1]:{port} {key[0]} {key[1]}\n')
    config=TMP/'client_config'
    config.write_text(f'''Host ash-bootstrap
  HostName 127.0.0.1
  Port {port}
  User {pwd.getpwuid(os.getuid()).pw_name}
  IdentityFile {TMP}/client
  IdentitiesOnly yes
  UserKnownHostsFile {TMP}/known_hosts
  StrictHostKeyChecking yes
''')
    env=dict(os.environ,ASH_APP_HOME=str(TMP/'client-state'),ASH_SSH_CONFIG=str(config),ASH_RUNTIME_PACKAGES=str(packages),ASH_BOOTSTRAP_SCRIPT=str(ROOT/'scripts/remote-bootstrap.sh'),ASH_REMOTE_RUNTIME_HOME=str(state),ASH_TEST_LAUNCHER=str(launcher))
    checks=ROOT/'.build/bootstrap-checks'
    def check(mode, extra=None): subprocess.run([str(checks),mode],env=dict(env,**(extra or {})),check=True,timeout=60)
    ssh=['ssh','-F',str(config),'-o','BatchMode=yes','-T','ash-bootstrap']
    def remote_install(data, digest=None, target_launcher=launcher, target_root=state):
        command=' '.join(map(quote,['sh','-c',script,'ash-bootstrap','install',target_launcher,target_root,manifest['version'],digest or package['sha256']]))
        return subprocess.run([*ssh,command],input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
    def req(action, **args):
        result=subprocess.check_output([*ssh,quote(launcher)+' request'],input=json.dumps(dict(protocol=1,action=action,**args)).encode(),timeout=15)
        value=json.loads(result);assert value['ok'],value;return value['data']
    check('disabled');assert not launcher.exists()
    check('direct');assert not launcher.exists()
    check('paused');assert not launcher.exists()
    corrupt=TMP/'bad-packages';shutil.copytree(packages,corrupt)
    (corrupt/package['file']).write_bytes(payload+b'corruption')
    check('corrupt',{'ASH_RUNTIME_PACKAGES':str(corrupt)});assert not launcher.exists()
    check('install');assert launcher.exists()
    initial=launcher.read_bytes()
    versions=list((state/'versions').iterdir());assert len(versions)==1
    check('parallel');assert launcher.read_bytes()==initial and len(list((state/'versions').iterdir()))==1
    health=req('health');tmux=health['tmux']
    run=req('start',id=str(uuid.uuid4()),workspaceId='upgrade-test',cwd=str(TMP),title='Retained shell',agent='command',arguments=['/bin/sh'])
    pane='='+run['session']+':0.0'
    def tm(*args): return subprocess.check_output([tmux,'-S',health['socket'],*args]).decode().strip()
    wait(lambda: req('list')['runs'][0]['status']=='running')
    pid=tm('display-message','-p','-t',pane,'#{pane_pid}')
    tm('send-keys','-t',pane,"ASH_KEEP='alive-after-upgrade'; export ASH_KEEP",'Enter')
    worker_pid=tm('display-message','-p','-t','ash-scheduler:0.0','#{pane_pid}')
    # A legacy launcher reports the previous version but continues to run the real live sessions.
    current=launcher.read_text()
    legacy=current.replace('exec ', 'if [ "$1" = --version ]; then echo "ash-runtime 0.1.1 protocol 1"; exit 0; fi\nif [ "$1" = --self-check ]; then echo "ASH_READY|0.1.1|1|macos|aarch64"; exit 0; fi\nexec ', 1)
    launcher.write_text(legacy)
    check('fallback',{'ASH_RUNTIME_PACKAGES':str(corrupt)})
    before_failure=launcher.read_bytes()
    result=remote_install(payload[:100]);assert result.returncode!=0 and launcher.read_bytes()==before_failure
    print('PASS interrupted/corrupt transfer leaves the old launcher and live sessions unchanged')
    check('manual-paused')
    assert len(list((state/'versions').iterdir()))==2
    assert tm('display-message','-p','-t',pane,'#{pane_pid}')==pid
    tm('send-keys','-t',pane,"printf 'KEPT_%s\\n' \"$ASH_KEEP\"",'Enter')
    wait(lambda: 'KEPT_alive-after-upgrade' in req('transcript',id=run['id'])['text'])
    # New work hands off the old scheduler without terminating any existing run.
    quick=req('start',id=str(uuid.uuid4()),workspaceId='upgrade-test',cwd=str(TMP),title='New version',agent='command',arguments=['/bin/sh','-c','echo NEW_VERSION_OK'])
    wait(lambda: next(r for r in req('list')['runs'] if r['id']==quick['id'])['status']=='exited')
    assert tm('display-message','-p','-t','ash-scheduler:0.0','#{pane_pid}')!=worker_pid
    assert next(r for r in req('list')['runs'] if r['id']==run['id'])['status']=='running'
    assert tm('display-message','-p','-t',pane,'#{pane_pid}')==pid
    print('PASS upgrade retains shell PID and environment; scheduler handoff preserves live tasks')
    # Activation's post-cutover health failure must roll back the previous executable.
    broken_root=TMP/'broken';broken_root.mkdir();(broken_root/'state.sqlite').write_bytes(b'not sqlite')
    rollback=TMP/'rollback-launcher';rollback.write_text('#!/bin/sh\necho previous-runtime\n');rollback.chmod(0o700)
    old=rollback.read_bytes()
    result=remote_install(payload,target_launcher=rollback,target_root=broken_root)
    assert result.returncode!=0 and rollback.read_bytes()==old,result.stderr.decode()
    print('PASS failed health check atomically restores the prior launcher')
    # Never replace a newer server with an older client's runtime.
    future=current.replace('exec ', 'if [ "$1" = --version ]; then echo "ash-runtime 99.0.0 protocol 1"; exit 0; fi\nif [ "$1" = --self-check ]; then echo "ASH_READY|99.0.0|1|macos|aarch64"; exit 0; fi\nexec ', 1)
    launcher.write_text(future)
    old=launcher.read_bytes()
    result=remote_install(payload)
    assert result.returncode!=0 and launcher.read_bytes()==old
    print('PASS remote activation refuses a downgrade, including competing clients')
finally:
    subprocess.run([shutil.which('tmux'),'-S',str(state/'t.sock'),'kill-server'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if 'config' in locals():
        subprocess.run(['ssh','-F',str(config),'-o',f'ControlPath={pathlib.Path.home()}/.local/share/ash/ssh/%C','-O','exit','ash-bootstrap'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if server and server.poll() is None: server.terminate();server.wait()
    shutil.rmtree(TMP)
