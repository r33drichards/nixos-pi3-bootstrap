{ config, lib, ... }:
let cfg = config.piBootstrap; in {
  options.piBootstrap = {
    wifi.enable = lib.mkEnableOption "automatic hotspot Wi-Fi connection";
    wifi.ssid = lib.mkOption { type = lib.types.str; default = "iPhone"; };
    wifi.interface = lib.mkOption { type = lib.types.str; default = "wlan0"; };
    wifi.environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pi-bootstrap/hotspot.env";
      description = "Root-only runtime file containing HOTSPOT_PSK; never put the password in Nix.";
    };
    authorizedKeys = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    tailscale.authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional runtime auth-key file for unattended enrollment.";
    };
    tailscale.extraUpFlags = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
  };
  config = lib.mkMerge [ {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      authKeyFile = cfg.tailscale.authKeyFile;
      extraUpFlags = cfg.tailscale.extraUpFlags;
    };
    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = { PasswordAuthentication = false; KbdInteractiveAuthentication = false; PermitRootLogin = "prohibit-password"; };
    };
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
    users.users.root.openssh.authorizedKeys.keys = cfg.authorizedKeys;
  } (lib.mkIf cfg.wifi.enable {
    networking.networkmanager = {
      enable = true;
      ensureProfiles.environmentFiles = [ cfg.wifi.environmentFile ];
      ensureProfiles.profiles.phone-hotspot = {
        connection = {
          id = "phone-hotspot";
          type = "wifi";
          interface-name = cfg.wifi.interface;
          autoconnect = true;
          autoconnect-retries = 0;
          autoconnect-priority = 100;
        };
        wifi = { ssid = cfg.wifi.ssid; mode = "infrastructure"; cloned-mac-address = "permanent"; };
        wifi-security = { key-mgmt = "wpa-psk"; psk = "$HOTSPOT_PSK"; };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
  }) ];
}
