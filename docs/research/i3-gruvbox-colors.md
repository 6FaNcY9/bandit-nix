# i3wm — Gruvbox Color Scheme Research

## Standard Gruvbox i3 Palette (jmattheis/i3wm-gruvbox-dark)

Source: https://github.com/jmattheis/i3wm-gruvbox-dark

```
set $bg        #282828
set $red       #cc241d
set $green     #98971a
set $yellow    #d79921
set $blue      #458588
set $purple    #b16286
set $aqua      #689d68
set $gray      #a89984
set $darkgray  #1d2021
set $lightgray #bdae93
```

## i3 Client Color Format

```
# class                  border     background text       indicator  child_border
client.focused            $lightgray $lightgray $bg        $purple    $darkgray
client.focused_inactive   $darkgray  $darkgray  $lightgray $purple    $darkgray
client.unfocused          $darkgray  $darkgray  $lightgray $purple    $darkgray
client.urgent             $red       $red       $white     $red       $red
```

## Adapted for Wallpaper Palette (bandit)

Wallpaper-extracted dominant colors:
- `#2A2A2A` — background (≈ gruvbox bg)
- `#ECDBB5` — foreground/cream
- `#D79B24` — golden yellow (accent, matches $yellow perfectly)
- `#CD241D` — red
- `#478789` — teal/blue
- `#699E6C` — forest green
- `#BA3E1F` — orange-red
- `#1F1C17` — near-black warm

**Recommended bandit i3 client colors:**
```nix
coloredBorderFocused   = "#D79B24";   # golden yellow — stands out
coloredBorderUnfocused = "#3c3836";   # dark grey — recedes
coloredBorderUrgent    = "#cc241d";   # red
coloredBorderInactive  = "#3c3836";
```

## i3 Bar Colors (if using i3bar instead of xfce4-panel)

```
bar {
  colors {
    background $bg         # #282828
    statusline $lightgray  # #bdae93
    # border background text
    focused_workspace   $lightgray $lightgray $bg
    inactive_workspace  $darkgray  $darkgray  $lightgray
    active_workspace    $darkgray  $darkgray  $lightgray
    urgent_workspace    $red       $red       $bg
  }
}
```

## Gaps & Borders (retro flat aesthetic)

```nix
gaps = {
  inner = 8;
  outer = 4;
  smartGaps = true;
  smartBorders = "on";
};
window = {
  border = 2;    # pixel 2 — visible but not thick
  titlebar = false;
};
```

## Sources
- https://github.com/jmattheis/i3wm-gruvbox-dark
- YouTube: "Ricing i3 WM With Gruvbox Color Scheme - Timelapse" — TheLinuxCast
- r/unixporn — various i3 gruvbox rices
