//
//  BlinkTests.swift
//  ___PROJECTNAME___
//
//  Created by ___FULLUSERNAME___ on ___DATE___.
//

// Tests for the Blink target, run on the Mac: `swift test` in the project
// folder (the one with Package.swift).

import Blink
import Testing

@Test func cyclesThroughRedGreenBlueAndOff() {
    #expect(blinkStep(0) == BlinkStep(red: 32, green: 0, blue: 0, name: "Red"))
    #expect(blinkStep(1) == BlinkStep(red: 0, green: 32, blue: 0, name: "Green"))
    #expect(blinkStep(2) == BlinkStep(red: 0, green: 0, blue: 32, name: "Blue"))
    #expect(blinkStep(3) == BlinkStep(red: 0, green: 0, blue: 0, name: "Off"))
}

@Test(arguments: [0, 1, 2, 3] as [UInt32])
func repeatsEveryFourSteps(index: UInt32) {
    #expect(blinkStep(index) == blinkStep(index + 4))
}

@Test func usesTheGivenBrightness() {
    #expect(blinkStep(0, brightness: 255).red == 255)
}
