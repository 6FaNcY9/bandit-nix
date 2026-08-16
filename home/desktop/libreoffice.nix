{
  config,
  pkgs,
  ...
}: let
  cfgDir = "${config.xdg.configHome}/libreoffice/4/user";

  # One item of the default save-format list: ODT stays the default for
  # Writer; Spreadsheets/Presentations default to OOXML for compatibility.
  # Factory node names verified against upstream officecfg Setup.xcu.
  ooxmlDefault = name: value: ''
    <item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory['${name}']/DefaultFilter">
      <value>${value}</value>
    </item>
  '';
in {
  # Home Manager has no programs.libreoffice module — the previous version of
  # this file declared one anyway (dead code) and, worse, the file was never
  # imported from home/default.nix, so this repo never installed LibreOffice
  # at all. This module installs the suite directly and manages its
  # configuration via the XCU registry in ~/.config/libreoffice/4/user.
  #
  # The registry file is declarative: Home Manager replaces it on every
  # activation, so options flipped in the GUI survive only until the next
  # rebuild. That trade-off is deliberate — GUI drift resets automatically.
  # NOTE: libreoffice-still + dictionaries add ~1.5 GB to the home profile.

  home = {
    packages = [
      pkgs.libreoffice-still
      pkgs.hunspell
      # German spell-checking for the de-DE document locale (igerman98 ships
      # hyph_de_DE patterns, so hyphenation and thesauri come along); English
      # stays available alongside it.
      pkgs.hunspellDicts.de_DE
      pkgs.hunspellDicts.en_US
    ];

    file."${cfgDir}/registrymodifications.xcu".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <oor:items xmlns:oor="http://openoffice.org/2001/registry"
                 xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

        <!-- Document author metadata — same identity as home/git.nix. -->
        <item oor:path="/org.openoffice.UserProfile/Data">
          <prop oor:name="o" oor:op="fuse">
            <value>29282675+6FaNcY9@users.noreply.github.com</value>
          </prop>
          <prop oor:name="givenname" oor:op="fuse">
            <value>6FaNcY9</value>
          </prop>
        </item>

        <!-- Locale/currency default to German (Europe/Vienna system), UI and
             spell-checking stay English. -->
        <item oor:path="/org.openoffice.Office.Linguistic/General">
          <prop oor:name="DefaultLocale" oor:op="fuse">
            <value>de-DE</value>
          </prop>
          <prop oor:name="UILocale" oor:op="fuse">
            <value>en-US</value>
          </prop>
        </item>

        <!-- Documents never execute macros (level 3 = Very High). -->
        <item oor:path="/org.openoffice.Office.Common/Security/Scripting">
          <prop oor:name="MacroSecurityLevel" oor:op="fuse">
            <value>3</value>
          </prop>
        </item>

        <!-- Default save formats: ODF for text documents, OOXML for
             spreadsheets/presentations (interoperability with MS Office). -->
        ${ooxmlDefault "com.sun.star.text.TextDocument" "writer8"}
        ${ooxmlDefault "com.sun.star.sheet.SpreadsheetDocument" "Calc MS Excel 2007 XML"}
        ${ooxmlDefault "com.sun.star.presentation.PresentationDocument" "Impress MS PowerPoint 2007 XML"}
      </oor:items>
    '';
  };
}
