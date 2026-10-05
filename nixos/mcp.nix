{
  lib,
  pkgs,
  ...
}: let
  caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # Runs an MCP server in bubblewrap: empty environment, no $HOME, read-only
  # /nix/store, the one API key bind-mounted read-only and exported inside the
  # sandbox only, network shared. A compromised or malicious dependency then
  # cannot read ~/.ssh, other tokens in the shell environment, or the project.
  sandbox = pkgs.writeShellScript "mcp-sandbox" ''
    set -euo pipefail
    secret=$1 var=$2
    shift 2
    if [[ ! -r "$secret" ]]; then
      printf 'mcp-sandbox: missing readable secret %s\n' "$secret" >&2
      exit 1
    fi
    exec ${lib.getExe pkgs.bubblewrap} \
      --unshare-all --share-net --die-with-parent --new-session \
      --clearenv \
      --setenv PATH ${lib.makeBinPath [pkgs.coreutils]} \
      --setenv HOME /tmp --setenv TMPDIR /tmp --setenv LANG C.UTF-8 \
      --setenv SSL_CERT_FILE ${caBundle} \
      --setenv NODE_EXTRA_CA_CERTS ${caBundle} \
      --ro-bind /nix/store /nix/store \
      --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
      --ro-bind-try /etc/hosts /etc/hosts \
      --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
      --ro-bind-try /etc/passwd /etc/passwd \
      --ro-bind-try /etc/group /etc/group \
      --proc /proc --dev /dev --tmpfs /tmp \
      --ro-bind "$secret" /run/mcp-secret \
      -- ${pkgs.bash}/bin/bash -c 'export "$1=$(< /run/mcp-secret)"; shift; exec "$@"' mcp-sandbox "$var" "$@"
  '';

  mkMcp = {
    package,
    secret,
    envVar,
  }:
    pkgs.writeShellScriptBin package.meta.mainProgram ''
      exec ${sandbox} ${secret} ${envVar} ${lib.getExe package} "$@"
    '';
in {
  # Laptop only (imported from nixos/default.nix): bandit-lab has neither the
  # secrets nor a use for these tools. Packaged builds replace the former
  # `npx -y` wrappers, so nothing is downloaded from npm at run time.
  environment.systemPackages = [
    # Claude Code's own sandbox also needs bwrap on PATH.
    pkgs.bubblewrap
    (mkMcp {
      package = pkgs.context7-mcp;
      secret = "/run/secrets/context7_api_key";
      envVar = "CONTEXT7_API_KEY";
    })
    (mkMcp {
      package = pkgs.firecrawl-mcp;
      secret = "/run/secrets/firecrawl-api-key";
      envVar = "FIRECRAWL_API_KEY";
    })
  ];
}
