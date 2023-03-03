# Cube

## What

A basic NBD block server with a single gimmick.

## Why

The main reason for using this over any other NBD server is its ability to reload the config without affecting any existing connection.

This allows for booting a device off an NBD device and changing the export configuration to point to a new root image. Without affecting the booted devices.
Then, when the device is rebooted, it will connect to the new root image.

## How

Create a config file `config.toml`

```toml
[listen]
port = 10809

[exports]
main = { path = "./src/main.rs", readonly = true }
block = "/tmp/block.bin"
```

Run the server with

```bash
cube -c config.toml
```

When the configuration is changed, it can be reloaded by sending `SIGHUP` to the server.

```bash
pkill -sighup cube
```