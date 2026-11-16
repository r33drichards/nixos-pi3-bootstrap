{ pkgs, lib, ... }:
let
  upstream = import (pkgs.path + "/nixos/tests/headscale.nix") { inherit pkgs lib; };
  key = pkgs.runCommand "integration-only-ssh-key" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -q -t ed25519 -N "" -f $out/id_ed25519
  '';
in {
  name = "pi-tailscale-ssh";
  nodes = upstream.nodes // {
    peer1 = { ... }: {
      imports = [ upstream.nodes.peer1 ../modules/bootstrap.nix ];
      piBootstrap.tailscale = {
        authKeyFile = "/run/test-tailscale-authkey";
        extraUpFlags = [ "--login-server=https://headscale" ];
      };
      # Provision the disposable key before starting the production enrollment unit.
      systemd.services.tailscaled-autoconnect.wantedBy = lib.mkForce [];
      # Test-only fixture, never a real private key.
      users.users.root.openssh.authorizedKeys.keyFiles = [ "${key}/id_ed25519.pub" ];
    };
    peer2 = { ... }: {
      imports = [ upstream.nodes.peer2 ];
      environment.systemPackages = [ pkgs.openssh ];
    };
  };
  testScript = (builtins.replaceStrings [ "peer1.execute(up_cmd)" ] [ ''
      import shlex
      peer1.succeed("umask 077; printf %s " + shlex.quote(authkey.strip()) + " > /run/test-tailscale-authkey")
      peer1.succeed("systemctl start tailscaled-autoconnect")
      peer1.wait_until_succeeds("tailscale ip -4")
    '' ] upstream.testScript) + ''
    import json
    peer1.wait_for_unit("sshd.service")
    ip = peer1.succeed("tailscale ip -4").strip()
    peer2.succeed("install -m600 ${key}/id_ed25519 /root/test-key")
    ssh = f"ssh -i /root/test-key -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 root@{ip}"
    with subtest("OpenSSH key login works through Tailscale"):
        assert peer2.wait_until_succeeds(ssh + " 'echo tailnet-ssh-ok'").strip() == "tailnet-ssh-ok"
    with subtest("Enrollment survives tailscaled restart"):
        before = json.loads(peer1.succeed("tailscale status --json"))["Self"]["ID"]
        peer1.succeed("systemctl restart tailscaled")
        peer1.wait_until_succeeds("tailscale ping peer2", timeout=90)
        after = json.loads(peer1.succeed("tailscale status --json"))["Self"]["ID"]
        assert before == after, "Restart unexpectedly created another identity"
        peer2.wait_until_succeeds(ssh + " true")
  '';
}
