//! Runtime resources and the shared lock. Request and worker processes open the same database.
use crate::support::{output, resolve, root};
use anyhow::{anyhow, bail, Result};
use fs2::FileExt;
use rusqlite::Connection;
use std::{env, fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

pub(crate) struct Runtime {
    pub(crate) root: PathBuf,
    pub(crate) db: Connection,
    pub(crate) tmux: PathBuf,
    pub(crate) socket: PathBuf,
}

impl Runtime {
    pub(crate) fn open() -> Result<Self> {
        let root = root();
        fs::create_dir_all(&root)?;
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700))?;
        let db = Connection::open(root.join("state.sqlite"))?;
        db.busy_timeout(Duration::from_secs(8))?;
        db.execute_batch("PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, data TEXT NOT NULL); CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT, data TEXT); CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS workspaces(id TEXT PRIMARY KEY, data TEXT NOT NULL);")?;
        let tmux = env::var("ASH_TMUX")
            .ok()
            .and_then(|p| resolve(&p))
            .or_else(|| resolve("tmux"))
            .ok_or_else(|| {
                anyhow!("tmux is required. Install tmux on this host to use managed sessions.")
            })?;
        // A short, private socket path also works when the application support directory is long.
        let socket = root.join("t.sock");
        if socket.as_os_str().len() > 100 {
            bail!("ASH_RUNTIME_HOME is too long for a Unix socket (use a shorter path)");
        }
        let config = "set -g status off\nset -g remain-on-exit on\nset -g history-limit 20000\nset -g default-terminal 'xterm-256color'\nset -g escape-time 10\nset -g focus-events on\nset -g mouse on\nset -g set-clipboard off\nset -g extended-keys on\nset -as terminal-features ',xterm-256color:RGB:extkeys'\n";
        let changed = fs::read_to_string(root.join("tmux.conf")).unwrap_or_default() != config;
        if changed {
            fs::write(root.join("tmux.conf"), config)?;
        }
        let rt = Self {
            root,
            db,
            tmux,
            socket,
        };
        if changed && rt.socket.exists() {
            let _ = rt.tm(&["source-file", &rt.root.join("tmux.conf").to_string_lossy()]);
        }
        Ok(rt)
    }

    pub(crate) fn lock(&self) -> Result<fs::File> {
        let f = fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(self.root.join("runtime.lock"))?;
        f.lock_exclusive()?;
        Ok(f)
    }

    pub(crate) fn tmux(&self) -> Command {
        let mut c = Command::new(&self.tmux);
        c.args(["-S"])
            .arg(&self.socket)
            .arg("-f")
            .arg(self.root.join("tmux.conf"));
        c
    }

    pub(crate) fn tm(&self, args: &[&str]) -> Result<String> {
        let mut c = self.tmux();
        c.args(args);
        output(c)
    }

    pub(crate) fn git(&self, cwd: &str, args: &[&str]) -> Result<String> {
        let mut c = Command::new("git");
        c.arg("-C")
            .arg(cwd)
            .args(args)
            .env("GIT_TERMINAL_PROMPT", "0");
        output(c)
    }

    pub(crate) fn limit(&self) -> usize {
        self.db
            .query_row(
                "SELECT value FROM settings WHERE key='concurrency'",
                [],
                |r| r.get::<_, String>(0),
            )
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(4)
    }
}
