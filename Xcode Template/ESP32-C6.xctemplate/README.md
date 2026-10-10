# ___PROJECTNAME___

Embedded Swift firmware for the ESP32-C6, built with ESP-IDF.

## Everyday use in Xcode

| Shortcut | What it does |
| --- | --- |
| `Cmd+B` | Builds the firmware and flashes it to a connected board |
| `Cmd+R` | Shows the board's serial output in Xcode's console |
| `Cmd+Shift+K` | Cleans the build |

After the very first `Cmd+B`, close and reopen the project once so that `Cmd+R` shows the serial output.

## What's in this project

```
___PROJECTNAME___/
├── README.md                 # This file
├── ___PROJECTNAME___.xcodeproj
└── ___PROJECTNAME___/         # The source folder
    ├── build.sh              # Run by Xcode on Cmd+B: builds with ESP-IDF, then flashes
    ├── CMakeLists.txt        # ESP-IDF project file
    ├── sdkconfig.defaults    # Your ESP-IDF settings (see "Changing ESP-IDF settings")
    ├── sdkconfig             # Full ESP-IDF settings, created on first build
    └── main/
        ├── main.swift        # Your firmware code starts here
        ├── BridgingHeader.h  # C headers that Swift can use
        ├── idf_component.yml # Libraries this project depends on
        └── CMakeLists.txt    # Lists the Swift files to compile
```

Xcode keeps the build output in DerivedData, like any other Xcode project. **Product ▸ Show Build Folder in Finder** takes you there.

## Opening Terminal in the source folder

Some tasks below need Terminal. The commands must run in the source folder, the one that contains `build.sh` and `main/`.

In Xcode's Project navigator, Control-click the `___PROJECTNAME___` folder and choose **Open Terminal at Location**.

## Adding a library

Libraries come from the [ESP-IDF Component Registry](https://components.espressif.com). Each library page shows its name, such as `espressif/button`.

In Terminal, in the source folder, run:

```bash
~/.espswift/scripts/add_library.sh espressif/button iot_button.h
```

The first argument is the library's name. The second is the C header to include; check the library's documentation for it. If you leave it out, the script guesses it from the name (`button.h` here).

The script adds the library to `main/idf_component.yml` and the header to `main/BridgingHeader.h`. Press `Cmd+B` to download and build it, and then use its functions from Swift.

To remove a library, delete its line from `main/idf_component.yml` and its `#include` from `main/BridgingHeader.h`.

## Changing ESP-IDF settings

ESP-IDF settings, such as the CPU frequency, logging level or Wi-Fi options, live in `sdkconfig`. To change them with ESP-IDF's settings menu, run in Terminal, in the source folder:

```bash
source ~/.espswift/esp-idf/export.sh
idf.py menuconfig
```

Use the arrow keys and Return to navigate, and press `S` to save and `Q` to quit. Then press `Cmd+B` in Xcode.

To keep a setting even if `sdkconfig` is deleted, also add it to `sdkconfig.defaults`.

## Watching serial output in Terminal

`Cmd+R` shows the board's output in Xcode. To see it in Terminal instead, run:

```bash
~/.espswift/scripts/monitor.sh
```

Press `Ctrl+C` to stop.

## More help

See the [Embedded Swift Xcode Template](https://github.com/letstakeabreak/Embedded-Swift-Xcode-Template) README for troubleshooting.
