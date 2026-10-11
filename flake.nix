{
  description = "Simple HTTP server - static file server with directory listing, upload, basic auth, and optional TLS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    { self, nixpkgs, crane }:
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
          craneLib = crane.mkLib pkgs;

          src = craneLib.cleanCargoSource ./.;

          mkSimpleHttpServer =
            { withTls ? false }:
            let
              commonArgs = {
                inherit src;
                pname = "simple-http-server" + pkgs.lib.optionalString withTls "-tls";
                version = "0.8.1";

                strictDeps = true;

                nativeBuildInputs = [ pkgs.pkg-config ];

                buildInputs =
                  pkgs.lib.optionals withTls [ pkgs.openssl ]
                  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                    pkgs.libiconv
                    pkgs.darwin.apple_sdk.frameworks.Security
                    pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
                  ];

                cargoExtraArgs = pkgs.lib.optionalString withTls "--features tls";

                # openssl crate uses pkg-config against nixpkgs openssl,
                # don't fall back to vendored sources.
                OPENSSL_NO_VENDOR = "1";

                meta = with pkgs.lib; {
                  description = "Simple static file HTTP server";
                  homepage = "https://github.com/TheWaWaR/simple-http-server";
                  license = licenses.mit;
                  mainProgram = "simple-http-server";
                  platforms = platforms.unix;
                };
              };
              # Dependencies are built in a separate derivation, so editing
              # project sources only recompiles the crate itself.
              cargoArtifacts = craneLib.buildDepsOnly commonArgs;
            in
            craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        in
        rec {
          # Default: no TLS feature (matches `cargo build`), smaller closure.
          default = mkSimpleHttpServer { };
          simple-http-server = default;
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
          craneLib = crane.mkLib pkgs;
        in
        {
          default = craneLib.devShell {
            packages =
              [
                pkgs.pkg-config
                pkgs.openssl
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                pkgs.libiconv
                pkgs.darwin.apple_sdk.frameworks.Security
                pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
              ];

            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
            OPENSSL_NO_VENDOR = "1";

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
          craneLib = crane.mkLib pkgs;

          src = craneLib.cleanCargoSource ./.;

          commonArgs = {
            inherit src;
            strictDeps = true;
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.openssl ];
            cargoExtraArgs = "--all-features";
            OPENSSL_NO_VENDOR = "1";
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          build = self.packages.${system}.default;
          build-tls = self.packages.${system}.simple-http-server-tls;

          fmt = craneLib.cargoFmt { inherit src; };

          clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- -D warnings";
            }
          );

          test = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });
        }
      );
    };
}
