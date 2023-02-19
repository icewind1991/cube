{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: let
      buildNbs = pkgs: pkgs.rustPlatform.buildRustPackage rec {
        version = "0.1.0";
        pname = "nbs";

        src = ./.;

        cargoSha256 = "sha256-qhCIHD+suZkwvthuIKvI1BUOi8NHEJHUTb6Qc2talz8=";

        meta = with pkgs.lib; {
          description = "A basic NBD block server with a single gimmick";
          homepage = "https://github.com/icewind1991/nbs";
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
          packages.nbs = buildNbs pkgs;
          defaultPackage = packages.nbs;
          defaultApp = packages.nbs;

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
          nbs = buildNbs pkgs;
          cfg = config.services.nbs;
          format = pkgs.formats.toml {};
          configFile = format.generate "nbs.toml" ({
            inherit (cfg) listen;
            exports = mapAttrs (_: export: {
              inherit (export) path;
              read_only = export.readOnly;
            }) cfg.exports;
          });
          pkg = self.defaultPackage.${pkgs.system};
        in {
          options.services.nbs = {
            enable = mkEnableOption "nbs";

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
            # symlink instead of passing `configFile` directly to nbs to allread changing the config without changing the path
            environment.etc."nbs/nbs.toml".source = configFile;

            networking.firewall.allowedTCPPorts = optional cfg.openPorts cfg.listen.port;

            systemd.services.nbs = {
              description = "NBD block server";

              environment = {
                RUST_LOG = cfg.log;
              };

              serviceConfig = {
                ExecStart = "${nbs}/bin/nbs -c /etc/nbs/nbs.toml";
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
