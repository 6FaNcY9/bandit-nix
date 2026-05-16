_: {
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    jack.enable = true;
    wireplumber.enable = true;

    extraConfig.pipewire."92-low-latency" = {
      context.properties = {
        default = {
          clock = {
            rate = 48000;
            quantum = 1024;
            min-quantum = 32;
            max-quantum = 8192;
          };
        };
      };
    };
  };

  # Framework 13 AMD speaker fix
  boot.extraModprobeConfig = ''
    options snd-hda-intel model=auto
  '';
}