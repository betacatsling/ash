//! Read-only workspace browsing and review. Paths are scoped to the requested root.
use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
};

const LIMIT: usize = 512 * 1024;

fn scoped(root: &Path, relative: &str) -> Result<PathBuf> {
    let path = root
        .join(relative)
        .canonicalize()
        .context("文件不存在或无法访问")?;
    if !path.starts_with(root) {
        bail!("只能预览当前目录内的文件");
    }
    Ok(path)
}

fn git(root: &Path, args: &[&str]) -> Result<Vec<u8>> {
    let out = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()?;
    if !out.status.success() {
        bail!("{}", String::from_utf8_lossy(&out.stderr).trim());
    }
    Ok(out.stdout)
}

fn bounded_diff(root: &Path, args: &[&str]) -> Result<(Vec<u8>, bool)> {
    let mut child = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let stderr = child.stderr.take().unwrap();
    let errors = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stderr.take(4096).read_to_end(&mut bytes);
        bytes
    });
    let mut bytes = Vec::new();
    let read = child
        .stdout
        .take()
        .unwrap()
        .take((LIMIT + 1) as u64)
        .read_to_end(&mut bytes);
    let truncated = bytes.len() > LIMIT;
    if truncated || read.is_err() {
        let _ = child.kill();
    }
    let status = child.wait()?;
    let errors = errors.join().unwrap_or_default();
    read?;
    if !truncated && !status.success() {
        bail!("{}", String::from_utf8_lossy(&errors).trim());
    }
    bytes.truncate(LIMIT);
    Ok((bytes, truncated))
}

fn base(root: &Path, v: &Value) -> Result<String> {
    if let Some(base) = v["base"].as_str() {
        if !(7..=64).contains(&base.len()) || !base.bytes().all(|c| c.is_ascii_hexdigit()) {
            bail!("无效的基准提交");
        }
        git(root, &["rev-parse", "--verify", base])?;
        return Ok(base.into());
    }
    if git(root, &["rev-parse", "--verify", "HEAD"]).is_ok() {
        return Ok("HEAD".into());
    }
    // An empty tree also supports repositories before their first commit.
    let out = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(["hash-object", "-t", "tree", "--stdin"])
        .output()?;
    if !out.status.success() {
        bail!("无法读取 Git 基准");
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().into())
}

pub fn request(action: &str, v: &Value) -> Result<Value> {
    let root = Path::new(v["cwd"].as_str().context("Missing cwd")?).canonicalize()?;
    match action {
        "browseFiles" => {
            let relative = v["path"].as_str().unwrap_or("");
            let directory = scoped(&root, relative)?;
            let mut entries = Vec::new();
            for entry in fs::read_dir(directory)? {
                let entry = entry?;
                let name = entry.file_name().to_string_lossy().into_owned();
                if name == ".git" {
                    continue;
                }
                let Ok(path) = entry.path().canonicalize() else {
                    continue;
                };
                if !path.starts_with(&root) {
                    continue;
                }
                let metadata = fs::metadata(&path)?;
                if !metadata.is_file() && !metadata.is_dir() {
                    continue;
                }
                entries.push(json!({"name":name,"path":entry.path().strip_prefix(&root)?.to_string_lossy(),"directory":metadata.is_dir(),"size":metadata.len()}));
                if entries.len() > 5000 {
                    break;
                }
            }
            entries.sort_by(|a, b| {
                b["directory"]
                    .as_bool()
                    .cmp(&a["directory"].as_bool())
                    .then(a["name"].as_str().cmp(&b["name"].as_str()))
            });
            let truncated = entries.len() > 5000;
            entries.truncate(5000);
            Ok(json!({"entries":entries,"truncated":truncated}))
        }
        "readFile" => {
            let path = scoped(&root, v["path"].as_str().context("Missing path")?)?;
            if !path.is_file() {
                bail!("请选择普通文件");
            }
            let size = fs::metadata(&path)?.len();
            let mut bytes = Vec::new();
            fs::File::open(&path)?
                .take((LIMIT + 1) as u64)
                .read_to_end(&mut bytes)?;
            let truncated = bytes.len() > LIMIT;
            bytes.truncate(LIMIT);
            let binary = bytes.contains(&0)
                || std::str::from_utf8(&bytes)
                    .err()
                    .map(|e| e.error_len().is_some())
                    .unwrap_or(false);
            Ok(
                json!({"text":if binary { String::new() } else { String::from_utf8_lossy(&bytes).into_owned() },"binary":binary,"truncated":truncated,"size":size}),
            )
        }
        "reviewFiles" | "reviewDiff" => {
            let repository = git(&root, &["rev-parse", "--show-toplevel"])?;
            let root = PathBuf::from(String::from_utf8_lossy(&repository).trim_end());
            let base = base(&root, v)?;
            if action == "reviewFiles" {
                let branch = git(&root, &["branch", "--show-current"])?;
                let bytes = git(
                    &root,
                    &[
                        "diff",
                        "--no-ext-diff",
                        "--no-textconv",
                        "--no-renames",
                        "--name-status",
                        "-z",
                        &base,
                        "--",
                    ],
                )?;
                let fields: Vec<_> = bytes.split(|b| *b == 0).filter(|s| !s.is_empty()).collect();
                let mut files = BTreeMap::new();
                for [status, path] in fields.as_chunks::<2>().0 {
                    files.insert(
                        String::from_utf8_lossy(path).into_owned(),
                        String::from_utf8_lossy(status).into_owned(),
                    );
                }
                for path in git(&root, &["ls-files", "--others", "--exclude-standard", "-z"])?
                    .split(|b| *b == 0)
                    .filter(|s| !s.is_empty())
                {
                    files.insert(String::from_utf8_lossy(path).into_owned(), "?".into());
                }
                Ok(
                    json!({"root":root,"branch":String::from_utf8_lossy(&branch).trim_end(),"files":files.into_iter().map(|(path,status)| json!({"path":path,"status":status})).collect::<Vec<_>>()}),
                )
            } else {
                let relative = v["path"].as_str().context("Missing path")?;
                if Path::new(relative).is_absolute()
                    || Path::new(relative)
                        .components()
                        .any(|c| matches!(c, std::path::Component::ParentDir))
                {
                    bail!("无效的文件路径");
                }
                let literal = format!(":(literal){relative}");
                let (bytes, truncated) = bounded_diff(
                    &root,
                    &[
                        "diff",
                        "--no-ext-diff",
                        "--no-textconv",
                        "--no-renames",
                        &base,
                        "--",
                        &literal,
                    ],
                )?;
                if bytes.is_empty()
                    && !git(
                        &root,
                        &[
                            "ls-files",
                            "--others",
                            "--exclude-standard",
                            "-z",
                            "--",
                            &literal,
                        ],
                    )?
                    .is_empty()
                {
                    let file = request("readFile", &json!({"cwd":root,"path":relative}))?;
                    if file["binary"] == true {
                        return Ok(
                            json!({"text":"二进制新文件，无法显示文本差异。","truncated":false}),
                        );
                    }
                    let text = file["text"].as_str().unwrap_or("");
                    return Ok(
                        json!({"text":format!("--- /dev/null\n+++ b/{relative}\n{}", text.split_terminator('\n').map(|s| format!("+{s}\n")).collect::<String>()),"truncated":file["truncated"]}),
                    );
                }
                Ok(json!({"text":String::from_utf8_lossy(&bytes),"truncated":truncated}))
            }
        }
        _ => bail!("Unknown panel action"),
    }
}
