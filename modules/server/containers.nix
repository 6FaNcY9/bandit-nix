# Podman next to Docker (spec step 3): services move to quadlet units one per
# PR in phase 4; until then Docker keeps its socket and the oci-containers backend.
{
  inputs,
  lib,
  ...
}: {
  imports = [inputs.quadlet-nix.nixosModules.quadlet];

  # Hardening (N5) is the default of every quadlet container, not a per-container
  # opt-in: this second declaration merges into quadlet-nix's own submodule.
  # A container relaxes one flag by setting it explicitly.
  options.virtualisation.quadlet.containers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      containerConfig = {
        noNewPrivileges = lib.mkDefault true;
        dropCapabilities = lib.mkDefault ["all"];
        readOnly = lib.mkDefault true;
      };
    });
  };

  config.virtualisation = {
    podman.enable = true;
    # Shared network for migrated services (phase 4): container names resolve
    # through aardvark-dns like on the Docker proxy network. Explicit subnet so
    # firewall rules can name it; collides with no LAN, tailnet or Docker range.
    quadlet.networks.proxy.networkConfig = {
      subnets = ["10.89.0.0/24"];
      gateways = ["10.89.0.1"];
    };
  };

  # Podman 6 only has the nftables driver: netavark's accepts live in its own nft table and do not
  # override Docker's FORWARD policy DROP in the iptables filter table, so forward is allowed here.
  # Same scope netavark's iptables chains had: anything from a podman bridge, only replies to it.
  # -C first: a firewall reload does not flush FORWARD, appending again would stack duplicates.
  config.networking.firewall.extraCommands = ''
    iptables -w -C FORWARD -i podman+ -j ACCEPT 2>/dev/null || iptables -w -A FORWARD -i podman+ -j ACCEPT
    iptables -w -C FORWARD -o podman+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -w -A FORWARD -o podman+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  '';
}
