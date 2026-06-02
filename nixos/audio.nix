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
      # PipeWire expects flat dot-notation keys, not nested attrsets.
      # Nested attrsets generate {"default":{"clock":{...}}} which is silently ignored.
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 32;
        "default.clock.max-quantum" = 8192;
      };
    };
  };

  # Framework 13 AMD speaker fix
  boot.extraModprobeConfig = ''
    options snd-hda-intel model=auto
  '';
}
