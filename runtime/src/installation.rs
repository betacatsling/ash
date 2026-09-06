//! Versioned activation. This process owns only the installer lock, never live terminal sessions.
use crate::support::quote;
use anyhow::{anyhow, bail, Context, Result};
use fs2::FileExt;
use serde_json::Value;
use std::{
    env, fs,
    io::{self, Write},
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

fn version(s: &str) -> Option<(u64, u64, u64)> {
    let parts: Vec<_> = s.split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    Some((
        parts[0].parse().ok()?,
        parts[1].parse().ok()?,
        parts[2].parse().ok()?,
    ))
}
fn installed_version(path: &Path) -> Option<String> {
    let result = Command::new(path).arg("--version").output().ok()?;
    if !result.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&result.stdout);
    let mut fields = text.split_whitespace();
    if fields.next()? != "ash-runtime" {
        return None;
    }
    Some(fields.next()?.to_owned())
}
fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let temp = path.with_extension(format!("ash-new-{}", std::process::id()));
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temp)?;
    let result = (|| -> Result<()> {
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::set_permissions(&temp, fs::Permissions::from_mode(0o700))?;
        fs::rename(&temp, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}
pub fn activate(root: &Path, launcher: &Path, digest: &str) -> Result<()> {
    if !root.is_absolute()
        || !launcher.is_absolute()
        || digest.len() != 64
        || !digest.bytes().all(|b| b.is_ascii_hexdigit())
    {
        bail!("Invalid installation destination or digest");
    }
    fs::create_dir_all(root)?;
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(root.join("install.lock"))?;
    lock.lock_exclusive()?; // OS releases this lock even after a crash or a broken SSH connection.
    if installed_version(launcher).and_then(|v| version(&v)) > version(env!("CARGO_PKG_VERSION")) {
        bail!("A newer Ash runtime is installed; update this Mac's Ash instead of downgrading the server");
    }
    let source = env::current_exe()?
        .parent()
        .and_then(Path::parent)
        .ok_or_else(|| anyhow!("Invalid runtime package"))?
        .to_path_buf();
    let versions = root.join("versions");
    fs::create_dir_all(&versions)?;
    let nonce = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let release = versions.join(format!(
        "{}-{}-{nonce}",
        env!("CARGO_PKG_VERSION"),
        &digest[..16]
    ));
    fs::rename(&source, &release).context("Cannot stage the versioned runtime")?;
    let executable = release.join("bin/ash-runtime");
    let check = Command::new(&executable).arg("--self-check").output()?;
    if !check.status.success() {
        bail!(
            "Runtime self-check failed: {}",
            String::from_utf8_lossy(&check.stderr)
        );
    }
    let parent = launcher
        .parent()
        .ok_or_else(|| anyhow!("Invalid launcher"))?;
    fs::create_dir_all(parent)?;
    let previous = match fs::read(launcher) {
        Ok(bytes) => Some(bytes),
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e.into()),
    };
    let script = format!("#!/bin/sh\nexport ASH_RUNTIME_HOME={}\nexport ASH_TMUX={}\nexport TERMINFO_DIRS={}:\"${{TERMINFO_DIRS:-/usr/share/terminfo:/lib/terminfo}}\"\nexec {} \"$@\"\n",
        quote(&root.to_string_lossy()), quote(&release.join("bin/tmux").to_string_lossy()), quote(&release.join("terminfo").to_string_lossy()), quote(&executable.to_string_lossy()));
    atomic_write(launcher, script.as_bytes())?;
    let verified = (|| -> Result<()> {
        let mut child = Command::new(launcher)
            .arg("request")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;
        child
            .stdin
            .take()
            .unwrap()
            .write_all(b"{\"protocol\":1,\"action\":\"health\"}\n")?;
        let result = child.wait_with_output()?;
        let response: Value = serde_json::from_slice(&result.stdout)?;
        if !result.status.success()
            || response["ok"] != true
            || response["data"]["version"] != env!("CARGO_PKG_VERSION")
        {
            bail!("Installed runtime did not pass the health check: {response}");
        }
        Ok(())
    })();
    if let Err(error) = verified {
        if let Some(bytes) = previous {
            atomic_write(launcher, &bytes)
                .context("Health check failed and previous launcher could not be restored")?;
        } else {
            fs::remove_file(launcher)?;
        }
        bail!("Activation failed; previous runtime restored: {error:#}");
    }
    fs::write(release.join("package.sha256"), digest)?;
    println!("ASH_INSTALLED|{}", env!("CARGO_PKG_VERSION"));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compares_versions_numerically() {
        assert!(version("0.10.0") > version("0.9.9"));
        assert_eq!(version("../bad"), None);
    }
}
