{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: let
      buildCube = pkgs: pkgs.rustPlatform.buildRustPackage rec {
        version = "0.1.0";
        pname = "cube";

        src = ./.;

        cargoSha256 = "sha256-tHcIwMQrGIRC6W0/B476QT5nOUY/5KkzEeJKbg3sFUA=";

        meta = with pkgs.lib; {
          description = "A basic NBD block server with a single gimmick";
          homepage = "https://github.com/icewind1991/cube";
          license = licenses.mit;
          platforms = platforms.linux;
        };
      };
    in flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages."${system}";
      in
        rec {
          # `nix build`
          packages.cube = buildCube pkgs;
          defaultPackage = packages.cube;
          defaultApp = packages.cube;

          # `nix develop`
          devShell = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [ rustc cargo bacon cargo-edit cargo-outdated ];
          };
        }
    ) // {
      nixosModule = {
        config,
        lib,
        pkgs,
        ...
      }:
        with lib; let
          cube = buildCube pkgs;
          cfg = config.services.cube;
          format = pkgs.formats.toml {};
          configFile = format.generate "cube.toml" ({
            inherit (cfg) listen;
            exports = mapAttrs (_: export: {
              inherit (export) path;
              read_only = export.readOnly;
            }) cfg.exports;
          });
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
