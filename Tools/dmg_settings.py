# dmgbuild settings for the Voice Pipes installer DMG (lays out the window without driving Finder, so it works on CI).
#   dmgbuild -s Tools/dmg_settings.py -D app="path/Voice Pipes.app" -D background=path/background.tiff "Voice Pipes" out.dmg
import os.path

application = defines["app"]
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
hide_extension = [appname]

background = defines["background"]
window_rect = ((200, 120), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
# Matches the arrow in Tools/make_dmg_background.swift.
icon_locations = {appname: (170, 190), "Applications": (470, 190)}
