# Typed repository constants. Defaults come from lib/repository.nix so the
# old tree (nixos/, read via the repoConfig specialArg) and the new one agree.
{lib, ...}: let
  repo = import ../lib/repository.nix {inherit lib;};
  inherit (lib) mkOption types;
  str = default:
    mkOption {
      inherit default;
      type = types.str;
    };
in {
  options.bandit = {
    workstation = {
      username = str repo.workstation.username;
      homeDirectory = str repo.workstation.homeDirectory;
      repoPath = str repo.workstation.repoPath;
    };

    lab = {
      tailscaleIp = str repo.lab.tailscaleIp;
      workstationTailscaleIp = str repo.lab.workstationTailscaleIp;
      tailnetFqdn = str repo.lab.tailnetFqdn;
      mcbotsWorkerServePort = mkOption {
        type = types.port;
        default = repo.lab.mcbotsWorkerServePort;
      };
    };

    backupPeer = {
      port = mkOption {
        type = types.port;
        default = repo.backupPeer.port;
      };
      retention = mkOption {
        type = types.listOf types.str;
        default = repo.backupPeer.retention;
      };
    };

    unfreePackageNames = mkOption {
      type = types.listOf types.str;
      default = repo.unfreePackageNames;
    };
  };
}
