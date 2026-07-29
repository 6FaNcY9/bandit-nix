{
  pkgs,
  repoConfig,
  ...
}: {
  # Client for the Cloudflare Access SSH path used by bandit-lab-wan below.
  home.packages = [pkgs.cloudflared];

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
      # LAN path — direct, fastest. Only reachable on the home network.
      "bandit-lab" = {
        Hostname = "192.168.1.2";
        User = repoConfig.workstation.username;
        IdentityFile = "~/.ssh/homelab";
        IdentitiesOnly = true;
      };
      # WAN path — same host, same key, tunnelled via Cloudflare Access.
      # Works from anywhere, including behind CGNAT. Requires `cloudflared`
      # locally and an Access policy on ssh-bandit-lab.mrija.org; the first
      # connection opens a browser for authentication.
      "bandit-lab-wan" = {
        Hostname = "ssh-bandit-lab.mrija.org";
        User = repoConfig.workstation.username;
        IdentityFile = "~/.ssh/homelab";
        IdentitiesOnly = true;
        ProxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
    };
  };
}
