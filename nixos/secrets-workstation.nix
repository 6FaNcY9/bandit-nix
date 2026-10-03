{repoConfig, ...}: let
  inherit (repoConfig.workstation) homeDirectory username;
in {
  # Laptop-only secrets, kept in files the lab key cannot decrypt
  # (docs/runbooks/sops-split.md). bandit-lab never imports this module.
  sops = {
    defaultSopsFile = ../secrets/bandit.yaml;

    secrets = {
      "github_ssh_key" = {
        sopsFile = ../secrets/github.yaml;
        owner = username;
        path = "${homeDirectory}/.ssh/github";
        mode = "0600";
      };
      "github_ssh_key_banditstudent" = {
        sopsFile = ../secrets/github.yaml;
        owner = username;
        path = "${homeDirectory}/.ssh/github-banditstudent";
        mode = "0600";
      };
      "cachix-secret" = {
        owner = username;
        mode = "0400";
      };
      "context7_api_key" = {
        owner = username;
        mode = "0400";
      };
      "thehost-sshkey" = {
        owner = username;
        path = "${homeDirectory}/.ssh/thehost_mrija";
        mode = "0600";
      };
      "firecrawl-api-key" = {
        owner = username;
        mode = "0400";
      };
      "shodan-api-key" = {
        owner = username;
        mode = "0400";
      };
      "cloudflare-api-key" = {
        owner = username;
        mode = "0400";
      };
    };
  };
}
