//! Protocol routing. Read-only panel and agent inspection bypass the scheduler lock.
use crate::{
    agent_tasks,
    models::{Run, Workspace},
    panel,
    runtime::Runtime,
    support::{now, required, resolve, truncate, valid_id},
    PROTOCOL,
};
use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Value};
use std::{env, fs, thread, time::Duration};

impl Runtime {
    pub(crate) fn health(&self) -> Value {
        let agents: Vec<Value> = ["pi", "codex", "claude"]
            .iter()
            .map(|n| json!({"id":n, "path":resolve(n).map(|p| p.to_string_lossy().to_string())}))
            .collect();
        json!({"protocol":PROTOCOL,"version":env!("CARGO_PKG_VERSION"),"platform":env::consts::OS,"arch":env::consts::ARCH,"tmux":self.tmux,"socket":self.socket,"root":self.root,"agents":agents,"concurrency":self.limit(),"termInfo":env::var("TERMINFO_DIRS").ok(),"capabilities":["workspace-registry","managed-sessions"]})
    }

    pub(crate) fn handle(&self, v: Value) -> Result<Value> {
        if v["protocol"].as_u64() != Some(PROTOCOL as u64) {
            bail!("Unsupported protocol; update Ash and ash-runtime together");
        }
        // Agent inspection is read-only and must not hold the scheduler lock.
        if v["action"] == "agentTasks" {
            return agent_tasks::inspect(self, &self.get(&required(&v, "id")?)?);
        }
        let action = required(&v, "action")?;
        if ["browseFiles", "readFile", "reviewFiles", "reviewDiff"].contains(&action.as_str()) {
            return panel::request(&action, &v);
        }
        let _lock = self.lock()?;
        match action.as_str() {
            "health" => Ok(self.health()),
            "list" => self.list_runs(),
            "workspace" => self.update_workspace(&v),
            "start" => self.start_run(&v),
            "cancel" => self.cancel_run(&v),
            "archive" => self.archive_run(&v),
            "changes" => self.changes(&v),
            "worktree" => self.create_worktree(&v),
            "settings" => self.update_settings(&v),
            "transcript" => self.transcript(&v),
            _ => bail!("Unknown action"),
        }
    }

    fn list_runs(&self) -> Result<Value> {
        self.tick()?;
        if self.all()?.iter().any(|r| r.status == "queued") {
            self.ensure_worker()?;
        }
        self.recover_workspaces()?;
        Ok(json!({"runs":self.all()?,"workspaces":self.workspaces()?,"concurrency":self.limit()}))
    }

    fn update_workspace(&self, v: &Value) -> Result<Value> {
        let w: Workspace = serde_json::from_value(v["workspace"].clone())?;
        self.save_workspace(&w)?;
        Ok(json!(w))
    }

    fn start_run(&self, v: &Value) -> Result<Value> {
        let id = required(v, "id")?;
        if !valid_id(&id) {
            bail!("Invalid run ID");
        }
        if let Ok(existing) = self.get(&id) {
            return Ok(json!(existing));
        }
        let cwd =
            fs::canonicalize(required(v, "cwd")?).context("Workspace directory is unavailable")?;
        if !cwd.is_dir() {
            bail!("Workspace must be a directory");
        }
        let agent = required(v, "agent")?;
        if !["shell", "pi", "codex", "claude", "command"].contains(&agent.as_str()) {
            bail!("Unsupported agent");
        }
        if ["pi", "codex", "claude"].contains(&agent.as_str()) && resolve(&agent).is_none() {
            bail!("{agent} is not installed on this host or not on PATH");
        }
        let task_id = v["taskId"].as_str().unwrap_or(&id).to_string();
        let mut r = Run {
            session: format!("ash-{id}"),
            id,
            task_id,
            workspace_id: required(v, "workspaceId")?,
            title: required(v, "title")?,
            agent,
            prompt: v["prompt"].as_str().unwrap_or_default().into(),
            cwd: cwd.to_string_lossy().to_string(),
            status: "queued".into(),
            created_at: now(),
            exit_code: None,
            error: None,
            base_commit: self
                .git(&cwd.to_string_lossy(), &["rev-parse", "HEAD"])
                .ok(),
            arguments: serde_json::from_value(v["arguments"].clone()).unwrap_or_default(),
            archived: false,
        };
        self.save(&r)?;
        if r.agent == "shell" {
            self.launch(&mut r)?;
        } else {
            self.ensure_worker()?;
            self.tick()?;
            r = self.get(&r.id)?;
        }
        Ok(json!(r))
    }

    fn cancel_run(&self, v: &Value) -> Result<Value> {
        let mut r = self.get(&required(v, "id")?)?;
        if !r.is_active() {
            return Ok(json!(r));
        }
        if r.status != "queued" {
            let target = format!("={}:0.0", r.session);
            self.tm(&["has-session", "-t", &format!("={}", r.session)])?;
            let pane = self.tm(&[
                "display-message",
                "-p",
                "-t",
                &target,
                "#{pane_dead}|#{pane_pid}",
            ])?;
            let (dead, pid) = pane
                .split_once('|')
                .ok_or_else(|| anyhow!("Unable to identify the managed process"))?;
            if dead == "0" {
                let pid: i32 = pid.parse()?;
                if pid <= 1 || unsafe { libc::getpgid(pid) } != pid {
                    bail!("Unable to verify the managed process group");
                }
                // Only the live tmux-owned group is eligible. Escalate for programs that ignore TERM.
                unsafe {
                    libc::kill(-pid, libc::SIGTERM);
                }
                thread::sleep(Duration::from_millis(150));
                if unsafe { libc::kill(-pid, 0) } == 0 {
                    unsafe {
                        libc::kill(-pid, libc::SIGKILL);
                    }
                }
            }
            self.tm(&["kill-session", "-t", &format!("={}", r.session)])?;
        }
        r.status = "cancelled".into();
        self.save(&r)?;
        self.tick()?;
        Ok(json!(r))
    }

    fn archive_run(&self, v: &Value) -> Result<Value> {
        let mut r = self.get(&required(v, "id")?)?;
        if r.is_active() {
            bail!("Stop the session before archiving it");
        }
        let _ = self.tm(&["kill-session", "-t", &format!("={}", r.session)]);
        r.archived = true;
        self.save(&r)?;
        Ok(json!(r))
    }

    fn changes(&self, v: &Value) -> Result<Value> {
        let cwd = required(v, "cwd")?;
        let base = v["base"]
            .as_str()
            .filter(|s| s.len() >= 7 && s.len() <= 64 && s.bytes().all(|c| c.is_ascii_hexdigit()));
        let branch = self.git(&cwd, &["branch", "--show-current"])?;
        let status = self.git(&cwd, &["status", "--short"])?;
        let diff = self.git(
            &cwd,
            &[
                "diff",
                "--no-ext-diff",
                "--no-textconv",
                base.unwrap_or("HEAD"),
                "--",
            ],
        )?;
        let untracked = self.git(&cwd, &["ls-files", "--others", "--exclude-standard"])?;
        Ok(
            json!({"branch":branch,"status":status,"diff":truncate(&diff,200_000),"untracked":untracked,"truncated":diff.len()>200_000}),
        )
    }

    fn create_worktree(&self, v: &Value) -> Result<Value> {
        let cwd = required(v, "cwd")?;
        let id = required(v, "id")?;
        if !valid_id(&id) {
            bail!("Invalid workspace ID");
        }
        let branch = format!("ash/{id}");
        let dest = self.root.join("worktrees").join(&id);
        if dest.exists() {
            bail!("Worktree already exists; select it from your workspaces");
        }
        fs::create_dir_all(dest.parent().unwrap())?;
        let base = self.git(&cwd, &["rev-parse", "HEAD"])?;
        self.git(
            &cwd,
            &[
                "worktree",
                "add",
                "-b",
                &branch,
                &dest.to_string_lossy(),
                &base,
            ],
        )?;
        Ok(json!({"path":dest,"branch":branch,"base":base}))
    }

    fn update_settings(&self, v: &Value) -> Result<Value> {
        let n = v["concurrency"]
            .as_u64()
            .filter(|n| (1..=16).contains(n))
            .ok_or_else(|| anyhow!("Concurrency must be 1–16"))?;
        self.db.execute("INSERT INTO settings(key,value) VALUES('concurrency',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value",[n.to_string()])?;
        self.tick()?;
        Ok(json!({"concurrency":n}))
    }

    fn transcript(&self, v: &Value) -> Result<Value> {
        let r = self.get(&required(v, "id")?)?;
        let text = self
            .tm(&[
                "capture-pane",
                "-p",
                "-t",
                &format!("={}:0.0", r.session),
                "-S",
                "-2000",
            ])
            .or_else(|_| {
                fs::read_to_string(self.root.join("logs").join(format!("{}.txt", r.id)))
                    .map_err(anyhow::Error::from)
            })
            .unwrap_or_default();
        Ok(json!({"text":text}))
    }
}
