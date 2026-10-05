{repoConfig, ...}: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      # ── Global defaults ───────────────────────────────────────
      "*" = {
        HashKnownHosts = "yes";
        ServerAliveInterval = 60;
        ServerAliveCountMax = 3;
      };

      # ── Git hosting ───────────────────────────────────────────
      "github.com" = {
        Hostname = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/github";
        IdentitiesOnly = true;
      };
      # Explicit alias for main account — use in remotes as git@6FaNcY9:user/repo
      "6FaNcY9" = {
        Hostname = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/github";
        IdentitiesOnly = true;
      };
      "BanditStudent" = {
        Hostname = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/github-banditstudent";
        IdentitiesOnly = true;
      };

      # ── Servers ───────────────────────────────────────────────
      "mrija" = {
        Hostname = "s16.thehost.com.ua";
        User = "mrija_org";
        IdentityFile = "~/.ssh/thehost_mrija";
        IdentitiesOnly = true;
      };
      # The only path to the lab: its tailnet address, reachable from any
      # network. sshd listens on tailscale0 only; the public Cloudflare SSH
      # route and the direct-LAN path were removed (docs/runbooks/cloudflare-access.md).
      "bandit-lab bandit-lab-ts" = {
        Hostname = repoConfig.lab.tailscaleIp;
        User = repoConfig.workstation.username;
        IdentityFile = "~/.ssh/homelabKey";
        IdentitiesOnly = true;
      };
    };
  };
}
