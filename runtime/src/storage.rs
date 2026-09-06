//! SQLite records, events, and workspace recovery.
use crate::{
    models::{Run, Workspace},
    runtime::Runtime,
    support::{now, valid_id},
};
use anyhow::{bail, Context, Result};
use rusqlite::params;
use serde_json::json;
use std::path::Path;

impl Runtime {
    pub(crate) fn all(&self) -> Result<Vec<Run>> {
        let mut s = self.db.prepare("SELECT data FROM runs ORDER BY rowid")?;
        let rows = s.query_map([], |r| r.get::<_, String>(0))?;
        rows.map(|r| Ok(serde_json::from_str(&r?)?)).collect()
    }

    pub(crate) fn get(&self, id: &str) -> Result<Run> {
        let data: String = self
            .db
            .query_row("SELECT data FROM runs WHERE id=?1", [id], |r| r.get(0))
            .context("Unknown run")?;
        Ok(serde_json::from_str(&data)?)
    }

    pub(crate) fn save(&self, r: &Run) -> Result<()> {
        let data = serde_json::to_string(r)?;
        let tx = self.db.unchecked_transaction()?;
        tx.execute("INSERT INTO runs(id,data) VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET data=excluded.data", params![r.id, data])?;
        tx.execute(
            "INSERT INTO events(run_id,data) VALUES(?1,?2)",
            params![r.id, json!({"status": r.status, "at": now()}).to_string()],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub(crate) fn workspaces(&self) -> Result<Vec<Workspace>> {
        let mut s = self
            .db
            .prepare("SELECT data FROM workspaces ORDER BY rowid")?;
        let rows = s.query_map([], |r| r.get::<_, String>(0))?;
        rows.map(|r| Ok(serde_json::from_str(&r?)?)).collect()
    }

    pub(crate) fn save_workspace(&self, w: &Workspace) -> Result<()> {
        if !valid_id(&w.id) || w.name.trim().is_empty() || !Path::new(&w.path).is_absolute() {
            bail!("Workspace requires a valid ID, name and absolute path");
        }
        for id in [&w.selected_run_id, &w.secondary_run_id]
            .into_iter()
            .flatten()
        {
            if !valid_id(id) {
                bail!("Invalid selected session ID");
            }
        }
        if let Some(ids) = &w.pane_run_ids {
            let mut seen = std::collections::HashSet::new();
            if ids.iter().any(|id| !valid_id(id) || !seen.insert(id)) {
                bail!("Invalid or duplicate pane session ID");
            }
        }
        self.db.execute("INSERT INTO workspaces(id,data) VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET data=excluded.data", params![w.id, serde_json::to_string(w)?])?;
        Ok(())
    }

    pub(crate) fn recover_workspaces(&self) -> Result<()> {
        let mut known: Vec<String> = self.workspaces()?.into_iter().map(|w| w.id).collect();
        for r in self.all()?.into_iter().filter(|r| !r.archived) {
            if !known.contains(&r.workspace_id) {
                let w = Workspace {
                    id: r.workspace_id.clone(),
                    name: Path::new(&r.cwd)
                        .file_name()
                        .map(|s| s.to_string_lossy().to_string())
                        .filter(|s| !s.is_empty())
                        .unwrap_or_else(|| "Workspace".into()),
                    path: r.cwd,
                    branch: None,
                    split: false,
                    selected_run_id: Some(r.id),
                    secondary_run_id: None,
                    pane_run_ids: None,
                    archived: false,
                };
                self.save_workspace(&w)?;
                known.push(r.workspace_id);
            }
        }
        Ok(())
    }
}
