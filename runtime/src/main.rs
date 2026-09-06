//! Runtime executable entry points.
use crate::{runtime::Runtime, support::resolve};
use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};
use std::{
    env,
    io::{self, Read, Write},
    path::Path,
    process::Command,
    thread,
    time::Duration,
};

mod agent_tasks;
mod installation;
mod models;
mod panel;
mod requests;
mod runtime;
mod sessions;
mod storage;
mod support;
mod terminal_environment;

const PROTOCOL: u32 = 1;

fn main() {
    if let Err(e) = main_result() {
        eprintln!("Ash: {e:#}");
        std::process::exit(1);
    }
}
fn main_result() -> Result<()> {
    unsafe {
        libc::umask(0o077);
    }
    let args: Vec<String> = env::args().collect();
    if let Some(bundle) = env::current_exe()?.parent().and_then(Path::parent) {
        if bundle.join("bin/tmux").is_file() {
            env::set_var("ASH_TMUX", bundle.join("bin/tmux"));
            env::set_var(
                "TERMINFO_DIRS",
                format!(
                    "{}:/usr/share/terminfo:/lib/terminfo",
                    bundle.join("terminfo").display()
                ),
            );
        }
    }
    if args.get(1).map(String::as_str) == Some("--version") {
        println!(
            "ash-runtime {} protocol {}",
            env!("CARGO_PKG_VERSION"),
            PROTOCOL
        );
        return Ok(());
    }
    if args.get(1).map(String::as_str) == Some("--self-check") {
        let sibling = env::current_exe()?.parent().unwrap().join("tmux");
        let tmux = if sibling.is_file() {
            sibling
        } else {
            resolve("tmux").ok_or_else(|| anyhow!("tmux is unavailable"))?
        };
        let result = Command::new(tmux).arg("-V").output()?;
        if !result.status.success() {
            bail!("Bundled tmux cannot execute");
        }
        println!(
            "ASH_READY|{}|{}|{}|{}",
            env!("CARGO_PKG_VERSION"),
            PROTOCOL,
            env::consts::OS,
            env::consts::ARCH
        );
        return Ok(());
    }
    if args.get(1).map(String::as_str) == Some("--install") {
        if args.len() != 5 {
            bail!("Invalid install arguments");
        }
        return installation::activate(Path::new(&args[2]), Path::new(&args[3]), &args[4]);
    }
    if args.get(1).map(String::as_str) == Some("request") {
        let response = (|| -> Result<Value> {
            let mut input = String::new();
            io::stdin().take(1_048_577).read_to_string(&mut input)?;
            if input.len() > 1_048_576 {
                bail!("Request too large");
            }
            let v: Value = serde_json::from_str(&input)?;
            Runtime::open()?.handle(v)
        })();
        let response = match response {
            Ok(v) => json!({"ok":true,"data":v}),
            Err(e) => json!({"ok":false,"error":format!("{e:#}")}),
        };
        writeln!(io::stdout(), "{response}")?;
        return Ok(());
    }
    let rt = Runtime::open()?;
    match args.get(1).map(String::as_str) {
        Some("execute") => rt.execute(args.get(2).ok_or_else(|| anyhow!("Missing ID"))?),
        Some("worker") => loop {
            {
                let _lock = rt.lock()?;
                if let Err(e) = rt.tick() {
                    eprintln!("{e:#}");
                }
            }
            thread::sleep(Duration::from_secs(2));
        },
        _ => bail!("Usage: ash-runtime request | --version"),
    }
}
