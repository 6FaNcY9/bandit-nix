# Laptop root for the new module tree (phase 2 replaces nixos/ group by group).
# A flat list, not a module: the module system orders list-typed options by
# import depth, so wrapping the groups in one more module would reorder
# systemPackages against nixos-hardware and break the parity check.
[
  ./options.nix
  ./system
  ./desktop
  ./home-manager.nix
]
