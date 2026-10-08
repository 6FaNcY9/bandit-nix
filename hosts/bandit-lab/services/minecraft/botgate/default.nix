# BotGate Velocity plugin, compiled against the pinned Velocity API jar.
{pkgs}: let
  velocityJar = pkgs.fetchurl {
    url = "https://fill-data.papermc.io/v1/objects/b4e3164df5377346854dc6cb9e6a78022b1946ff69e89676313f5f6f1c6f0fb3/velocity-3.5.1-615.jar";
    hash = "sha256-tOMWTfU3c0aFTcbLnmp4AisZRv9p6JZ2MT9fbxxvD7M=";
  };
in
  pkgs.runCommand "botgate.jar" {nativeBuildInputs = [pkgs.jdk21_headless];} ''
    mkdir classes
    cp ${./BotGate.java} BotGate.java
    javac --release 21 -proc:none -Xlint:all -Werror -cp ${velocityJar} -d classes BotGate.java
    cp ${./velocity-plugin.json} classes/velocity-plugin.json
    jar --create --file $out --date 1980-01-01T00:00:02Z -C classes .
  ''
