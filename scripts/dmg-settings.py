# dmgbuild settings for the installer window. Run through scripts/make-dmg.sh, which passes
# -D app=<path to .app> -D volicon=<.icns> -D background=<.tiff>.
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["volicon"]  # noqa: F821
background = defines["background"]  # noqa: F821

# The outer window frame: Finder's title bar and (user-enabled) path/status bars eat ~120 pt of it.
window_rect = ((200, 140), (660, 520))
default_view = "icon-view"
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 195),
    "Applications": (490, 195),
}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
