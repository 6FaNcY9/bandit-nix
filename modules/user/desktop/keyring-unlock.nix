{pkgs, ...}: let
  keyringUnlock = pkgs.writers.writePython3Bin "keyring-unlock" {
    libraries = [pkgs.python3Packages.jeepney];
  } (builtins.readFile ./keyring-unlock.py);
in {
  # Fingerprint login leaves the GNOME keyring locked (no password reaches
  # PAM). The keyring password is sealed once to this laptop's TPM as a
  # user-scoped credential; the owner creates it with:
  #   systemd-ask-password -n "Keyring-Passwort:" | systemd-creds --user encrypt --with-key=host+tpm2 --name=keyring - ~/.local/state/keyring.cred
  systemd.user.services.keyring-tpm-unlock = {
    Unit = {
      Description = "Unlock the GNOME keyring with the TPM-sealed password";
      ConditionPathExists = "%h/.local/state/keyring.cred";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      LoadCredentialEncrypted = "keyring:%h/.local/state/keyring.cred";
      # Unlock only the TPM-sealed "Default Keyring" (the alias), used by Brave
      # and Claude's Safe Storage. The separate "Login" collection was removed
      # (its password drifted and prompted); gh (go-keyring) now falls back to
      # the Default alias, so there is nothing else to unlock here.
      ExecStart = "${pkgs.bash}/bin/bash -c '${keyringUnlock}/bin/keyring-unlock < \"$CREDENTIALS_DIRECTORY/keyring\"'";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
