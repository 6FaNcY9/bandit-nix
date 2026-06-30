_: {
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    # Age private key for this host — must be provisioned at first boot:
    # install -m 0600 -D <host-age-privkey> /var/lib/sops-nix/key.txt
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false; # fail loudly if key not provisioned rather than silently creating a wrong one
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
      "github_ssh_key_banditstudent" = {
        sopsFile = ../secrets/github.yaml;
        owner = "vino";
        path = "/home/vino/.ssh/github-banditstudent";
        mode = "0600";
      };
      "cachix-secret" = {
        owner = "vino";
        mode = "0400";
      };
      "context7_api_key" = {
        owner = "vino";
        mode = "0400";
      };
      "vaultwarden-admin-token" = {
        mode = "0400";
      };
      "thehost-sshkey" = {
        owner = "vino";
        path = "/home/vino/.ssh/thehost_mrija";
        mode = "0600";
      };
      "firecrawl-api-key" = {
        owner = "vino";
        path = "/run/secrets/firecrawl-api-key";
        mode = "0400";
      };
    };
  };
}
