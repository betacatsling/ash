#!/usr/bin/env python3
import hashlib, json, pathlib, struct, subprocess, tarfile, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
directory = ROOT/'dist/runtime-packages'
manifest = json.loads((directory/'manifest.json').read_text())
version = next(line.split('"')[1] for line in (ROOT/'runtime/Cargo.toml').read_text().splitlines() if line.startswith('version ='))
assert manifest['version'] == version and manifest['protocol'] == 1
assert {p['target'] for p in manifest['packages']} == {'macos-aarch64','macos-x86_64','linux-aarch64','linux-x86_64'}
for package in manifest['packages']:
    data = (directory/package['file']).read_bytes()
    assert len(data) == package['size'] and hashlib.sha256(data).hexdigest() == package['sha256']
    with tarfile.open(directory/package['file']) as archive:
        members = archive.getmembers()
        assert all(not m.issym() and not m.islnk() and not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts for m in members)
        assert all(any(m.name == name for m in members) for name in ['bin/ash-runtime','bin/tmux','licenses/tmux.txt'])
        assert any(m.name.endswith('/xterm-256color') for m in members)
        for name in ['bin/ash-runtime','bin/tmux']:
            binary = archive.extractfile(name).read()
            if package['target'].startswith('linux'):
                assert binary[:6] == b'\x7fELF\x02\x01'
                machine = struct.unpack_from('<H', binary, 18)[0]
                assert machine == (183 if package['target'].endswith('aarch64') else 62)
                offset = struct.unpack_from('<Q', binary, 32)[0]
                size, count = struct.unpack_from('<HH', binary, 54)
                assert all(struct.unpack_from('<I', binary, offset+i*size)[0] != 3 for i in range(count)), 'Linux binary must not require a system dynamic loader'
            else:
                with tempfile.NamedTemporaryFile() as f:
                    f.write(binary); f.flush()
                    deps = subprocess.check_output(['/usr/bin/otool','-L',f.name], text=True).splitlines()[1:]
                    assert all(line.strip().startswith(('/usr/lib/', '/System/Library/')) for line in deps), deps
print('PASS all 4 bundled packages: digest, size, safe archive paths, architecture, static Linux binaries and portable macOS dependencies')
