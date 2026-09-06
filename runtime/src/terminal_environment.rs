//! Interactive processes must not inherit output policy from the GUI launcher,
//! a non-interactive SSH request, or a long-lived tmux server. This mirrors
//! Sources/Ash/TerminalEnvironment.swift. User shell startup files and explicit
//! per-command environment assignments still run after this boundary.
use std::process::Command;

pub(crate) fn configure(command: &mut Command) {
    for key in ["NO_COLOR", "FORCE_COLOR", "CLICOLOR_FORCE"] {
        command.env_remove(key);
    }
    command
        .env("TERM", "xterm-256color")
        .env("COLORTERM", "truecolor")
        .env("CLICOLOR", "1")
        .env("TERM_PROGRAM", "Ash")
        .env("TERM_PROGRAM_VERSION", env!("CARGO_PKG_VERSION"));
}
