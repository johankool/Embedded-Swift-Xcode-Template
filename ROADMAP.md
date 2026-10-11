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

## Done

- [x] ESP32-C3 and other RISC-V chips (ESP32-C2, C5, C61, H2, P4)
- [x] Code completion and jump to definition in Xcode (Xcode 27)
- [x] Template build test, run in CI for every chip
