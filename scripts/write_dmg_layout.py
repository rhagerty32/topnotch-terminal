#!/usr/bin/env python3
"""Write the Finder icon-view layout onto a mounted TopNotch Terminal disk image.

The background is Resources/dmg/background.png, copied to .background/background.png
before this runs. Icon positions are centers in the 720×440 point window.
Applications sits in the drawn notch. The app sits under the chevrons.
"""

from __future__ import annotations

import sys
from pathlib import Path

from mac_alias import Alias

WINDOW_BOUNDS = "{{280, 120}, {720, 440}}"
ICON_POSITIONS = {
    "TopNotch Terminal.app": (360, 292),
    "Applications": (360, 68),
}


def write_ds_store(path: Path, alias_bytes: bytes) -> None:
    from ds_store import DSStore

    if path.exists():
        path.unlink()
    bwsp = {
        "ShowStatusBar": False,
        "WindowBounds": WINDOW_BOUNDS,
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }
    icvp = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundColorRed": 0.0,
        "backgroundColorGreen": 0.0,
        "backgroundColorBlue": 0.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 12.0,
        "iconSize": 80.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
        "backgroundImageAlias": alias_bytes,
    }
    with DSStore.open(str(path), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = bwsp
        store["."]["icvp"] = icvp
        store["."]["icvl"] = ("type", b"icnv")
        for name, point in ICON_POSITIONS.items():
            store[name]["Iloc"] = point
        store[".background"]["Iloc"] = (8000, 8000)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: write_dmg_layout.py /Volumes/TopNotch Terminal")
    mount = Path(sys.argv[1])
    background = mount / ".background" / "background.png"
    if not background.is_file():
        raise SystemExit(f"missing background: {background}")
    if not (mount / "TopNotch Terminal.app").exists():
        raise SystemExit(f"missing app on {mount}")
    if not (mount / "Applications").is_symlink():
        raise SystemExit(f"missing Applications link on {mount}")
    alias = Alias.for_file(str(background))
    write_ds_store(mount / ".DS_Store", alias.to_bytes())
    print(f"Wrote Finder layout on {mount}")


if __name__ == "__main__":
    main()
