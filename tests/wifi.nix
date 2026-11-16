{ pkgs, lib, ... }: {
  name = "phone-hotspot-autoconnect";
  nodes.machine = {
    imports = [ ../modules/bootstrap.nix ];
    virtualisation.memorySize = 1024;
    boot.kernelModules = [ "mac80211_hwsim" ];
    boot.extraModprobeConfig = "options mac80211_hwsim radios=2";
    networking.usePredictableInterfaceNames = false;
    networking.networkmanager.unmanaged = [ "interface-name:wlan0" "interface-name:eth*" ];
    networking.networkmanager.settings.main.no-auto-default = "*";
    piBootstrap.wifi = {
      enable = true;
      ssid = "Test iPhone";
      interface = "wlan1";
      environmentFile = "/run/hotspot.env";
    };
    systemd.services.test-secret = {
      wantedBy = [ "multi-user.target" ];
      before = [ "NetworkManager-ensure-profiles.service" ];
      requiredBy = [ "NetworkManager-ensure-profiles.service" ];
      serviceConfig.Type = "oneshot";
      script = "install -m600 ${pkgs.writeText "test-hotspot-env" "HOTSPOT_PSK=integration-test-only\n"} /run/hotspot.env";
    };
    networking.interfaces.wlan0.ipv4.addresses = [{ address = "192.168.50.1"; prefixLength = 24; }];
    services.hostapd = {
      enable = true;
      radios.wlan0 = {
        band = "2g"; channel = 6; countryCode = "US";
        networks.wlan0 = {
          ssid = "Test iPhone";
          authentication = { mode = "wpa2-sha1"; wpaPassword = "integration-test-only"; };
        };
      };
    };
    systemd.services.hostapd.wantedBy = lib.mkForce [];
    services.dnsmasq = {
      enable = true;
      settings = {
        interface = "wlan0";
        bind-dynamic = true;
        dhcp-range = "192.168.50.10,192.168.50.50,255.255.255.0,1h";
      };
    };
    networking.firewall.allowedUDPPorts = [ 67 ];
    environment.systemPackages = [ pkgs.iw ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("NetworkManager.service")
    machine.wait_for_unit("NetworkManager-ensure-profiles.service")
    machine.wait_until_succeeds("ip link show wlan1")
    connected = "iw dev wlan1 link | grep -F 'SSID: Test iPhone'"
    address = "ip -4 addr show wlan1 | grep -E 'inet 192[.]168[.]50[.](1[0-9]|[2-4][0-9]|50)/24'"
    with subtest("Boot succeeds while the phone is absent"):
        machine.fail(connected)
    with subtest("Automatically discover, authenticate and obtain DHCP when phone appears"):
        machine.succeed("systemctl start hostapd")
        machine.wait_until_succeeds(connected, timeout=120)
        machine.wait_until_succeeds(address, timeout=120)
    with subtest("Recover after the hotspot disappears and returns"):
        machine.succeed("systemctl stop hostapd")
        machine.wait_until_fails(connected, timeout=60)
        machine.succeed("systemctl start hostapd")
        machine.wait_until_succeeds(connected, timeout=120)
        machine.wait_until_succeeds(address, timeout=120)
    with subtest("Saved profile survives reboot without a manual connect command"):
        machine.reboot()
        machine.wait_for_unit("NetworkManager-ensure-profiles.service")
        machine.succeed("systemctl start hostapd")
        machine.wait_until_succeeds(connected, timeout=120)
        machine.wait_until_succeeds(address, timeout=120)
  '';
}
