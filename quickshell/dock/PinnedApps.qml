pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property var apps: [
        { id: "ghostty",            label: "Ghostty",       icon: "com.mitchellh.ghostty"                          },
        { id: "zen",                label: "Zen",           icon: "zen-browser",           execName: "zen-browser" },
        { id: "zeditor",            label: "Zed",           icon: "zed"                                            },
        { id: "spotify-launcher",   label: "Spotify",       icon: "spotify"                                        },
        { id: "steam",              label: "Steam",         icon: "steam"                                          },
        { id: "bitwig-studio",      label: "Bitwig Studio", icon: "bitwig-studio"                                  },
        { id: "blender",            label: "Blender",       icon: "blender"                                        },
        { id: "steam_app_431730",   label: "Aseprite",      icon: "steam_icon_431730", steamId: "431730"           },
        { id: "org.gnome.Nautilus", label: "Files",         icon: "system-file-manager", execName: "nautilus"     }
    ]
}
