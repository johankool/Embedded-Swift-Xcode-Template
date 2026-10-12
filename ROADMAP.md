# Roadmap

This project is being developed as part of the [Swift Mentorship Program](https://www.swift.org/mentorship/). Contributions to any of these are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Near-term

- [ ] **Build without flashing.** `Cmd+B` currently builds and then flashes a connected board (in `build.sh`), like the Arduino IDE. Building should only build, so builds are faster and don't touch the board; flashing should be a separate step, for example as part of `Cmd+R`.
- [ ] **Run scheme without reopening the project** ([#3](https://github.com/letstakeabreak/Embedded-Swift-Xcode-Template/issues/3)). After the first build, the project has to be closed and reopened before `Cmd+R` shows the serial output, because `setup_scheme.sh` only writes the scheme during that build. The template could provide the scheme from the start, or the scheme could be written in a way Xcode picks up.
- [ ] **Code completion with Xcode 26.** The Indexing target is only verified with Xcode 27, and so is CI. Supporting Xcode 26 needs a test fixture (`tests/fixtures/project.pbxproj`) created by Xcode 26, and checking that its indexing works.
- [ ] **Test the other chips on hardware.** Only the ESP32-C6 has run on a board. The ESP32-C2, C3, C5, C61, H2 and P4 are tested by building only, including the per-chip LED pins and the LED over SPI on the C2 and C61.
- [ ] **Update existing projects after a Swift upgrade.** `install.sh` writes the installed Swift toolchain's identifier into the template, and projects keep the one they were created with. After installing a newer Swift, the Indexing target of existing projects has to be pointed at it by hand (its `TOOLCHAINS` build setting).
- [ ] **Cache downloads in CI.** Every CI run downloads and installs ESP-IDF, its tools and Swift (about 5 of its 11 minutes). Caching them between runs would make CI faster.
- [ ] Signed and notarized installer
- [ ] GPIO and I2C sensor examples
- [ ] Installer progress bar improvements ([#4](https://github.com/letstakeabreak/Embedded-Swift-Xcode-Template/issues/4))

## Longer-term

- [ ] `espswift-idf` Swift Package: idiomatic Swift wrappers for ESP-IDF APIs (GPIO, LED, timers, ...), so projects don't call C functions such as `led_strip_new_rmt_device` directly
- [ ] `espswift` CLI (doctor / build / flash / monitor)
- [ ] Homebrew tap
- [ ] ESP32-S3 support (needs Xtensa support in Swift)

## Ideas

Not planned yet; worth considering.

**Keeping projects up to date**
- [ ] **Version-stamp projects,** so a newer `install.sh` can detect old projects and offer to migrate them (for example replacing a pre-wrapper `build.sh`, or updating the Indexing target after a Swift upgrade).
- [ ] **`install.sh --update` or a version check,** so users learn about new releases.

**Running without hardware**
- [ ] **Run firmware in the [Wokwi](https://wokwi.com) simulator.** Wokwi simulates the ESP32-C3, C6, C61 and H2 (C5 in alpha, P4 in beta; see [its ESP32 guide](https://docs.wokwi.com/guides/esp32)). `Cmd+R` could run the firmware without a board, and the [Wokwi CLI](https://docs.wokwi.com/wokwi-ci/getting-started) could make CI check that it actually runs and prints the expected serial output, not just that it builds. Its free tier allows 50 minutes of simulation per 30 days.
- [ ] **Host-side unit tests:** test pure Swift logic in `Sources/` that doesn't use ESP-IDF on the Mac, with Swift Testing.

**Debugging**
- [ ] **On-chip debugging in Xcode:** the ESP32-C3, C5, C6, H2 and P4 have built-in USB-JTAG, so OpenOCD and LLDB could give breakpoints and stepping.
- [ ] **Decode crash backtraces:** turn the addresses in a panic dump into file and line numbers in the Xcode console, as ESP-IDF's monitor does.

**Everyday workflow**
- [ ] **Compiler errors as clickable Xcode issues:** make sure Swift and C errors from the ESP-IDF build show up in the Issue navigator and jump to the line, and filter the noise from the build log.
- [ ] **Choose the serial port** when several boards are connected; `detect_port.sh` picks the first one it finds.
- [ ] **Interactive serial input:** Xcode's console is output-only; a "Monitor in Terminal" action could open the serial monitor in Terminal for two-way communication.
- [ ] **Show the firmware size after each build** (`idf.py size`), so growth is visible before it hits the flash limit.
- [ ] **Faster builds with ccache,** which ESP-IDF supports for its C code.
- [ ] **Choose the board, not just the chip:** a Board pop-up (e.g. ESP32-C6-DevKitC-1 or DevKitM-1) could set the LED pin and flash size together.

**Examples and libraries**
- [ ] **Example projects:** Wi-Fi with an HTTP request, BLE, an I2C sensor, deep sleep; each a small project in an `Examples/` folder that CI builds as well.
- [ ] **Swift packages:** a way to use Embedded-compatible Swift packages (such as `swift-mmio`) from `Sources/`, as CMake can't use Swift Package Manager directly.

**Quality and reach**
- [ ] **More checks in CI:** ShellCheck for the scripts, `uninstall.sh`, and `install.sh`'s swiftly route (CI only uses swift.org's installer).
- [ ] **A VS Code and Cursor guide:** code completion already works there through `compile_commands.json`; also a step toward Linux support.
- [ ] **A documentation site:** a DocC tutorial ("your first firmware") built around the template.

## Done

- [x] ESP32-C3 and other RISC-V chips (ESP32-C2, C5, C61, H2, P4)
- [x] Code completion and jump to definition in Xcode (Xcode 27)
- [x] Template build test, run in CI for every chip
- [x] Each project's `build.sh` calls ESPSwift's installed build script, so updating ESPSwift updates the build of every project created from then on
