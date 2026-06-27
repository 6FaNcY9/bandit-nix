# Run `nixos-generate-config` on bandit-lab and replace device paths with
# stable /dev/disk/by-uuid or /dev/disk/by-partuuid entries before installing.
#
# Confirmed Windows layout on the 4 TB Corsair MP600 PRO NVMe:
#   /dev/nvme0n1p1  100 MiB  EFI System Partition
#   /dev/nvme0n1p2   16 MiB  Microsoft Reserved - do not use for NixOS
#   /dev/nvme0n1p3  1.3 TiB  Windows C: - do not use for NixOS
#   /dev/nvme0n1p4  538 MiB  Windows Recovery
#   /dev/nvme0n1p5  2.7 TiB  NixOS target, format as BTRFS
{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}: let
  rootDev = "/dev/disk/by-uuid/620b7a32-8630-41f6-9d7b-8d694abdaa38";
  btrfsDefaults = ["subvol=@" "noatime" "compress=zstd" "space_cache=v2" "discard=async"];
  btrfsSubvol = subvol: {
    device = rootDev;
    fsType = "btrfs";
    options = ["subvol=${subvol}" "noatime" "compress=zstd" "space_cache=v2" "discard=async"];
  };
in {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # ── Boot ──────────────────────────────────────────────────────────────────
  # GRUB + separate /efi mount: kernels/initrds go to BTRFS (unlimited),
  # only the ~2 MB GRUB EFI binary lands on the 100 MiB Windows-shared ESP.
  boot.loader = {
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      useOSProber = false;
      configurationLimit = 10;
    };
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/efi";
    };
  };

  # ── CPU ───────────────────────────────────────────────────────────────────
  boot.kernelModules = ["kvm-intel"];
  hardware = {
    cpu = {
      amd.updateMicrocode = lib.mkForce false;
      intel.updateMicrocode = true;
    };

    # ── GPU — NVIDIA GeForce RTX 4090 Laptop ───────────────────────────────
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
      modesetting.enable = true;
      open = false;
      nvidiaSettings = false; # headless server
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      powerManagement.enable = true;
    };
  };
  services.xserver.videoDrivers = ["nvidia"];
  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];

  # ── Filesystems — BTRFS with subvolumes ──────────────────────────────────
  # Before installing: mkfs.btrfs /dev/nvme0n1p5 then mount and create subvols:
  #   btrfs subvolume create @
  #   btrfs subvolume create @home
  #   btrfs subvolume create @nix
  #   btrfs subvolume create @log
  #   btrfs subvolume create @snapshots
  fileSystems = {
    "/" = {
      device = rootDev;
      fsType = "btrfs";
      options = btrfsDefaults;
    };
    "/home" = btrfsSubvol "@home";
    "/nix" = btrfsSubvol "@nix";
    "/var/log" = (btrfsSubvol "@log") // {neededForBoot = true;};
    "/.snapshots" = btrfsSubvol "@snapshots";
    "/efi" = {
      device = "/dev/disk/by-uuid/C625-99B7";
      fsType = "vfat";
      options = ["fmask=0077" "dmask=0077"];
    };
  };

  swapDevices = []; # zram configured in server.nix

  nixpkgs.hostPlatform = "x86_64-linux";
}
