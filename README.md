# claude-desktop-nix

Nix package for [Claude Desktop](https://code.claude.com/docs/en/desktop-linux) on Linux, repackaged from the official Debian package.

| Package | Upstream | Programs | Use it on |
| --- | --- | --- | --- |
| `claude-desktop` (default) | [apt repository](https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages) | `claude-desktop` | `x86_64-linux` desktops. |

The package patches Cowork to use QEMU, the UEFI firmware, and `virtiofsd` from nixpkgs, because the app looks for them at Debian paths. The build fails if upstream moves one of these paths. The setuid `chrome-sandbox` helper is removed, so Chromium uses user namespaces.

Claude Desktop is **unfree**. This flake's own `packages` output allows it. With `overlays.default`, your nixpkgs must allow it:

```nix
nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-desktop" ];
```

## Quick start

```sh
nix run github:kevinpita/claude-desktop-nix
```

## NixOS

Add the input and the overlay to your flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    claude-desktop-nix = {
      url = "github:kevinpita/claude-desktop-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, claude-desktop-nix, ... }: {
    nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ claude-desktop-nix.overlays.default ];
          nixpkgs.config.allowUnfree = true;
          environment.systemPackages = [ pkgs.claude-desktop ];
        })
      ];
    };
  };
}
```

Without the overlay, use `claude-desktop-nix.packages.x86_64-linux.default` in a package list.

## Development

Run these commands from the repository root:

```sh
nix develop
nix fmt
nix flake check --all-systems --no-build
nix build .#claude-desktop
test -x ./result/bin/claude-desktop
```

For new, untracked files, use `nix flake check "path:$PWD" --all-systems --no-build` until the files are added to Git.

## Updates

The update workflow checks the upstream apt index hourly. For a new release, it takes the version and the SHA-256 from the index, updates `flake.lock`, builds the package, and creates a pull request with auto-merge.

```sh
./scripts/update.sh --check
./scripts/update.sh --version 5.11492.5
./scripts/update.sh
```

## License

The packaging code in this repository is MIT licensed. Claude Desktop itself is proprietary software from Anthropic.
