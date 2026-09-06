# Third-party notices

Ash's own source is licensed under MIT. Third-party components retain their original licenses and copyright notices.

## Terminal and bundled tools

| Component | Role | License text |
| --- | --- | --- |
| [SwiftTerm 1.20.0](https://github.com/migueldeicaza/SwiftTerm) | Native terminal rendering | [MIT](docs/licenses/SwiftTerm.txt) |
| [Swift Argument Parser 1.8.2](https://github.com/apple/swift-argument-parser) | Swift package build tooling | [Apache 2.0 with Swift exception](docs/licenses/Swift-Argument-Parser.txt) |
| [tmux 3.6a](https://github.com/tmux/tmux) | Managed remote sessions | [Upstream COPYING](docs/licenses/tmux.txt) |
| [libevent 2.1.12](https://libevent.org/) | Static tmux dependency | [Upstream LICENSE](docs/licenses/libevent.txt) |
| [ncurses 6.5](https://invisible-island.net/ncurses/) | Terminal capabilities | [Upstream COPYING](docs/licenses/ncurses.txt) |
| [musl](https://musl.libc.org/) | Static Linux C library, supplied by the cross toolchain | [Upstream COPYRIGHT](docs/licenses/musl.txt) |

SQLite 3.46.0 is bundled through `libsqlite3-sys`; SQLite's original code is [public domain](https://sqlite.org/copyright.html). The Rust bindings retain their MIT license in the notices below. OpenSSH and system Git are invoked from the host installation rather than redistributed by Ash. Coding agent CLIs are installed separately by users.

## Rust dependencies

The following inventory comes from the resolved Cargo dependency graph, including build-time and optional crates. Complete upstream license texts are preserved in [Rust-dependencies.txt](docs/licenses/Rust-dependencies.txt). Windows-only import archives are not shipped in Ash's macOS/Linux products.

| Package | Version | Declared license |
| --- | --- | --- |
| ahash | 0.8.12 | MIT OR Apache-2.0 |
| anyhow | 1.0.104 | MIT OR Apache-2.0 |
| bitflags | 2.13.1 | MIT OR Apache-2.0 |
| cc | 1.4.5 | MIT OR Apache-2.0 |
| cfg-if | 1.0.4 | MIT OR Apache-2.0 |
| fallible-iterator | 0.3.0 | MIT/Apache-2.0 |
| fallible-streaming-iterator | 0.1.9 | MIT/Apache-2.0 |
| find-msvc-tools | 0.1.12 | MIT OR Apache-2.0 |
| fs2 | 0.4.3 | MIT/Apache-2.0 |
| hashbrown | 0.14.5 | MIT OR Apache-2.0 |
| hashlink | 0.9.1 | MIT OR Apache-2.0 |
| itoa | 1.0.18 | MIT OR Apache-2.0 |
| libc | 0.2.189 | MIT OR Apache-2.0 |
| libsqlite3-sys | 0.30.1 | MIT |
| memchr | 2.8.3 | Unlicense OR MIT |
| once_cell | 1.21.4 | MIT OR Apache-2.0 |
| pkg-config | 0.3.34 | MIT OR Apache-2.0 |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 |
| quote | 1.0.47 | MIT OR Apache-2.0 |
| rusqlite | 0.32.1 | MIT |
| serde | 1.0.229 | MIT OR Apache-2.0 |
| serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 |
| serde_json | 1.0.151 | MIT OR Apache-2.0 |
| shlex | 2.0.1 | MIT OR Apache-2.0 |
| smallvec | 1.16.0 | MIT OR Apache-2.0 |
| syn | 2.0.119 | MIT OR Apache-2.0 |
| syn | 3.0.5 | MIT OR Apache-2.0 |
| unicode-ident | 1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| vcpkg | 0.2.15 | MIT/Apache-2.0 |
| version_check | 0.9.5 | MIT/Apache-2.0 |
| winapi | 0.3.9 | MIT/Apache-2.0 |
| zerocopy | 0.8.56 | BSD-2-Clause OR Apache-2.0 OR MIT |
| zerocopy-derive | 0.8.56 | BSD-2-Clause OR Apache-2.0 OR MIT |
| zmij | 1.0.23 | MIT |

When updating dependencies, regenerate this inventory and preserve their license texts in release bundles.
