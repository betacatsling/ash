#!/usr/bin/env python3
"""Color regression through real runtime -> persistent tmux -> PTY -> program."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get('ASH_TEST_RUNTIME', ROOT / 'runtime/target/debug/ash-runtime'))
TMUX = shutil.which('tmux')


def main():
    with tempfile.TemporaryDirectory(prefix='ash-color-', dir='/tmp') as directory:
        root = Path(directory)
        state = root / 'state'
        state.mkdir()
        socket = str(state / 't.sock')
        # Simulate a server created by the old application. It outlives requests
        # and keeps its poisoned environment even when the caller is now clean.
        polluted = dict(os.environ, NO_COLOR='1', FORCE_COLOR='0', CLICOLOR_FORCE='0',
                        CLICOLOR='0', TERM='dumb', ASH_RUNTIME_HOME=str(state))
        clean = dict(polluted)
        for key in ['NO_COLOR', 'FORCE_COLOR', 'CLICOLOR_FORCE']:
            clean.pop(key, None)

        def tm(*args):
            return subprocess.check_output([TMUX, '-S', socket, *args], env=clean).decode()

        def request(action, **values):
            raw = subprocess.check_output([str(BIN), 'request'], env=clean,
                input=json.dumps(dict(protocol=1, action=action, **values)).encode())
            result = json.loads(raw)
            assert result['ok'], result
            return result['data']

        def start(command):
            run = request('start', id=str(uuid.uuid4()), workspaceId='colors', cwd=str(root),
                          title='Color regression', agent='command', arguments=['/bin/sh', '-c', command])
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                current = next(r for r in request('list')['runs'] if r['id'] == run['id'])
                if current['status'] == 'exited':
                    assert current['exitCode'] == 0, current
                    return run
                time.sleep(.1)
            raise AssertionError(current)

        try:
            subprocess.run([TMUX, '-S', socket, '-f', '/dev/null', 'new-session', '-d',
                            '-s', 'legacy', 'sleep 120'], env=polluted, check=True)
            server_pid = tm('display-message', '-p', '#{pid}').strip()
            assert 'NO_COLOR=1' in tm('show-environment', '-g', 'NO_COLOR')
            probe = root / 'probe.py'
            probe.write_text('''import json, os
from pathlib import Path
keys = ['NO_COLOR', 'FORCE_COLOR', 'CLICOLOR_FORCE', 'CLICOLOR', 'TERM', 'COLORTERM', 'TERM_PROGRAM']
Path('environment.json').write_text(json.dumps(dict(env={k: os.getenv(k) for k in keys}, tty=[os.isatty(i) for i in range(3)])))
print('\\x1b[31mANSI_RED\\x1b[0m \\x1b[38;5;196mINDEXED_RED\\x1b[0m \\x1b[38;2;12;180;240mRGB_CYAN\\x1b[0m', flush=True)
''')
            run = start(f'{shlex.quote(shutil.which("python3"))} {shlex.quote(str(probe))}')
            result = json.loads((root / 'environment.json').read_text())
            assert result['tty'] == [True, True, True], result
            assert result['env'] == dict(NO_COLOR=None, FORCE_COLOR=None, CLICOLOR_FORCE=None,
                CLICOLOR='1', TERM='xterm-256color', COLORTERM='truecolor', TERM_PROGRAM='Ash'), result
            pane = tm('capture-pane', '-e', '-p', '-S', '-2000', '-t', '=' + run['session'] + ':0.0')
            assert '\x1b[31mANSI_RED' in pane, repr(pane)
            assert '\x1b[38;5;196mINDEXED_RED' in pane, repr(pane)
            assert '\x1b[38;2;12;180;240mRGB_CYAN' in pane, repr(pane)
            assert tm('display-message', '-p', '#{pid}').strip() == server_pid
            assert 'NO_COLOR=1' in tm('show-environment', '-g', 'NO_COLOR')
            print('PASS stale tmux environment cannot suppress colors; ANSI, indexed and RGB survive the PTY')

            start("NO_COLOR=1 /bin/sh -c 'printf %s \"$NO_COLOR\"' > explicit-preference")
            assert (root / 'explicit-preference').read_text() == '1'
            print('PASS explicit per-command color preferences still work')

            fastfetch = shutil.which('fastfetch')
            if fastfetch:
                args = shlex.quote(fastfetch) + ' --config none --structure OS:Shell:Colors'
                colored = start(args)
                monochrome = start('NO_COLOR=1 ' + args)
                colored = tm('capture-pane', '-e', '-p', '-S', '-2000', '-t', '=' + colored['session'] + ':0.0')
                monochrome = tm('capture-pane', '-e', '-p', '-S', '-2000', '-t', '=' + monochrome['session'] + ':0.0')
                foreground = r'\x1b\[(?:[0-9;]*;)?(?:3[0-7]|9[0-7])m'
                assert re.search(foreground, colored), repr(colored)
                assert not re.search(foreground, monochrome), repr(monochrome)
                assert '\x1b[41m' in monochrome, repr(monochrome)
                print('PASS fastfetch reproduces the screenshot with NO_COLOR and restores colored text without it')
            else:
                print('SKIP optional fastfetch comparison (fastfetch not installed)')
        finally:
            subprocess.run([TMUX, '-S', socket, 'kill-server'], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
