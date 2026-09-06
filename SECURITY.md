# Security

Ash runs local commands and uses your SSH connections. It is currently a developer preview; it should not be treated as a sandbox for untrusted code.

## Reporting a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/betacatsling/ash/security/advisories/new) for security issues. Do not publish credentials, usable exploits against a real host, SSH configuration, or private session transcripts in a public issue.

Include the affected version, a minimal reproduction using test data, the expected security boundary, and the observed impact. A response-time commitment is not currently available.

## Current boundaries

- Worktrees separate files, not process permissions, networks, ports, or databases.
- Agent authentication and approval settings are controlled by the agent CLI.
- Remote installation runs as the authenticated SSH user and uses bundled package checksums. A checksum alone does not establish a download's authenticity.
- Preview binaries use ad-hoc signing and are not notarized.
- Execution records and terminal output can contain sensitive information. Review them before sharing.

Only the current development line is maintained; there is no separate long-term security support branch.
