#!/usr/bin/env python3
"""Run the actual Swift panel models through a disposable loopback SSH server."""
import functools, http.server, os, pathlib, pwd, shlex, socket, subprocess, tempfile, threading, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='ash-panel-ssh-', dir='/tmp') as temp:
    temp = pathlib.Path(temp)
    for name in ['host', 'client']:
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(temp/name)], check=True)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); ssh_port = sock.getsockname()[1]
    config = temp/'sshd_config'
    config.write_text(f'''Port {ssh_port}
ListenAddress 127.0.0.1
HostKey {temp}/host
PidFile {temp}/sshd.pid
AuthorizedKeysFile {temp}/client.pub
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
LogLevel ERROR
''')
    public = (temp/'host.pub').read_text().split()
    (temp/'known_hosts').write_text(f'[127.0.0.1]:{ssh_port} {public[0]} {public[1]}\n')
    client = temp/'ssh_config'
    client.write_text(f'''Host ash-panel-fixture
  HostName 127.0.0.1
  User {pwd.getpwuid(os.getuid()).pw_name}
  Port {ssh_port}
  IdentityFile {temp}/client
  IdentitiesOnly yes
  UserKnownHostsFile {temp}/known_hosts
  StrictHostKeyChecking yes
''')
    wrapper = temp/'runtime'
    wrapper.write_text('#!/bin/sh\nexport ASH_RUNTIME_HOME='+shlex.quote(str(temp/'state'))+'\nexec '+shlex.quote(str(ROOT/'runtime/target/debug/ash-runtime'))+' request\n')
    wrapper.chmod(0o755)
    (temp/'index.html').write_text('<html><body>PANEL_SSH_OK</body></html>')
    http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(temp)))
    threading.Thread(target=http.serve_forever, daemon=True).start()
    log = open(temp/'sshd.log', 'w+')
    ssh = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], stderr=log)
    try:
        time.sleep(.3)
        if ssh.poll() is not None:
            log.seek(0); raise RuntimeError(log.read())
        executable = temp/'checks'
        subprocess.run([str(ROOT/'scripts/swift-check.sh'), 'SidePanelChecks', str(executable)], check=True)
        env = dict(os.environ, ASH_SSH_CONFIG=str(client), ASH_PANEL_TEST_PORT=str(http.server_port), ASH_PANEL_TEST_DIRECTORY=str(temp), ASH_PANEL_TEST_RUNTIME=str(wrapper))
        subprocess.run([str(executable)], env=env, check=True, timeout=40)
        directories = temp/'directory-checks'
        subprocess.run([str(ROOT/'scripts/swift-check.sh'), 'DirectorySuggestionsChecks', str(directories)], check=True)
        subprocess.run([str(directories)], env=dict(env, ASH_DIRECTORY_REMOTE='ash-panel-fixture', ASH_DIRECTORY_PATH=str(temp)), check=True, timeout=40)
    finally:
        http.shutdown(); http.server_close()
        ssh.terminate(); ssh.wait(timeout=5); log.close()
