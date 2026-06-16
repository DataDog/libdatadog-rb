{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.11";

    # cross-platform convenience
    flake-utils.url = "github:numtide/flake-utils";

    # backwards compatibility with nix-build and nix-shell
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";

    # pinned, exact upstream Rust toolchains
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat, rust-overlay }:
    # resolve for all platforms in turn
    flake-utils.lib.eachDefaultSystem (system:
      let
        basename = "libdatadog-rb";

        # packages for this system platform, with the rust-overlay applied
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        # pinned Rust toolchain for building libdatadog from source; single
        # source of truth is ./rust-toolchain.toml (kept in sync with the
        # libdatadog toolchain and the CI `RUST_VERSION`).
        rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        hook = ''
          # get major.minor.0 ruby version
          export RUBY_VERSION="$(ruby -e 'puts RUBY_VERSION.gsub(/\d+$/, "0")')"

          # make gem install work in-project, compatibly with bundler
          export GEM_HOME="$(pwd)/vendor/bundle/ruby/$RUBY_VERSION"

          # make bundle work in-project
          export BUNDLE_PATH="$(pwd)/vendor/bundle"

          # enable calling gem scripts without bundle exec
          export PATH="$GEM_HOME/bin:$PATH"

          # enable implicitly resolving gems to bundled version
          export RUBYGEMS_GEMDEPS="$(pwd)/Gemfile"
        '';

        deps = [
          pkgs.libyaml.dev  # for gem: psych
          pkgs.libffi.dev   # for gem: fiddle, ffi

          # for compiling libdatadog (rustc + cargo, pinned)
          rust
          pkgs.cmake
          pkgs.autoconf
          pkgs.automake
          pkgs.libtool
        ];

        mkRubyDevShell = { pkg }: pkgs.stdenv.mkDerivation {
          name = "${basename}-nix-shell";

          buildInputs = [ pkg ] ++ deps;

          shellHook = hook;
        };
      in rec {
        devShells.ruby40 = mkRubyDevShell { pkg = pkgs.ruby_4_0; };
        devShells.ruby34 = mkRubyDevShell { pkg = pkgs.ruby_3_4; };
        devShells.ruby33 = mkRubyDevShell { pkg = pkgs.ruby_3_3; };
        devShells.ruby32 = mkRubyDevShell { pkg = pkgs.ruby_3_2; };
        devShells.ruby31 = mkRubyDevShell { pkg = pkgs.ruby_3_1; };

        devShells.default = devShells.ruby40;
      }
    );
}
