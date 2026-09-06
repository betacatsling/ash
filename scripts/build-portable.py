#!/usr/bin/env python3
"""Build pinned tmux + static private dependencies; never installs on the host system."""
import hashlib, os, pathlib, shutil, subprocess, sys, tarfile, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = sys.argv[1]
SPECS = {
    'linux-x86_64': ('x86_64-linux-musl', 'x86_64-linux'),
    'linux-aarch64': ('aarch64-linux-musl', 'aarch64-linux'),
    'macos-x86_64': ('x86_64-apple-darwin', 'x86_64-apple-darwin'),
    'macos-aarch64': ('arm64-apple-darwin', 'aarch64-apple-darwin'),
}
triple, host = SPECS[TARGET]
work = ROOT / '.build/portable' / TARGET
prefix = work / 'install'
work.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
compiler = work / 'cc'
if TARGET.startswith('linux'):
    zig = next((ROOT / '.tools/cross/lib').rglob('ziglang/zig'))
    compiler.write_text(f'#!/bin/sh\nexec "{zig}" cc -target {triple} "$@"\n')
    env['AR'] = str(work / 'ar')
    (work / 'ar').write_text(f'#!/bin/sh\nexec "{zig}" ar "$@"\n')
    (work / 'ar').chmod(0o755)
    env['RANLIB'] = str(work / 'ranlib')
    (work / 'ranlib').write_text(f'#!/bin/sh\nexec "{zig}" ranlib "$@"\n')
    (work / 'ranlib').chmod(0o755)
else:
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    compiler.write_text(f'#!/bin/sh\nexec /usr/bin/clang -target {triple} -isysroot "{sdk}" -mmacosx-version-min=12.0 "$@"\n')
compiler.chmod(0o755)
env.update(CC=str(compiler), CFLAGS='-O2', PKG_CONFIG='/usr/bin/false')

def build(name, options, extra=None):
    archive = ROOT / '.tools' / (name + '.tar.gz')
    sources = {
        'tmux-3.6a': ('https://github.com/tmux/tmux/releases/download/3.6a/tmux-3.6a.tar.gz', 'b6d8d9c76585db8ef5fa00d4931902fa4b8cbe8166f528f44fc403961a3f3759'),
        'libevent-2.1.12-stable': ('https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz', '92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb'),
        'ncurses-6.5': ('https://ftp.gnu.org/gnu/ncurses/ncurses-6.5.tar.gz', '136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6'),
    }
    url, checksum = sources[name]
    if not archive.exists(): urllib.request.urlretrieve(url, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum: raise SystemExit('Source checksum mismatch: ' + name)
    source = work / name
    if not source.exists():
        with tarfile.open(archive) as f: f.extractall(work)
    runenv = dict(env, **(extra or {}))
    with (work / (name + '.log')).open('w') as log:
        for args in [['./configure', '--prefix=' + str(prefix), '--host=' + host, *options], ['make', '-j4'], ['make', 'install']]:
            result = subprocess.run(args, cwd=source, env=runenv, stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                log.flush(); print((work / (name + '.log')).read_text()[-5000:]); sys.exit(result.returncode)

build('libevent-2.1.12-stable', ['--disable-shared', '--enable-static', '--disable-openssl', '--disable-libevent-regress', '--disable-samples', '--disable-doxygen', '--disable-thread-support'])
build('ncurses-6.5', ['--without-shared', '--without-debug', '--enable-widec', '--with-termlib', '--without-progs', '--without-tests', '--without-cxx', '--without-cxx-binding', '--without-ada', '--without-manpages', '--disable-db-install', '--without-dlsym'])
build('tmux-3.6a', ['--disable-utf8proc', '--disable-utempter', '--disable-systemd'], {
    'LIBEVENT_CFLAGS': '-I' + str(prefix / 'include'),
    'LIBEVENT_LIBS': str(prefix / 'lib/libevent_core.a'),
    'LIBTINFO_CFLAGS': '-I' + str(prefix / 'include/ncursesw'),
    'LIBTINFO_LIBS': str(prefix / 'lib/libtinfow.a'),
    'LDFLAGS': '-static' if TARGET.startswith('linux') else '',
})
licenses = prefix / 'licenses'
licenses.mkdir(exist_ok=True)
for name, path in [('tmux', 'tmux-3.6a/COPYING'), ('libevent', 'libevent-2.1.12-stable/LICENSE'), ('ncurses', 'ncurses-6.5/COPYING')]:
    shutil.copyfile(work / path, licenses / (name + '.txt'))
print('Built portable tmux: ' + str(prefix / 'bin/tmux'))
