//! Persisted records and protocol payloads. Keep serialized field names compatible.
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Run {
    pub(crate) id: String,
    pub(crate) task_id: String,
    pub(crate) workspace_id: String,
    pub(crate) title: String,
    pub(crate) agent: String,
    pub(crate) prompt: String,
    pub(crate) cwd: String,
    pub(crate) session: String,
    pub(crate) status: String,
    pub(crate) created_at: f64,
    pub(crate) exit_code: Option<i32>,
    pub(crate) error: Option<String>,
    pub(crate) base_commit: Option<String>,
    #[serde(default)]
    pub(crate) arguments: Vec<String>,
    #[serde(default)]
    pub(crate) archived: bool,
}
#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Workspace {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) path: String,
    pub(crate) branch: Option<String>,
    #[serde(default)]
    pub(crate) split: bool,
    pub(crate) selected_run_id: Option<String>,
    pub(crate) secondary_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) pane_run_ids: Option<Vec<String>>,
    #[serde(default)]
    pub(crate) archived: bool,
}

impl Run {
    pub(crate) fn is_live(&self) -> bool {
        matches!(self.status.as_str(), "starting" | "running")
    }

    pub(crate) fn is_active(&self) -> bool {
        self.status == "queued" || self.is_live()
    }
}
