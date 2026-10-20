# Laptop only. GitHub CI pushes to this cache without a signed-commit gate, so a
# host that trusts it accepts store paths from whoever controls the workflow or
# its CACHIX_AUTH_TOKEN. bandit-lab deploys only GPG-signed commits
# (auto-rebuild) and must not trust this side channel; it builds what
# cache.nixos.org does not have. The `lab-cache-trust` flake check enforces it.
{
  nix.settings = {
    substituters = ["https://github-bandit-nix.cachix.org"];
    trusted-public-keys = [
      "github-bandit-nix.cachix.org-1:iaqre/ibQyXnNT8oRzHQHJ4UQfzvGAaFooRXs8v+Hks="
    ];
  };
}
