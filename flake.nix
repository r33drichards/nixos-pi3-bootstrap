{
  description = "Pi 3 hotspot bootstrap with Wi-Fi and Tailscale VM tests";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = { self, nixpkgs }: {
    nixosModules.bootstrap = import ./modules/bootstrap.nix;
    checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
      let pkgs = import nixpkgs { inherit system; }; in {
        wifi-autoconnect = pkgs.testers.runNixOSTest (import ./tests/wifi.nix);
        tailscale-ssh = pkgs.testers.runNixOSTest (import ./tests/tailscale.nix);
      });
  };
}
