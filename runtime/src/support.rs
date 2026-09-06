//! Shared process, path, quoting, and validation helpers.
use anyhow::{anyhow, bail, Result};
use serde_json::Value;
use std::{
    env, fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

pub(crate) fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}
pub(crate) fn quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
pub(crate) fn valid_id(s: &str) -> bool {
    !s.is_empty() && s.len() <= 80 && s.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
}
pub(crate) fn required(v: &Value, key: &str) -> Result<String> {
    v[key]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .ok_or_else(|| anyhow!("Missing {key}"))
}
pub(crate) fn output(mut c: Command) -> Result<String> {
    let o = c.output()?;
    if !o.status.success() {
        bail!("{}", String::from_utf8_lossy(&o.stderr).trim());
    }
    Ok(String::from_utf8_lossy(&o.stdout).trim_end().to_string())
}
pub(crate) fn resolve(name: &str) -> Option<PathBuf> {
    let p = Path::new(name);
    if p.is_absolute() && p.is_file() {
        return Some(p.to_path_buf());
    }
    let home = env::var("HOME").unwrap_or_default();
    let extra = format!(
        "{home}/.local/bin:{home}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    );
    let search = format!("{}:{extra}", env::var("PATH").unwrap_or_default());
    for dir in search.split(':').filter(|s| !s.is_empty()) {
        let p = Path::new(dir).join(name);
        if p.is_file()
            && fs::metadata(&p)
                .map(|m| m.permissions().mode() & 0o111 != 0)
                .unwrap_or(false)
        {
            return Some(p);
        }
    }
    None
}
pub(crate) fn root() -> PathBuf {
    env::var_os("ASH_RUNTIME_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var("HOME").unwrap()).join(".local/share/ash"))
}
pub(crate) fn truncate(s: &str, max: usize) -> &str {
    let mut n = s.len().min(max);
    while !s.is_char_boundary(n) {
        n -= 1;
    }
    &s[..n]
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shell_quoting() {
        assert_eq!(quote("a'b\n$(x)"), "'a'\\''b\n$(x)'");
    }
    #[test]
    fn ids_cannot_inject_tmux_targets() {
        for id in ["", "-x;touch /tmp/x", "a:b", "a.b", "../x"] {
            assert!(!valid_id(id));
        }
        assert!(valid_id("A-b-123"));
    }
    #[test]
    fn unicode_truncation() {
        assert_eq!(truncate("你好hello", 4), "你");
    }
}
