{
  description = "Simple HTTP server - static file server with directory listing, upload, basic auth, and optional TLS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          mkSimpleHttpServer =
            {
              withTls ? false,
            }:
            pkgs.rustPlatform.buildRustPackage {
              pname = "simple-http-server" + pkgs.lib.optionalString withTls "-tls";
              version = "0.8.1";

              src = pkgs.lib.cleanSource ./.;

              cargoLock = {
                lockFile = ./Cargo.lock;
              };
              cargoHash = "sha256-nUxoUJKZ22rmonJevIldSsFspFXQ4RIMl/0zW0IlGMc=";

              nativeBuildInputs = with pkgs; [
                pkg-config
              ];

              buildInputs =
                with pkgs;
                pkgs.lib.optionals withTls [ openssl ]
                ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                  libiconv
                  darwin.apple_sdk.frameworks.Security
                  darwin.apple_sdk.frameworks.SystemConfiguration
                ];

              buildFeatures = pkgs.lib.optionals withTls [ "tls" ];

              # openssl crate uses pkg-config against nixpkgs openssl,
              # don't fall back to vendored sources.
              OPENSSL_NO_VENDOR = 1;

              meta = with pkgs.lib; {
                description = "Simple static file HTTP server";
                homepage = "https://github.com/TheWaWaR/simple-http-server";
                license = licenses.mit;
                mainProgram = "simple-http-server";
                platforms = platforms.unix;
              };
            };
        in
        {
          # Default: no TLS feature (matches `cargo build`), smaller closure.
          default = mkSimpleHttpServer { };
          simple-http-server = self.packages.${system}.default;
          # With PKCS#12 HTTPS support (matches `cargo build --features tls`).
          simple-http-server-tls = mkSimpleHttpServer { withTls = true; };
        }
      );

      apps = forEachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/simple-http-server";
        };
      });

      devShells = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "simple-http-server-dev";
            strictDeps = true;

            # Official nixpkgs Rust toolchain (stable).
            nativeBuildInputs = with pkgs; [
              rustc
              cargo
              rustfmt
              clippy
              rust-analyzer
              pkg-config
            ];

            buildInputs = with pkgs; [
              openssl
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              libiconv
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.SystemConfiguration
            ];

            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
            OPENSSL_NO_VENDOR = 1;

            shellHook = ''
              echo "simple-http-server dev shell"
              rustc --version
              cargo --version
            '';
          };
        }
      );

      formatter = forEachSystem (system: (import nixpkgs { inherit system; }).nixfmt-tree);

      checks = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          build = self.packages.${system}.default;
          build-tls = self.packages.${system}.simple-http-server-tls;
          fmt = pkgs.stdenv.mkDerivation {
            name = "check-fmt";
            src = pkgs.lib.cleanSource ./.;
            nativeBuildInputs = [ pkgs.rustfmt ];
            buildPhase = "cargo fmt --all -- --check";
            installPhase = "touch $out";
          };
          clippy = self.packages.${system}.default.overrideAttrs (old: {
            name = "check-clippy";
            nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pkgs.clippy ];
            checkPhase = "cargo clippy --all --tests --all-features -- -D warnings";
            installPhase = "touch $out";
          });
        }
      );
    };
}
