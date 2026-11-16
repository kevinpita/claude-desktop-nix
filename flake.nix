{
  description = "Nix flake for Claude Desktop, repackaged from the official Debian package";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      overlay = final: _prev: {
        claude-desktop = final.callPackage ./packages/claude-desktop.nix { };
      };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
          # Claude Desktop is unfree.
          config.allowUnfree = true;
        };
      in
      {
        packages = {
          default = pkgs.claude-desktop;
          inherit (pkgs) claude-desktop;
        };

        formatter = pkgs.nixfmt-tree;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gh
            nixfmt
          ];
        };
      }
    )
    // {
      overlays.default = overlay;
    };
}
