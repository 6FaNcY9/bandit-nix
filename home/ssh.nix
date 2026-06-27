_: {
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
      "bandit-lab" = {
        Hostname = "192.168.1.2";
        User = "vino";
        IdentityFile = "~/.ssh/homelabKey";
        IdentitiesOnly = true;
      };
    };
  };
}
