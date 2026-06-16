# Run `nixos-generate-config` on bandit-lab and verify disk UUIDs/devices.
# Assumed layout: NVMe, GPT, UEFI, single 3 TB BTRFS volume.
{
  config,
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # ── Boot ──────────────────────────────────────────────────────────────────
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ── CPU ───────────────────────────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode = true;

  # ── GPU — NVIDIA 5090 Ti ──────────────────────────────────────────────────
  hardware.nvidia = {
    modesetting.enable = true;
    open = true; # open kernel module required for Blackwell (50xx series)
    nvidiaSettings = false; # headless server
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = true;
  };
  # No xserver — headless server. NVIDIA kernel module loaded via hardware.nvidia.

  # ── Filesystems — BTRFS with subvolumes ──────────────────────────────────
  # Replace /dev/nvme0n1 with actual device from nixos-generate-config.
  # Before installing: mkfs.btrfs /dev/nvme0n1p2 then mount and create subvols:
  #   btrfs subvolume create @
  #   btrfs subvolume create @home
  #   btrfs subvolume create @nix
  #   btrfs subvolume create @log
  #   btrfs subvolume create @snapshots
  fileSystems = {
    "/" = {
      device = "/dev/nvme0n1p2";
      fsType = "btrfs";
      options = ["subvol=@" "noatime" "compress=zstd" "space_cache=v2" "discard=async"];
    };
    "/home" = {
      device = "/dev/nvme0n1p2";
      fsType = "btrfs";
      options = ["subvol=@home" "noatime" "compress=zstd" "space_cache=v2" "discard=async"];
    };
    "/nix" = {
      device = "/dev/nvme0n1p2";
      fsType = "btrfs";
      options = ["subvol=@nix" "noatime" "compress=zstd" "space_cache=v2" "discard=async"];
    };
    "/var/log" = {
      device = "/dev/nvme0n1p2";
      fsType = "btrfs";
      options = ["subvol=@log" "noatime" "compress=zstd" "space_cache=v2" "discard=async"];
      neededForBoot = true;
    };
    "/.snapshots" = {
      device = "/dev/nvme0n1p2";
      fsType = "btrfs";
      options = ["subvol=@snapshots" "noatime" "compress=zstd" "space_cache=v2" "discard=async"];
    };
    "/boot" = {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
      options = ["fmask=0077" "dmask=0077"];
    };
  };

  swapDevices = []; # zram configured in server.nix

  nixpkgs.hostPlatform = "x86_64-linux";
}
