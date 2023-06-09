{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/nixos-23.05";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = (import nixpkgs) {
          inherit system;
        };
      in rec {
        # `nix build`
        packages = rec {
          cube = pkgs.callPackage (import ./package.nix) {};
          default = cube;
        };

        # `nix develop`
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [rustc cargo bacon cargo-edit cargo-outdated];
        };
      }
    )
    // {
      nixosModule = {
        config,
        lib,
        pkgs,
        ...
      }:
        with lib; let
          cube = pkgs.callPackage (import ./package.nix) {};
          cfg = config.services.cube;
          format = pkgs.formats.toml {};
          configFile = format.generate "cube.toml" {
            inherit (cfg) listen;
            exports =
              mapAttrs (_: export: {
                inherit (export) path;
                read_only = export.readOnly;
              })
              cfg.exports;
          };
          pkg = self.defaultPackage.${pkgs.system};
        in {
          options.services.cube = {
            enable = mkEnableOption "cube";

            log = mkOption {
              type = types.str;
              default = "INFO";
              description = "Log level";
            };

            listen = mkOption {
              type = types.submodule {
                options = {
                  port = mkOption {
                    type = types.int;
                    default = 10809;
                    description = "Port to listen on";
                  };
                  address = mkOption {
                    type = types.str;
                    default = "0.0.0.0";
                    description = "Address to listen on";
                  };
                };
              };
              default = {
                address = "0.0.0.0";
                port = 10809;
              };
            };

            exports = mkOption {
              default = [];
              type = types.attrsOf (types.submodule {
                options = {
                  path = mkOption {
                    type = types.str;
                    description = "Source path to the image to export";
                  };
                  readOnly = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether to export the image readonly";
                  };
                };
              });
            };

            openPorts = mkOption {
              default = false;
              type = types.bool;
            };
          };

          config = mkIf cfg.enable {
            # symlink instead of passing `configFile` directly to cube to allread changing the config without changing the path
            environment.etc."cube/cube.toml".source = configFile;

            networking.firewall.allowedTCPPorts = optional cfg.openPorts cfg.listen.port;

            systemd.services.cube = {
              description = "NBD block server";

              environment = {
                RUST_LOG = cfg.log;
              };

              serviceConfig = {
                ExecStart = "${cube}/bin/cube -c /etc/cube/cube.toml";
                ExecReload = "${pkgs.util-linux}/bin/kill -HUP $MAINPID";
                Restart = "on-failure";
                RestartSec = 10;
              };
              wantedBy = ["multi-user.target"];
              reloadTriggers = [configFile];
            };
          };
        };
    };
}
