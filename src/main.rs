mod config;
mod error;

use crate::config::{Config, Exports};
use crate::error::{Error, HandshakeError, NbdError};
use clap::Parser;
use nbd::server::{handshake, transmission};
use signal_hook::consts::SIGHUP;
use signal_hook::iterator::exfiltrator::SignalOnly;
use signal_hook::iterator::SignalsInfo;
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::thread::spawn;
use tracing::{error, info};

#[derive(Debug, Parser)]
struct Args {
    #[arg(short, long)]
    config: PathBuf,
}

pub type Result<T, E = Error> = std::result::Result<T, E>;

#[tracing::instrument(skip_all, fields(remote = ?stream.peer_addr().ok()))]
fn handle_client(mut stream: TcpStream, exports: Exports) -> Result<(), NbdError> {
    let file = handshake(&mut stream, move |name| {
        let export_cfg = exports
            .get(name)
            .ok_or_else(|| HandshakeError::UnknownExport(name.into()))?;
        info!(name = name, export = ?export_cfg, "opening export");
        Ok(export_cfg.export()?)
    })?;
    info!("connected");
    transmission(&mut stream, file)?;
    info!("disconnected");
    Ok(())
}

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    let args = Args::parse();
    let config = Config::load(&args.config)?;
    let listener = TcpListener::bind(&config.listen).map_err(Error::Listen)?;
    info!("Listening on {}", config.listen);

    let exports = config.exports.clone();
    spawn(move || {
        let mut reload_signals = SignalsInfo::<SignalOnly>::new([SIGHUP]).unwrap();
        for _ in &mut reload_signals {
            info!("Reloading config");
            match Config::load(&args.config) {
                Ok(updated) => {
                    let count = exports.update(updated.exports);
                    info!("Registered {count} exports");
                }
                Err(e) => {
                    error!(error = ?e, "Failed to load updated config");
                }
            }
        }
    });

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let exports = config.exports.clone();
                spawn(move || {
                    if let Err(e) = handle_client(stream, exports) {
                        error!("{e}");
                    }
                });
            }
            Err(e) => {
                let e = Error::Connection(e);
                error!("{e}");
            }
        }
    }
    Ok(())
}
