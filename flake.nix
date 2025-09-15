# SPDX-FileCopyrightText: 2025 NONE
#
# SPDX-License-Identifier: Unlicense

{
  description = "Homelab infrastructure development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    coreos-installer.url = "github:ajpantuso/nix-coreos-installer";
    pykickstart.url = "github:ajpantuso/nix-pykickstart";
  };

  outputs = { self, nixpkgs, flake-utils, coreos-installer, pykickstart }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            butane
            coreos-installer.packages.${system}.default
            coreutils
            curl
            findutils
            git
            gnumake
            mo
            podman
            pre-commit
            pykickstart.packages.${system}.default
            reuse
          ];

          shellHook = ''
            export PROJECT_ROOT="$(git rev-parse --show-toplevel)";
            export CACHE_DIR="$PROJECT_ROOT/.cache";
            mkdir -p "$CACHE_DIR";
          '';
        };
      });
}
