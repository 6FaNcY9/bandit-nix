{...}: {
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    # Age private key for this host — must be provisioned at first boot:
    # install -m 0600 -D <host-age-privkey> /var/lib/sops-nix/key.txt
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
      sshKeyPaths = [];
    };

    secrets = {
      "user-password" = {
        neededForUsers = true;
      };
      "github_ssh_key" = {
        sopsFile = ../secrets/github.yaml;
        owner = "vino";
        path = "/home/vino/.ssh/github";
        mode = "0600";
      };
      "cachix-secret" = {
        owner = "vino";
        mode = "0400";
      };
    };
  };
}
