{modulesPath, ...}: let
  rootDev = "/dev/disk/by-uuid/0629aaee-1698-49d1-b3e1-e7bb6b957cda";
  btrfsDefaults = ["compress=zstd" "noatime" "discard=async"];
  btrfsSubvol = subvol: extraOpts: {
    device = rootDev;
    fsType = "btrfs";
    options = ["subvol=${subvol}"] ++ extraOpts;
  };
in {
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
    "/" = btrfsSubvol "@" btrfsDefaults;
    "/home" = btrfsSubvol "@home" btrfsDefaults;
    "/nix" = btrfsSubvol "@nix" btrfsDefaults;
    "/var" = btrfsSubvol "@var" btrfsDefaults;
    "/.snapshots" = btrfsSubvol "@/.snapshots" btrfsDefaults;
    "/home/.snapshots" = btrfsSubvol "@home/.snapshots" btrfsDefaults;
    "/boot" = {
      device = "/dev/disk/by-uuid/CC4A-AF6B";
      fsType = "vfat";
      options = ["fmask=0077" "dmask=0077"];
    };
  };

  swapDevices = [];
}
