{pkgs, ...}: {
  home.packages = with pkgs; [
    ffmpegthumbnailer
    mpv
    pcmanfm
    poppler-utils
    tumbler
    viewnior
    xarchiver
  ];

  # PCManFM defaults to useful previews and a compact, keyboard-friendly
  # layout. Thumbnail generation is provided by Tumbler, Poppler and FFmpeg.
  xdg.configFile."pcmanfm/default/pcmanfm.conf".text = ''
    [config]
    bm_open_method=0

    [volume]
    mount_on_startup=1
    mount_removable=1
    autorun=1

    [ui]
    always_show_tabs=0
    close_on_unmount=1
    side_pane_mode=places
    view_mode=icon
    show_hidden=0
    show_thumbnail=1
    thumbnail_max=2048
    big_icon_size=64
    small_icon_size=24
    side_pane_icon_size=24
    sort=name;ascending;
    toolbar=newtab;navigation;home;
    show_statusbar=1
    pathbar_mode_buttons=1
  '';

  xdg = {
    desktopEntries.nvim-pdf = {
      name = "PDF Reader (Neovim)";
      genericName = "PDF Viewer";
      comment = "Read PDFs inside Neovim with pdfreader.nvim";
      exec = "${pkgs.kitty}/bin/kitty --class nvim-pdf nvim %f";
      icon = "application-pdf";
      terminal = false;
      categories = ["Office" "Viewer"];
      mimeType = ["application/pdf"];
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "inode/directory" = ["pcmanfm.desktop"];
        "application/pdf" = ["nvim-pdf.desktop"];

        "image/bmp" = ["viewnior.desktop"];
        "image/gif" = ["viewnior.desktop"];
        "image/jpeg" = ["viewnior.desktop"];
        "image/png" = ["viewnior.desktop"];
        "image/svg+xml" = ["viewnior.desktop"];
        "image/tiff" = ["viewnior.desktop"];
        "image/webp" = ["viewnior.desktop"];

        "video/mp4" = ["mpv.desktop"];
        "video/webm" = ["mpv.desktop"];
        "video/x-matroska" = ["mpv.desktop"];

        "application/gzip" = ["xarchiver.desktop"];
        "application/vnd.rar" = ["xarchiver.desktop"];
        "application/x-7z-compressed" = ["xarchiver.desktop"];
        "application/x-bzip2" = ["xarchiver.desktop"];
        "application/x-rar" = ["xarchiver.desktop"];
        "application/x-tar" = ["xarchiver.desktop"];
        "application/zip" = ["xarchiver.desktop"];
      };
    };
  };
}
