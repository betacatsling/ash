#!/usr/bin/env python3
"""Checks installer source selection and transport boundaries without installing remotely."""
import io,json,os,pathlib,subprocess,tarfile,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='ash-install-') as d:
    p=pathlib.Path(d); fake=p/'ssh'
    fake.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys,shlex
root=pathlib.Path(os.environ['ASH_INSTALL_TEST'])
with (root/'calls').open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
mode=shlex.split(sys.argv[-1])[4]
if mode=='probe': print('ASH_PROBE|macos|aarch64|missing')
else:
    (root/'payload.tar').write_bytes(sys.stdin.buffer.read())
    print('ASH_INSTALLED|0.1.2')
'''); fake.chmod(0o755)
    env=dict(os.environ,PATH=str(p)+':'+os.environ['PATH'],ASH_INSTALL_TEST=d)
    subprocess.run([str(ROOT/'scripts/install-remote.sh'),'user@dev-server'],env=env,check=True,stdout=subprocess.DEVNULL)
    calls=[json.loads(x) for x in (p/'calls').read_text().splitlines()]
    assert len(calls)==2 and all('user@dev-server' in c for c in calls)
    with tarfile.open(p/'payload.tar') as archive:
        names=[m.name for m in archive if m.isfile()]
        assert 'bin/ash-runtime' in names and 'bin/tmux' in names and not any(n.endswith('.rs') for n in names),names
    result=subprocess.run([str(ROOT/'scripts/install-remote.sh'),'-oProxyCommand=bad'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    assert result.returncode!=0
    print('PASS installer: valid host, verified package payload, binary transfer, bundled tmux, option rejection')
