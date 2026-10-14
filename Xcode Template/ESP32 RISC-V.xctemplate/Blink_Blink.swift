//
//  Blink.swift
//  ___PROJECTNAME___
//
//  Created by ___FULLUSERNAME___ on ___DATE___.
//

// The blink pattern, in plain Swift: it doesn't use ESP-IDF, so it can be
// tested on the Mac (see Tests/BlinkTests).

/// One step of the blink pattern: a color for the LED and its name.
public struct BlinkStep: Equatable {
    public var red: UInt32
    public var green: UInt32
    public var blue: UInt32
    public var name: StaticString

    public init(red: UInt32, green: UInt32, blue: UInt32, name: StaticString) {
        self.red = red
        self.green = green
        self.blue = blue
        self.name = name
    }

    public static func == (lhs: BlinkStep, rhs: BlinkStep) -> Bool {
        lhs.red == rhs.red && lhs.green == rhs.green && lhs.blue == rhs.blue
    }
}

/// Cycles through red, green, blue and off.
/// - Parameters:
///   - index: The step number; the pattern repeats every 4 steps.
///   - brightness: The color's brightness, 0–255. Low by default, as the
///     LED is very bright.
public func blinkStep(_ index: UInt32, brightness: UInt32 = 32) -> BlinkStep {
    switch index % 4 {
    case 0: BlinkStep(red: brightness, green: 0, blue: 0, name: "Red")
    case 1: BlinkStep(red: 0, green: brightness, blue: 0, name: "Green")
    case 2: BlinkStep(red: 0, green: 0, blue: brightness, name: "Blue")
    default: BlinkStep(red: 0, green: 0, blue: 0, name: "Off")
    }
}
