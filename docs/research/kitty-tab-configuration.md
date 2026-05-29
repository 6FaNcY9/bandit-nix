# Kitty Terminal — Tab Bar & Configuration Research

Source: https://sw.kovidgoyal.net/kitty/conf/

## Tab Bar Options

### tab_bar_edge
```
tab_bar_edge bottom   # default
tab_bar_edge top      # move tabs to top
```
**Only `top` or `bottom`** — no left/right.

### tab_bar_style
```
tab_bar_style fade         # tabs fade into background (default)
tab_bar_style powerline    # powerline arrows between tabs  ← current setting
tab_bar_style slant        # diagonal separators
tab_bar_style separator    # custom char separator
tab_bar_style hidden       # hide the tab bar entirely
tab_bar_style custom       # Python script tab_bar.py in config dir
```

### tab_powerline_style (only when tab_bar_style = powerline)
```
tab_powerline_style angled   # default — sharp chevron >
tab_powerline_style slanted  # slanted slash /
tab_powerline_style round    # round parenthesis )
```

### Tab bar appearance
```
tab_bar_background none         # bar background (default = terminal bg)
tab_bar_background #111111      # set explicit color
tab_bar_margin_height 0.0 0.0   # above and below margin (pts)
tab_bar_margin_width 0.0        # left/right margin (pts)
tab_bar_align left              # left | center | right
tab_bar_min_tabs 2              # show bar only when ≥ N tabs open
tab_bar_show_new_tab_button no  # hide/show + button
```

### Active/inactive tab colors
```
active_tab_foreground   #1d2021   # text on active tab
active_tab_background   #d79921   # bg of active tab (golden yellow)
active_tab_font_style   bold
inactive_tab_foreground #a89984   # text on inactive tabs
inactive_tab_background #3c3836   # bg of inactive tabs
inactive_tab_font_style normal
tab_bar_margin_color    #282828   # color of margin areas around tabs
```

### Tab title template
```
tab_title_template "{index}: {title}"
tab_title_template "{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{index}: {title}"
```
Variables: `title`, `index`, `layout_name`, `num_windows`, `num_window_groups`,
`tab.active_wd`, `bell_symbol`, `activity_symbol`, `is_active`

### Custom tab bar (Python)
Create `~/.config/kitty/tab_bar.py`:
```python
from kitty.fast_data_types import Screen
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb, draw_title

def draw_tab(draw_data: DrawData, screen: Screen, tab: TabBarData,
             before: int, max_title_length: int, index: int, is_last: bool,
             extra_data: ExtraData) -> int:
    # Full control over tab rendering
    ...
```
See: https://github.com/kovidgoyal/kitty/discussions/4447

## Recommended Gruvbox Kitty Tab Config (bandit)

```nix
programs.kitty.settings = {
  # Move tabs to TOP
  tab_bar_edge = "top";
  tab_bar_style = "powerline";
  tab_powerline_style = "slanted";  # / style separators

  # Gruvbox tab colors
  tab_bar_background       = "#111111";
  active_tab_foreground    = "#1d2021";
  active_tab_background    = "#d79921";  # golden yellow
  active_tab_font_style    = "bold";
  inactive_tab_foreground  = "#a89984";
  inactive_tab_background  = "#282828";
  inactive_tab_font_style  = "normal";
  tab_bar_margin_color     = "#111111";

  # Title: show index + title
  tab_title_template = "{index}: {title}";

  # Show only when multiple tabs open
  tab_bar_min_tabs = "2";
};
```

## Other Key Kitty Config Options

### Window padding & appearance
```
window_padding_width 8         # inner padding
window_border_width 1pt        # border between split windows
draw_minimal_borders yes       # thinner borders for splits
```

### Layouts (split panes)
```
enabled_layouts tall,fat,horizontal,vertical,stack,grid
# tall    = one main window, others stacked on side
# fat     = one main at top, others below
# stack   = fullscreen tabs (no tiling)
# grid    = equal grid
```

### Remote control (needed for scripting)
```
allow_remote_control socket-only
listen_on unix:{kitty_pid}     # socket per instance
```

### Useful keybindings
```
# Split windows
map ctrl+shift+enter  new_window_with_cwd
map ctrl+shift+]      next_window
map ctrl+shift+[      previous_window

# Layouts
map ctrl+shift+l      next_layout

# Tabs
map ctrl+shift+t      new_tab_with_cwd
map ctrl+shift+,      move_tab_forward
map ctrl+shift+.      move_tab_backward
```

## Kitty Themes

Kitty has a built-in theme browser: `kitty +kitten themes`
- Lists all community themes (including gruvbox variants)
- Stylix manages colors automatically — theme can override specific elements

## Sources
- Official docs: https://sw.kovidgoyal.net/kitty/conf/
- Tab bar customization: https://github.com/kovidgoyal/kitty/discussions/4447
- Kitty themes: https://sw.kovidgoyal.net/kitty/kittens/themes/
