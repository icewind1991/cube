use crate::error::{ConfigError, HandshakeError};
use nbd::Export;
use serde::Deserialize;
use std::collections::HashMap;
use std::fmt::{Display, Formatter};
use std::fs::{read_to_string, File, OpenOptions};
use std::net::ToSocketAddrs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use tracing::{debug, info};

#[derive(Debug, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub listen: ListenConfig,
    pub exports: Exports,
}

impl Config {
    pub fn load(path: impl AsRef<Path>) -> Result<Config, ConfigError> {
        let content = read_to_string(path)?;
        Ok(toml::from_str(&content)?)
    }
}

#[derive(Debug, Deserialize)]
pub struct ListenConfig {
    #[serde(default = "default_address")]
    pub address: String,
    #[serde(default = "default_port")]
    pub port: u16,
}

impl Display for ListenConfig {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.address, self.port)
    }
}

impl Default for ListenConfig {
    fn default() -> Self {
        ListenConfig {
            address: default_address(),
            port: default_port(),
        }
    }
}

fn default_address() -> String {
    "0.0.0.0".into()
}

fn default_port() -> u16 {
    10809
}

impl ToSocketAddrs for ListenConfig {
    type Iter = <(String, u16) as ToSocketAddrs>::Iter;

    fn to_socket_addrs(&self) -> std::io::Result<Self::Iter> {
        (self.address.as_str(), self.port).to_socket_addrs()
    }
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ExportConfigDe {
    Simple(PathBuf),
    Options(ExportConfigRaw),
}

#[derive(Debug, Clone, Deserialize)]
pub struct ExportConfigRaw {
    #[serde(default)]
    pub readonly: bool,
    pub path: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(from = "ExportConfigDe")]
pub struct ExportConfig {
    pub readonly: bool,
    pub path: PathBuf,
}

impl From<ExportConfigDe> for ExportConfig {
    fn from(value: ExportConfigDe) -> Self {
        match value {
            ExportConfigDe::Simple(path) => ExportConfig {
                readonly: false,
                path,
            },
            ExportConfigDe::Options(export) => ExportConfig {
                readonly: export.readonly,
                path: export.path,
            },
        }
    }
}

impl ExportConfig {
    pub fn export(&self) -> Result<Export<File>, HandshakeError> {
        let meta = self.path.metadata().map_err(|e| HandshakeError::Open {
            err: e,
            path: self.path.clone(),
        })?;
        let size = match meta.len() {
            0 => {
                let path = self.path.canonicalize().map_err(|e| HandshakeError::Open {
                    err: e,
                    path: self.path.clone(),
                })?;
                if path != self.path {
                    debug!(path = ?self.path, canonicalized = ?path, "path is configured in non canonicalized form");
                }
                get_block_size(&path).ok_or_else(|| HandshakeError::UnknownSize(path))?
            }
            size => size,
        };

        let readonly = self.readonly || meta.permissions().readonly();
        let mut opt = OpenOptions::new();
        opt.read(true);
        if !readonly {
            opt.write(true);
        }

        let file = opt.open(&self.path).map_err(|e| HandshakeError::Open {
            err: e,
            path: self.path.clone(),
        })?;

        info!(readonly, size, "go export meta");

        Ok(Export {
            readonly,
            size,
            data: file,
            resizeable: false,
            rotational: false,
            send_trim: false,
            send_flush: false,
        })
    }
}

#[tracing::instrument]
fn get_block_size(path: &Path) -> Option<u64> {
    let device = path.strip_prefix("/dev").ok()?;
    let mut sys_path = PathBuf::from("/sys/class/block");
    sys_path.push(device);
    sys_path.push("size");
    debug!(sysfs_path = ?sys_path, "getting block size");
    let size_str = read_to_string(sys_path).ok()?;
    debug!(block_count = size_str, "got size");
    size_str.trim().parse().ok().map(|blocks: u64| blocks * 512)
}

#[derive(Debug, Clone, Deserialize)]
#[serde(from = "HashMap<String, ExportConfig>")]
pub struct Exports {
    exports: Arc<Mutex<HashMap<String, ExportConfig>>>,
}

impl From<HashMap<String, ExportConfig>> for Exports {
    fn from(value: HashMap<String, ExportConfig>) -> Self {
        Exports {
            exports: Arc::new(Mutex::new(value)),
        }
    }
}

impl Exports {
    pub fn get(&self, name: &str) -> Option<ExportConfig> {
        self.exports.lock().unwrap().get(name).cloned()
    }

    #[allow(dead_code)]
    pub fn update(&self, other: Exports) -> usize {
        let other = match Arc::try_unwrap(other.exports) {
            Ok(mutex) => mutex.into_inner().unwrap(),
            Err(arc) => arc.lock().unwrap().clone(),
        };
        let count = other.len();
        *self.exports.lock().unwrap() = other;
        count
    }
}
