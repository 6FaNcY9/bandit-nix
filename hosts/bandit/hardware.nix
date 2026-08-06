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

  # Temporary workaround for the reported spacebar phantom presses and partial
  # backlight failure. Root cause is not confirmed: inspect the key mechanism,
  # contact, and keyboard ribbon before deciding whether to replace the input
  # cover. Until then, keyd drops the spacebar and maps both Caps Lock and
  # Right Ctrl to space. Scoped to the internal keyboard only, so external
  # keyboards keep their spacebar. NOTE: hwdb keymaps from earlier generations
  # persist in the atkbd driver until reboot or `setkeycodes`; if Caps Lock
  # appears dead after changing this, run `sudo setkeycodes 39 57; sudo
  # setkeycodes 3a 58` (or reboot) to restore the default scancode map.
  services.keyd = {
    enable = true;
    keyboards.internal = {
      ids = ["0001:0001"];
      settings.main = {
        space = "noop";
        capslock = "space";
        rightcontrol = "space";
      };
    };
  };
}
