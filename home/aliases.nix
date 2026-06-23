# Shell-agnostic aliases shared by fish (home/shell.nix) and zsh
# (home/terminal/zsh.nix). Fish abbreviations (shellAbbrs) live in
# shell.nix because zsh has no equivalent concept; per-shell aliases
# (`reload`, `paths`) live in each respective file because their
# implementations differ between shells.
{
  # ── Nix workflow ──────────────────────────────────────
  ns = "nh os switch";
  nt = "nh os test";
  nfu = "nix flake update";
  ngc = "nix-collect-garbage -d";
  nd = "nix develop";
  nsn = "nix search nixpkgs";

  # ── Navigation ────────────────────────────────────────
  ll = "eza -la --icons --git";
  la = "eza -la --icons --git";
  lt = "eza --tree --icons --level=2";
  lta = "eza --tree --icons --level=3 -a";
  cat = "bat";
  home = "cd ~";
  csrc = "cd ~/src";
  cnix = "cd ~/src/bandit-nix";
  cconf = "cd ~/.config";
  cproj = "cd ~/Projects";
  cdocs = "cd ~/Documents";
  cdl = "cd ~/Downloads";
  cvms = "cd ~/vms";
  cpic = "cd ~/Pictures";

  # ── Git ───────────────────────────────────────────────
  g = "git";
  ga = "git add";
  gc = "git commit";
  gca = "git commit --amend";
  gp = "git push";
  gl = "git pull";
  gs = "git status";
  gd = "git diff";
  glog = "git log --oneline --decorate --graph";

  # ── Editor ────────────────────────────────────────────
  v = "nvim";
  vi = "nvim";
  vim = "nvim";

  # ── System ────────────────────────────────────────────
  ports = "ss -tulanp";
  psg = "ps aux | grep";
  cls = "clear";

  # ── Network ───────────────────────────────────────────
  myip = "curl -sf ifconfig.me";
}
