// swift-tools-version: 6.0

// The project's Swift code, as a Swift package. ESP-IDF builds it (with
// SwiftPM) into the firmware; `swift test` in this folder tests the plain
// Swift targets on the Mac.

import PackageDescription

// The firmware targets need ESP-IDF, so they're only part of the package
// when ESP-IDF builds it, which sets ESPSWIFT_FIRMWARE=1.
let buildingFirmware = Context.environment["ESPSWIFT_FIRMWARE"] == "1"

// Plain Swift, without ESP-IDF: code that runs on the Mac too, so its
// tests (in Tests/) run there with `swift test`.
var targets: [Target] = [
    .target(name: "Blink"),
    .testTarget(name: "BlinkTests", dependencies: ["Blink"]),
]
var products: [Product] = []
var dependencies: [Package.Dependency] = []

if buildingFirmware {
    targets += [
        // The firmware: app_main and everything that uses ESP-IDF.
        .target(name: "Firmware", dependencies: ["Blink", "ESPIDF"]),
        // ESP-IDF's C APIs, for `import ESPIDF` (see Sources/ESPIDF/include).
        .target(name: "ESPIDF"),
    ]
    // ESP-IDF links this library into the firmware.
    products.append(.library(name: "Firmware", type: .static, targets: ["Firmware"]))
    // Swift packages the firmware uses, such as:
    // dependencies.append(.package(url: "https://github.com/apple/swift-mmio.git", from: "0.1.1"))
    // and add `.product(name: "MMIO", package: "swift-mmio")` to Firmware's dependencies.
}

let package = Package(
    name: "___PROJECTNAME___",
    products: products,
    dependencies: dependencies,
    targets: targets
)
