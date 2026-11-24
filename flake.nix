{
  description = "Stream Tube - A native YouTube client for Windows and Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
          config = {
            allowUnfree = true;
          };
        };

        # Rust toolchain
        rustToolchain = pkgs.rust-bin.stable.latest.default;

        # Native build inputs
        nativeBuildInputs = with pkgs; [
          rustToolchain
          pkg-config
        ];

        # Build dependencies for Linux
        buildInputs = with pkgs; [
          fontconfig
          freetype
          wayland
          libxkbcommon
          libx11
          libxcb
          vulkan-loader
          openssl
          zstd
        ];

        # Version from Cargo.toml
        version = "0.7.2-alpha";

      in {
        devShells.default = pkgs.mkShell {
          name = "streamtube-dev";
          buildInputs = nativeBuildInputs ++ buildInputs;
          shellHook = ''
            export RUST_BACKTRACE=1
            echo "Stream Tube development environment"
            echo "Run 'cargo build --release' to build"
            echo "Run 'cargo run --release' to run"
          '';
        };

        packages.default = pkgs.rustPlatform.buildRustPackage {
          inherit version;
          pname = "streamtube";
          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
            #outputHashes = {
            #  "gpui-pre-windows-0.3.12" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            #};
          };

          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;

          # Use the same optimization as release profile
          NIX_CFLAGS_COMPILE = "-O2";
          NIX_CXXFLAGS_COMPILE = "-O2";

          cargoBuildType = "release";

          # Build phase
          buildPhase = ''
            cargo build --release --locked
          '';

          # Install phase
          installPhase = ''
            mkdir -p $out/bin
            cp target/release/streamtube $out/bin/
            # Also copy assets
            mkdir -p $out/share/streamtube
            cp assets/logo.png $out/share/streamtube/
            cp assets/logo.svg $out/share/streamtube/
            # Desktop file
            mkdir -p $out/share/applications
            cp packaging/linux/streamtube.desktop $out/share/applications/
            # Icon
            mkdir -p $out/share/icons/hicolor/256x256/apps
            cp assets/logo.png $out/share/icons/hicolor/256x256/apps/streamtube.png
            mkdir -p $out/share/icons/hicolor/scalable/apps
            cp assets/logo.svg $out/share/icons/hicolor/scalable/apps/streamtube.svg
            # Metainfo
            mkdir -p $out/share/metainfo
            cp packaging/linux/io.github.avaneesh_inamdar.StreamTube.metainfo.xml $out/share/metainfo/
            # License and readme
            mkdir -p $out/share/doc/streamtube
            cp LICENSE README.md $out/share/doc/streamtube/
          '';

          # Allow the build to access the network for cargo
          impureEnvVars = [ "CARGO_HOME" "RUSTUP_HOME" "HOME" ];

          # Don't run tests by default - they require --ignored flag
          doCheck = false;
        };

        # App package for use in other flakes
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/streamtube";
        };

        # Checks for CI
        checks = {
          build = self.packages.${system}.default;
          # Run cargo check
          check = pkgs.runCommand "cargo-check" {
            nativeBuildInputs = nativeBuildInputs;
            buildInputs = buildInputs;
          } ''
            cargo check --locked
          '';
          # Run clippy
          clippy = pkgs.runCommand "cargo-clippy" {
            nativeBuildInputs = nativeBuildInputs ++ [ pkgs.clippy ];
            buildInputs = buildInputs;
          } ''
            cargo clippy --locked -- -D warnings
          '';
          # Run tests (ignored)
          test = pkgs.runCommand "cargo-test" {
            nativeBuildInputs = nativeBuildInputs;
            buildInputs = buildInputs;
          } ''
            cargo test --locked -- --ignored
          '';
        };
      }
    );
}