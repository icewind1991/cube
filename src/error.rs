use miette::Diagnostic;
use std::io::{Error as IoError, ErrorKind};
use std::path::PathBuf;
use thiserror::Error;

#[derive(Debug, Error, Diagnostic)]
pub enum Error {
    #[error("Failed to listen to port")]
    Connection(IoError),
    #[error("Failed to listen to port")]
    Listen(IoError),
    #[error(transparent)]
    #[diagnostic(transparent)]
    Nbd(#[from] NbdError),
    #[error(transparent)]
    #[diagnostic(transparent)]
    Config(#[from] ConfigError),
}

#[derive(Debug, Error, Diagnostic)]
pub enum NbdError {
    #[error(transparent)]
    Io(IoError),
    #[error("Client disconnected unexpectedly")]
    Disconnected,
    #[error(transparent)]
    #[diagnostic(transparent)]
    Handshake(HandshakeError),
}

impl From<NbdError> for IoError {
    fn from(value: NbdError) -> Self {
        match value {
            NbdError::Handshake(e) => e.into(),
            NbdError::Io(e) => e,
            NbdError::Disconnected => ErrorKind::UnexpectedEof.into(),
        }
    }
}

impl From<IoError> for NbdError {
    fn from(value: IoError) -> Self {
        match value.kind() {
            ErrorKind::UnexpectedEof => NbdError::Disconnected,
            _ => NbdError::Io(value),
        }
    }
}

#[derive(Debug, Error, Diagnostic)]
pub enum HandshakeError {
    #[error("Unknown export {0}")]
    UnknownExport(String),
    #[error("Failed to open {path}")]
    Open { path: PathBuf, err: IoError },
}

impl From<HandshakeError> for IoError {
    fn from(value: HandshakeError) -> Self {
        match value {
            HandshakeError::Open { err, .. } => err,
            HandshakeError::UnknownExport(export) => {
                IoError::new(ErrorKind::InvalidData, format!("Unknown export: {export}"))
            }
        }
    }
}

#[derive(Debug, Error, Diagnostic)]
pub enum ConfigError {
    #[error("Failed to read config file")]
    Read(#[from] IoError),
    #[error("Failed to parse config file")]
    Parse(#[from] toml::de::Error),
}
