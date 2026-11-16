# Pi 3 hotspot bootstrap

NixOS module and Linux VM integration tests for a Raspberry Pi joining an iPhone hotspot automatically and accepting ordinary SSH over Tailscale. The Mac can stay on its existing internet connection.

## Tests

```sh
nix build -L .#checks.x86_64-linux.wifi-autoconnect
nix build -L .#checks.x86_64-linux.tailscale-ssh
```

GitHub Actions runs both tests with KVM. The Wi-Fi test uses two mac80211_hwsim radios in one VM: a WPA2 access point with DHCP and a NetworkManager client. It checks boot without the hotspot, automatic association and DHCP when it appears, recovery after disappearance, and connection after reboot. No `nmcli connect` command is used.

The VPN test uses a disposable local Headscale server and two Tailscale clients. It checks enrollment, SSH over the VPN with a generated test-only key, and identity persistence across daemon restart. It never contacts a production tailnet.

These tests do not emulate the Pi's Broadcom firmware, iPhone hotspot discoverability, cellular service, or Xfinity's captive portal. Those require physical validation. Wi-Fi and VPN are tested separately; this is not yet a combined end-to-end wireless VPN test.

## Physical Pi configuration

Import `modules/bootstrap.nix`, then configure:

```nix
piBootstrap = {
  wifi.enable = true;
  wifi.ssid = "Your iPhone name";
  authorizedKeys = [ "ssh-ed25519 YOUR_PUBLIC_KEY" ];
  tailscale.authKeyFile = "/var/lib/pi-bootstrap/tailscale-authkey";
};
```

Provision `/var/lib/pi-bootstrap/hotspot.env` with `HOTSPOT_PSK=your-hotspot-password`, owned by root with mode 0600. Put a one-off Tailscale auth key in the root-only runtime auth-key file for unattended enrollment, or leave `authKeyFile` null and run `sudo tailscale up` interactively. Never put actual passwords or auth keys in Nix expressions or Git. See [Tailscale auth keys](https://tailscale.com/docs/features/access-control/auth-keys).

SSH is key-only and allowed through the firewall on `tailscale0`. Tailnet policy must also allow your Mac to reach the Pi on port 22. This repository does not enroll the physical Pi or modify its card automatically.
