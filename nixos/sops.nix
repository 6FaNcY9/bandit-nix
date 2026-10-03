_: {
  sops = {
    # Deliberately no defaultSopsFile here: each host must pick its own
    # (nixos/secrets-workstation.nix for the laptop, nixos/server/default.nix
    # for bandit-lab), so a host that forgets fails at evaluation instead of
    # silently inheriting another host's file. See docs/runbooks/sops-split.md.
    #
    # Age private key for this host — must be provisioned at first boot:
    # install -m 0600 -D <host-age-privkey> /var/lib/sops-nix/key.txt
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false; # fail loudly if key not provisioned rather than silently creating a wrong one
      sshKeyPaths = [];
    };

    secrets."user-password".neededForUsers = true;
  };
}
