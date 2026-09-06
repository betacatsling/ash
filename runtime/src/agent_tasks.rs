//! Read-only adapters for agents inside the selected tmux pane. Never associate
//! sessions by cwd or recency: multiple agents can work in the same directory.
#[cfg(not(target_os = "linux"))]
use crate::support::resolve;
use crate::{
    models::Run,
    runtime::Runtime,
    support::{output, valid_id},
};
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    env, fs,
    io::{BufRead, BufReader, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    process::Command,
};

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AgentTask {
    id: String,
    title: String,
    status: String,
    detail: Option<String>,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSession {
    id: String,
    agent: String,
    tasks: Vec<AgentTask>,
    notice: Option<String>,
}

fn task(id: String, title: &Value, status: &Value, detail: &Value) -> Option<AgentTask> {
    let title = title.as_str()?.trim();
    if title.is_empty() {
        return None;
    }
    Some(AgentTask {
        id,
        title: title.chars().take(2000).collect(),
        status: match status.as_str() {
            Some("pending" | "in_progress" | "completed") => status.as_str().unwrap(),
            _ => "unknown",
        }
        .into(),
        detail: detail
            .as_str()
            .filter(|s| !s.is_empty())
            .map(|s| s.chars().take(4000).collect()),
    })
}

// The file may be written while we read it. Ignore incomplete trailing records.
fn records(path: &Path) -> Result<(Vec<Value>, bool)> {
    const LIMIT: u64 = 8 * 1024 * 1024;
    let mut file = fs::File::open(path)?;
    let size = file.metadata()?.len();
    let clipped = size > LIMIT;
    if clipped {
        file.seek(SeekFrom::Start(size - LIMIT))?;
    }
    let mut reader = BufReader::new(file.take(LIMIT));
    let mut line = String::new();
    if clipped {
        reader.read_line(&mut line)?;
        line.clear();
    }
    let mut result = Vec::new();
    while reader.read_line(&mut line)? > 0 {
        if line.ends_with('\n') {
            if let Ok(v) = serde_json::from_str(&line) {
                result.push(v);
            }
        }
        line.clear();
    }
    Ok((result, clipped))
}

fn parse_tasks(agent: &str, records: &[Value]) -> Vec<AgentTask> {
    let mut tasks = BTreeMap::new();
    let mut calls: HashMap<String, (String, Value)> = HashMap::new();
    for record in records {
        if agent == "codex" {
            let p = &record["payload"];
            if record["type"] != "response_item" {
                continue;
            }
            if p["type"] == "function_call"
                && p["name"]
                    .as_str()
                    .is_some_and(|n| n == "update_plan" || n == "functions.update_plan")
            {
                if let (Some(id), Some(args)) = (p["call_id"].as_str(), p["arguments"].as_str()) {
                    if let Ok(args) = serde_json::from_str::<Value>(args) {
                        calls.insert(id.into(), ("update_plan".into(), args));
                    }
                }
            } else if p["type"] == "function_call_output" {
                if let Some((_, args)) = p["call_id"].as_str().and_then(|id| calls.remove(id)) {
                    // Failed calls must not replace the last accepted plan.
                    if !p["output"]
                        .as_str()
                        .is_some_and(|s| s.trim() == "Plan updated")
                    {
                        continue;
                    }
                    if let Some(plan) = args["plan"].as_array() {
                        tasks.clear();
                        for (i, item) in plan.iter().enumerate() {
                            let id = format!("{:04}", i);
                            if let Some(t) =
                                task(id.clone(), &item["step"], &item["status"], &Value::Null)
                            {
                                tasks.insert(id, t);
                            }
                        }
                    }
                }
            }
        } else if let Some(content) = record["message"]["content"].as_array() {
            for block in content {
                if block["type"] == "tool_use" {
                    if let (Some(id), Some(name)) = (block["id"].as_str(), block["name"].as_str()) {
                        if ["TodoWrite", "TaskCreate", "TaskUpdate"].contains(&name) {
                            calls.insert(id.into(), (name.into(), block["input"].clone()));
                        }
                    }
                } else if block["type"] == "tool_result" {
                    let Some((name, input)) = block["tool_use_id"]
                        .as_str()
                        .and_then(|id| calls.remove(id))
                    else {
                        continue;
                    };
                    if block["is_error"] == true {
                        continue;
                    }
                    if name == "TodoWrite" {
                        if let Some(todos) = input["todos"].as_array() {
                            tasks.clear();
                            for (i, item) in todos.iter().enumerate() {
                                let id = format!("{:04}", i);
                                if let Some(t) = task(
                                    id.clone(),
                                    &item["content"],
                                    &item["status"],
                                    &Value::Null,
                                ) {
                                    tasks.insert(id, t);
                                }
                            }
                        }
                    } else if name == "TaskCreate" {
                        let result = match &block["content"] {
                            Value::String(s) => s.clone(),
                            Value::Array(a) => a
                                .iter()
                                .filter_map(|v| v["text"].as_str())
                                .collect::<Vec<_>>()
                                .join("\n"),
                            _ => String::new(),
                        };
                        // Claude returns “Task #N created successfully: …”. Use
                        // the returned ID, never an inferred local counter.
                        if let Some(id) = result
                            .split("Task #")
                            .nth(1)
                            .map(|s| {
                                s.chars()
                                    .take_while(|c| c.is_ascii_digit())
                                    .collect::<String>()
                            })
                            .filter(|s| !s.is_empty())
                        {
                            if let Some(t) = task(
                                id.clone(),
                                &input["subject"],
                                &json!("pending"),
                                &input["description"],
                            ) {
                                tasks.insert(id, t);
                            }
                        }
                    } else if let Some(id) = input["taskId"].as_str() {
                        if input["status"] == "deleted" {
                            tasks.remove(id);
                        } else if let Some(t) = tasks.get_mut(id) {
                            if let Some(s) = input["subject"].as_str() {
                                t.title = s.chars().take(2000).collect();
                            }
                            if let Some(s) = input["status"].as_str() {
                                t.status =
                                    if ["pending", "in_progress", "completed"].contains(&s) {
                                        s
                                    } else {
                                        "unknown"
                                    }
                                    .into();
                            }
                            if let Some(s) = input["description"].as_str() {
                                t.detail = Some(s.chars().take(4000).collect());
                            }
                        }
                    }
                }
            }
        }
    }
    tasks.into_values().collect()
}

#[derive(Debug)]
struct Proc {
    pid: i32,
    parent: i32,
    agent: Option<String>,
}
fn processes(text: &str) -> Vec<Proc> {
    text.lines()
        .filter_map(|line| {
            let mut words = line.split_whitespace();
            let pid = words.next()?.parse().ok()?;
            let parent = words.next()?.parse().ok()?;
            let exe = Path::new(words.next()?).file_name()?.to_str()?;
            let agent = match exe {
                "claude" | "codex" => Some(exe.to_string()),
                "node" | "bun" => {
                    words
                        .next()
                        .and_then(|p| match Path::new(p).file_name()?.to_str()? {
                            "cli.js" if p.contains("claude-code/") => Some("claude".into()),
                            "codex.js" => Some("codex".into()),
                            _ => None,
                        })
                }
                _ => None,
            };
            Some(Proc { pid, parent, agent })
        })
        .collect()
}
fn descendants(root: i32, procs: &[Proc]) -> HashSet<i32> {
    let mut pids = HashSet::from([root]);
    loop {
        let old = pids.len();
        for p in procs {
            if pids.contains(&p.parent) {
                pids.insert(p.pid);
            }
        }
        if old == pids.len() {
            return pids;
        }
    }
}
fn open_paths(pid: i32) -> Result<Vec<PathBuf>> {
    #[cfg(target_os = "linux")]
    {
        Ok(fs::read_dir(format!("/proc/{pid}/fd"))?
            .filter_map(|e| fs::read_link(e.ok()?.path()).ok())
            .collect())
    }
    #[cfg(not(target_os = "linux"))]
    {
        let lsof = resolve("lsof").unwrap_or_else(|| PathBuf::from("/usr/sbin/lsof"));
        let o = Command::new(lsof)
            .args(["-nP", "-a", "-p", &pid.to_string(), "-Fn"])
            .output()?;
        if !o.status.success() {
            bail!("无法读取 Agent 的会话文件");
        }
        Ok(String::from_utf8_lossy(&o.stdout)
            .lines()
            .filter_map(|l| l.strip_prefix('n'))
            .map(PathBuf::from)
            .collect())
    }
}
fn transcript_paths(agent: &str, paths: &[PathBuf]) -> Vec<PathBuf> {
    let mut found = Vec::new();
    for path in paths {
        let filename = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default();
        if agent == "codex" && filename.starts_with("rollout-") && filename.ends_with(".jsonl") {
            found.push(path.clone());
        }
        if agent == "claude" {
            if path.extension().is_some_and(|s| s == "jsonl")
                && path.components().any(|c| c.as_os_str() == "projects")
            {
                found.push(path.clone());
            }
            // Claude keeps its session-specific debug log open even when the
            // transcript writer is closed. This gives an exact session ID.
            if path
                .parent()
                .and_then(Path::file_name)
                .is_some_and(|s| s == "debug")
            {
                if let (Some(config), Some(id)) = (
                    path.parent().and_then(Path::parent),
                    path.file_stem().and_then(|s| s.to_str()),
                ) {
                    if valid_id(id) {
                        if let Ok(dirs) = fs::read_dir(config.join("projects")) {
                            for dir in dirs.flatten().take(2000) {
                                let p = dir.path().join(format!("{id}.jsonl"));
                                if p.is_file() {
                                    found.push(p);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    found.sort();
    found.dedup();
    found
}

// Recent Claude versions publish a PID → session ID registry. Verify the
// process birth time too, so a stale registry file cannot match a reused PID.
fn claude_registered_transcripts(pid: i32, config: &Path) -> Vec<PathBuf> {
    let Ok(meta) = records_json(&config.join("sessions").join(format!("{pid}.json"))) else {
        return vec![];
    };
    if meta["pid"].as_i64() != Some(pid as i64) {
        return vec![];
    }
    let Some(id) = meta["sessionId"].as_str().filter(|id| valid_id(id)) else {
        return vec![];
    };
    let Some(birth) = meta["procStart"].as_str() else {
        return vec![];
    };
    let mut ps = Command::new("ps");
    ps.args(["-o", "lstart=", "-p", &pid.to_string()])
        .env("LC_ALL", "C")
        .env("TZ", "UTC");
    if output(ps).ok().is_none_or(|s| s.trim() != birth.trim()) {
        return vec![];
    }
    let Ok(dirs) = fs::read_dir(config.join("projects")) else {
        return vec![];
    };
    dirs.flatten()
        .take(2000)
        .map(|d| d.path().join(format!("{id}.jsonl")))
        .filter(|p| p.is_file())
        .collect()
}

pub fn inspect(rt: &Runtime, run: &Run) -> Result<Value> {
    if !run.is_live() {
        return Ok(json!({"sessions":[]}));
    }
    let pane = rt.tm(&[
        "display-message",
        "-p",
        "-t",
        &format!("={}:0.0", run.session),
        "#{pane_pid}",
    ])?;
    let root: i32 = pane.parse()?;
    let mut ps = Command::new("ps");
    ps.args(["-axo", "pid=,ppid=,args="]);
    let procs = processes(&output(ps)?);
    let owned = descendants(root, &procs);
    let mut sessions = Vec::new();
    let mut seen = HashSet::new();
    for p in procs
        .iter()
        .filter(|p| owned.contains(&p.pid) && p.agent.is_some())
    {
        let agent = p.agent.as_deref().unwrap();
        let mut transcripts = Vec::new();
        if agent == "claude" {
            let config = env::var_os("CLAUDE_CONFIG_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| {
                    PathBuf::from(env::var("HOME").unwrap_or_default()).join(".claude")
                });
            transcripts = claude_registered_transcripts(p.pid, &config);
        }
        if transcripts.is_empty() {
            transcripts = transcript_paths(agent, &open_paths(p.pid)?);
        }
        if transcripts.is_empty() {
            // A node launcher often has a native codex child; don't duplicate it.
            let children = descendants(p.pid, &procs);
            if procs.iter().any(|child| {
                child.pid != p.pid
                    && children.contains(&child.pid)
                    && child.agent.as_deref() == Some(agent)
            }) {
                continue;
            }
            sessions.push(AgentSession {
                id: format!("{agent}-{}", p.pid),
                agent: agent.into(),
                tasks: vec![],
                notice: Some("已识别 Agent，暂未找到可读取的任务记录。".into()),
            });
        }
        for path in transcripts {
            if !seen.insert(path.clone()) {
                continue;
            }
            let (records, clipped) = records(&path)?;
            let mut tasks = parse_tasks(agent, &records);
            // Current task files include updates made by teammates and survive
            // transcript compaction. The directory is tied to this session only.
            if agent == "claude" {
                if let (Some(config), Some(id)) = (
                    path.parent().and_then(Path::parent).and_then(Path::parent),
                    path.file_stem(),
                ) {
                    if let Ok(files) = fs::read_dir(config.join("tasks").join(id)) {
                        let mut current = Vec::new();
                        let mut incomplete = false;
                        for file in files
                            .flatten()
                            .take(1000)
                            .filter(|f| f.path().extension().is_some_and(|s| s == "json"))
                        {
                            match records_json(&file.path()) {
                                Ok(v) => {
                                    if v["status"] != "deleted" {
                                        if let Some(t) = v["id"].as_str().and_then(|id| {
                                            task(
                                                id.into(),
                                                &v["subject"],
                                                &v["status"],
                                                &v["description"],
                                            )
                                        }) {
                                            current.push(t);
                                        } else {
                                            incomplete = true;
                                        }
                                    }
                                }
                                Err(_) => incomplete = true,
                            }
                        }
                        if !incomplete {
                            current
                                .sort_by(|a, b| a.id.len().cmp(&b.id.len()).then(a.id.cmp(&b.id)));
                            tasks = current;
                        }
                    }
                }
            }
            sessions.push(AgentSession {
                id: path.to_string_lossy().into(),
                agent: agent.into(),
                tasks,
                notice: clipped.then(|| "仅读取最近的任务记录，较早的任务可能未包含。".into()),
            });
        }
    }
    Ok(json!({"sessions":sessions}))
}
fn records_json(path: &Path) -> Result<Value> {
    let f = fs::File::open(path)?;
    if f.metadata()?.len() > 1_000_000 {
        bail!("Task record too large");
    }
    Ok(serde_json::from_reader(f)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn plan(id: &str, steps: Value, result: &str) -> Vec<Value> {
        vec![
            json!({"type":"response_item","payload":{"type":"function_call","name":"update_plan","call_id":id,"arguments":json!({"plan":steps}).to_string()}}),
            json!({"type":"response_item","payload":{"type":"function_call_output","call_id":id,"output":result}}),
        ]
    }
    fn claude(id: &str, name: &str, input: Value, result: &str, error: bool) -> Vec<Value> {
        vec![
            json!({"message":{"content":[{"type":"tool_use","id":id,"name":name,"input":input}]}}),
            json!({"message":{"content":[{"type":"tool_result","tool_use_id":id,"content":result,"is_error":error}]}}),
        ]
    }
    #[test]
    fn codex_latest_successful_plan_and_clear() {
        let mut log = plan(
            "a",
            json!([{"step":"检查中文","status":"in_progress"}]),
            "Plan updated",
        );
        log.extend(plan(
            "b",
            json!([{"step":"wrong","status":"completed"}]),
            "Error: invalid plan",
        ));
        let tasks = parse_tasks("codex", &log);
        assert_eq!(tasks[0].title, "检查中文");
        assert_eq!(tasks[0].status, "in_progress");
        log.extend(plan("c", json!([]), "Plan updated"));
        assert!(parse_tasks("codex", &log).is_empty());
    }
    #[test]
    fn claude_create_update_delete_and_failed_call() {
        let mut log = claude(
            "a",
            "TaskCreate",
            json!({"subject":"Implement","description":"Details"}),
            "Task #7 created successfully: Implement",
            false,
        );
        log.extend(claude(
            "b",
            "TaskUpdate",
            json!({"taskId":"7","status":"in_progress"}),
            "Updated task #7",
            false,
        ));
        log.extend(claude(
            "c",
            "TaskUpdate",
            json!({"taskId":"7","status":"completed"}),
            "Error",
            true,
        ));
        let tasks = parse_tasks("claude", &log);
        assert_eq!(tasks[0].id, "7");
        assert_eq!(tasks[0].status, "in_progress");
        log.extend(claude(
            "d",
            "TaskUpdate",
            json!({"taskId":"7","status":"deleted"}),
            "Deleted",
            false,
        ));
        assert!(parse_tasks("claude", &log).is_empty());
    }
    #[test]
    fn claude_todos_replace_and_unknown_status() {
        let mut log = claude(
            "a",
            "TodoWrite",
            json!({"todos":[{"content":"Old","status":"pending"}]}),
            "ok",
            false,
        );
        log.extend(claude(
            "b",
            "TodoWrite",
            json!({"todos":[{"content":"New","status":"future_status"}]}),
            "ok",
            false,
        ));
        let tasks = parse_tasks("claude", &log);
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].title, "New");
        assert_eq!(tasks[0].status, "unknown");
    }
    #[test]
    fn process_tree_excludes_sibling_and_prompt_mentions() {
        let procs = processes("10 1 /bin/zsh\n11 10 node /x/@openai/codex/bin/codex.js\n12 11 /x/codex\n13 1 claude\n14 10 echo claude\n15 10 node /x/@anthropic-ai/claude-code/cli.js\n");
        let owned = descendants(10, &procs);
        assert!(!owned.contains(&13));
        assert!(procs.iter().find(|p| p.pid == 14).unwrap().agent.is_none());
        assert_eq!(
            procs
                .iter()
                .filter(|p| owned.contains(&p.pid) && p.agent.is_some())
                .count(),
            3
        );
    }
    #[test]
    fn transcript_discovery_requires_provider_specific_path() {
        let paths = vec![
            PathBuf::from("/tmp/notes.jsonl"),
            PathBuf::from("/tmp/sessions/rollout-one.jsonl"),
            PathBuf::from("/tmp/projects/repo/session.jsonl"),
        ];
        assert_eq!(transcript_paths("codex", &paths), vec![paths[1].clone()]);
        assert_eq!(transcript_paths("claude", &paths), vec![paths[2].clone()]);
    }
    #[test]
    fn partial_and_malformed_records_are_ignored() {
        let p = env::temp_dir().join(format!("ash-agent-records-{}", std::process::id()));
        fs::write(&p, "{\"valid\":true}\nbroken\n{\"partial\":true}").unwrap();
        let (v, clipped) = records(&p).unwrap();
        fs::remove_file(p).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["valid"], true);
        assert!(!clipped);
    }
}
