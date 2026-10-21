# Home Manager wiring: the user tree gets the typed constants as `bandit`.
{config, ...}: {
  home-manager = {
    users.${config.bandit.workstation.username} = import ./user;
    extraSpecialArgs.bandit = config.bandit;
  };
}
