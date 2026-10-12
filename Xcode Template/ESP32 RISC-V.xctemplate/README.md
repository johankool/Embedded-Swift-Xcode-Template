# ___PROJECTNAME___

Embedded Swift firmware for an ESP32 (`___VARIABLE_chip___`), built with ESP-IDF.

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
├── Sources/                  # Your Swift code
│   └── main.swift            # Your firmware code starts here
└── ___PROJECTNAME___/         # The ESP-IDF project (the "source folder")
    ├── build.sh              # Run by Xcode on Cmd+B: calls ESPSwift's build script (ESP-IDF build, then flash)
    ├── CMakeLists.txt        # ESP-IDF project file
    ├── sdkconfig.defaults    # The chip and your ESP-IDF settings
    ├── sdkconfig             # Full ESP-IDF settings, created on first build
    ├── compile_commands.json # Compiler settings for code completion, created by every build
    ├── .espswift/            # The same for Xcode's Indexing target (hidden)
    └── main/
        ├── BridgingHeader.h  # C headers that Swift can use
        ├── idf_component.yml # Libraries this project depends on
        └── CMakeLists.txt    # Compiles every .swift file in Sources/
```

To add a Swift file, create it in `Sources/` (also in a subfolder), and tick the **Indexing** target in the dialog for the new file so it gets code completion (see below). It's compiled into your firmware on the next `Cmd+B`; there's no list of files to update.

Xcode keeps the build output in DerivedData, like any other Xcode project. **Product ▸ Show Build Folder in Finder** takes you there.

## Code completion

Code completion, jump to definition (Command-click) and inline errors work for your Swift code and for ESP-IDF's C APIs, **after the first `Cmd+B`**: the build provides Xcode with ESP-IDF's compiler settings, and updates them on every build.

This is what the project's second target, **Indexing**, is for. Xcode doesn't index the main target, because ESP-IDF builds it, so it indexes the Indexing target instead. You never need to build it or choose its scheme.

The Indexing target contains the Swift files in `Sources/`. For a file that doesn't get completion, select it and tick **Indexing** under **Target Membership** in the File inspector.

Other editors with Swift support, such as VS Code and Cursor, use `compile_commands.json` in the source folder.

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

## Changing the chip

The chip you chose when creating the project is set in `sdkconfig.defaults`:

```
CONFIG_IDF_TARGET="___VARIABLE_chip___"
```

To build for another RISC-V based ESP32 (`esp32c2`, `esp32c3`, `esp32c5`, `esp32c6`, `esp32c61`, `esp32h2` or `esp32p4`), change this line and press `Cmd+B`. The build then reconfigures the project for the new chip, which recreates `sdkconfig` from `sdkconfig.defaults` (the previous one is kept as `sdkconfig.old`).

The example blinks the RGB LED of Espressif's DevKit boards. Its pin is chosen per chip in `main/BridgingHeader.h` (`BOARD_RGB_LED_GPIO`); change it there if your board's LED is on another pin.

## Watching serial output in Terminal

`Cmd+R` shows the board's output in Xcode. To see it in Terminal instead, run:

```bash
~/.espswift/scripts/monitor.sh
```

Press `Ctrl+C` to stop.

## More help

See the [Embedded Swift Xcode Template](https://github.com/letstakeabreak/Embedded-Swift-Xcode-Template) README for troubleshooting.
