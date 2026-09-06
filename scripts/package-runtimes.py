#!/usr/bin/env python3
"""Create the trusted per-platform packages shipped inside Ash.app."""
import hashlib, json, pathlib, shutil, subprocess, tarfile, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
version = next(line.split('"')[1] for line in (ROOT/'runtime/Cargo.toml').read_text().splitlines() if line.startswith('version ='))
targets = {
    'macos-aarch64': 'aarch64-apple-darwin',
    'macos-x86_64': 'x86_64-apple-darwin',
    'linux-aarch64': 'aarch64-unknown-linux-musl',
    'linux-x86_64': 'x86_64-unknown-linux-musl',
}
output = ROOT/'dist/runtime-packages'
output.mkdir(parents=True, exist_ok=True)
manifest = dict(format=1, version=version, protocol=1, packages=[])
for target, triple in targets.items():
    runtime = ROOT/'runtime/target'/triple/'release/ash-runtime'
    portable = ROOT/'.build/portable'/target/'install'
    if not runtime.is_file() or not (portable/'bin/tmux').is_file():
        raise SystemExit(f'Missing {target} binaries; run scripts/build-runtime-packages.sh first')
    with tempfile.TemporaryDirectory(prefix='ash-package-') as directory:
        stage = pathlib.Path(directory)
        (stage/'bin').mkdir()
        shutil.copy2(runtime, stage/'bin/ash-runtime')
        shutil.copy2(portable/'bin/tmux', stage/'bin/tmux')
        shutil.copytree(portable/'licenses', stage/'licenses')
        shutil.copy2(ROOT/'LICENSE', stage/'licenses/Ash.txt')
        for notice in ['Rust-dependencies.txt', 'musl.txt']:
            shutil.copy2(ROOT/'docs/licenses'/notice, stage/'licenses'/notice)
        for term in ['xterm-256color', 'screen-256color', 'tmux-256color']:
            termcap = subprocess.run(['/usr/bin/infocmp', term], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            if termcap.returncode == 0:
                subprocess.run(['/usr/bin/tic', '-x', '-o', str(stage/'terminfo'), '-'], input=termcap.stdout, check=True)
        if target.startswith('macos'):
            for binary in (stage/'bin').iterdir(): subprocess.run(['codesign','--force','--sign','-',str(binary)],check=True)
        filename = f'ash-runtime-{version}-{target}.tar.gz'
        def public_metadata(member):
            member.uid = member.gid = 0
            member.uname = member.gname = ''
            return member
        with tarfile.open(output/filename, 'w:gz') as archive:
            for name in ['bin', 'licenses', 'terminfo']: archive.add(stage/name, arcname=name, filter=public_metadata)
    data = (output/filename).read_bytes()
    manifest['packages'].append(dict(target=target, file=filename, sha256=hashlib.sha256(data).hexdigest(), size=len(data)))
(output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(f'Packaged {len(targets)} platforms, runtime {version}')
