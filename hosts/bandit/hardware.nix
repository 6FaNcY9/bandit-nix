{modulesPath, ...}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "thunderbolt"
        "usb_storage"
        "uas"
        "sd_mod"
      ];
      kernelModules = [];
    };
    kernelModules = ["kvm-amd"];
    extraModulePackages = [];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
      fsType = "btrfs";
      options = ["subvol=@" "compress=zstd" "noatime" "discard=async"];
    };
    "/home" = {
      device = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
      fsType = "btrfs";
      options = ["subvol=@home" "compress=zstd" "noatime" "discard=async"];
    };
    "/nix" = {
      device = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
      fsType = "btrfs";
      options = ["subvol=@nix" "compress=zstd" "noatime" "discard=async"];
    };
    "/var" = {
      device = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
      fsType = "btrfs";
      options = ["subvol=@var" "compress=zstd" "noatime" "discard=async"];
    };
    "/swap" = {
      device = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
      fsType = "btrfs";
      options = ["subvol=@swap" "noatime" "discard=async"];
    };
    "/.snapshots" = {
      device = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
      fsType = "btrfs";
      options = ["subvol=@/.snapshots" "compress=zstd" "noatime" "discard=async"];
    };
    "/home/.snapshots" = {
      device = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
      fsType = "btrfs";
      options = ["subvol=@home/.snapshots" "compress=zstd" "noatime" "discard=async"];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/CC4A-AF6B";
      fsType = "vfat";
      options = ["fmask=0077" "dmask=0077"];
    };
  };

  swapDevices = [];
}
