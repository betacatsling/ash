//! Managed session lifecycle. Mutations run under the runtime lock; execution releases it while the child runs.
use crate::{
    models::Run,
    runtime::Runtime,
    support::{quote, resolve},
};
use anyhow::{anyhow, Result};
use std::{
    env, fs,
    os::unix::process::CommandExt,
    process::{Command, Stdio},
};

impl Runtime {
    pub(crate) fn launch(&self, r: &mut Run) -> Result<()> {
        r.status = "starting".into();
        self.save(r)?;
        let executable = env::current_exe()?;
        let cmd = format!(
            "ASH_RUNTIME_HOME={} {} execute {}",
            quote(&self.root.to_string_lossy()),
            quote(&executable.to_string_lossy()),
            quote(&r.id)
        );
        let result = self.tm(&[
            "new-session",
            "-d",
            "-s",
            &r.session,
            "-x",
            "120",
            "-y",
            "35",
            "-c",
            &r.cwd,
            &cmd,
        ]);
        match result {
            Ok(_) => {
                r.status = "running".into();
            }
            Err(e) => {
                r.status = "failedToStart".into();
                r.error = Some(e.to_string());
            }
        }
        self.save(r)
    }

    pub(crate) fn ensure_worker(&self) -> Result<()> {
        if self.tm(&["has-session", "-t", "=ash-scheduler"]).is_ok() {
            // A dead worker pane must not prevent restarting the scheduler.
            let owner = self
                .tm(&["show-options", "-v", "-t", "ash-scheduler", "@ash-runtime"])
                .unwrap_or_default();
            if self
                .tm(&[
                    "display-message",
                    "-p",
                    "-t",
                    "ash-scheduler:0.0",
                    "#{pane_dead}",
                ])
                .unwrap_or_default()
                == "0"
                && owner == env::current_exe()?.to_string_lossy()
            {
                return Ok(());
            }
            let _ = self.tm(&["kill-session", "-t", "=ash-scheduler"]);
        }
        let cmd = format!(
            "ASH_RUNTIME_HOME={} {} worker",
            quote(&self.root.to_string_lossy()),
            quote(&env::current_exe()?.to_string_lossy())
        );
        self.tm(&["new-session", "-d", "-s", "ash-scheduler", &cmd])?;
        self.tm(&[
            "set-option",
            "-t",
            "ash-scheduler",
            "@ash-runtime",
            &env::current_exe()?.to_string_lossy(),
        ])?;
        Ok(())
    }

    pub(crate) fn tick(&self) -> Result<()> {
        let mut all = self.all()?;
        for r in all.iter_mut().filter(|r| r.is_live()) {
            if self
                .tm(&["has-session", "-t", &format!("={}", r.session)])
                .is_err()
            {
                r.status = "lost".into();
                r.error = Some("The managed session no longer exists".into());
                self.save(r)?;
                continue;
            }
            let target = format!("={}:0.0", r.session);
            match self.tm(&[
                "display-message",
                "-p",
                "-t",
                &target,
                "#{pane_dead}|#{pane_dead_status}",
            ]) {
                Ok(s) if s.starts_with("1|") => {
                    r.status = "lost".into();
                    r.error = Some("Session wrapper exited without a final result".into());
                    self.save(r)?;
                }
                Err(_) => {
                    r.status = "lost".into();
                    r.error = Some("The managed session no longer exists".into());
                    self.save(r)?;
                }
                _ => {
                    if r.status == "starting" {
                        r.status = "running".into();
                        self.save(r)?;
                    }
                }
            }
        }
        let active = all
            .iter()
            .filter(|r| r.is_live() && r.agent != "shell")
            .count();
        for r in all
            .iter_mut()
            .filter(|r| r.status == "queued")
            .take(self.limit().saturating_sub(active))
        {
            self.launch(r)?;
        }
        Ok(())
    }

    pub(crate) fn execute(&self, id: &str) -> Result<()> {
        let mut r = {
            let _lock = self.lock()?;
            self.get(id)?
        };
        let mut c = match r.agent.as_str() {
            "shell" => {
                let mut c = Command::new(env::var("SHELL").unwrap_or("/bin/sh".into()));
                c.arg("-l");
                c
            }
            "command" => {
                let (exe, args) = r
                    .arguments
                    .split_first()
                    .ok_or_else(|| anyhow!("Missing command arguments"))?;
                let mut c = Command::new(exe);
                c.args(args);
                c
            }
            name => {
                let mut c =
                    Command::new(resolve(name).ok_or_else(|| anyhow!("Agent is unavailable"))?);
                if !r.prompt.is_empty() {
                    c.arg("--").arg(&r.prompt);
                }
                c
            }
        };
        // Keep the supervisor alive when the interactive agent receives Ctrl-C.
        unsafe {
            libc::signal(libc::SIGINT, libc::SIG_IGN);
            libc::signal(libc::SIGQUIT, libc::SIG_IGN);
            c.pre_exec(|| {
                libc::signal(libc::SIGINT, libc::SIG_DFL);
                libc::signal(libc::SIGQUIT, libc::SIG_DFL);
                Ok(())
            });
        }
        crate::terminal_environment::configure(&mut c);
        let result = c
            .current_dir(&r.cwd)
            .env("ASH_RUN_ID", &r.id)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
        match result {
            Ok(status) => {
                r.status = "exited".into();
                r.exit_code = status.code();
            }
            Err(e) => {
                r.status = "failedToStart".into();
                r.error = Some(e.to_string());
                eprintln!("Ash: {e}");
            }
        }
        {
            let _lock = self.lock()?;
            if self.get(id)?.status != "cancelled" {
                self.save(&r)?;
            }
        }
        if let Ok(log) = self.tm(&[
            "capture-pane",
            "-p",
            "-t",
            &format!("={}:0.0", r.session),
            "-S",
            "-2000",
        ]) {
            fs::create_dir_all(self.root.join("logs"))?;
            fs::write(self.root.join("logs").join(format!("{id}.txt")), log)?;
        }
        println!(
            "\r\n[Ash · process exited{} · results are ready to inspect]",
            r.exit_code.map(|c| format!(" ({c})")).unwrap_or_default()
        );
        Ok(())
    }
}
