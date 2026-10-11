//
//  main.swift
//  ___PROJECTNAME___
//
//  Created by ___FULLUSERNAME___ on ___DATE___.
//

// Embedded Swift entry point.
// This example blinks the onboard NeoPixel (WS2812) RGB LED of
// Espressif's DevKit boards.

@_cdecl("app_main")
public func app_main() {
    print("Hello from Embedded Swift on ESP32!")
    print("Starting NeoPixel blink demo...")
    
    // ── LED Strip Configuration ──────────────────────────────
    // board_rgb_led_new() in BridgingHeader.h sets up the led_strip
    // driver for the board's LED: it picks the LED's pin for the
    // chip, and the peripheral that generates the precise timing
    // pulses WS2812 LEDs need (RMT, or SPI on chips without RMT).
    
    var ledStrip: led_strip_handle_t?
    let result = board_rgb_led_new(&ledStrip)
    
    if result != ESP_OK {
        print("Failed to initialize LED strip!")
        return
    }
    
    print("NeoPixel initialized on GPIO \(BOARD_RGB_LED_GPIO).")
    
    // ── Animation Loop ───────────────────────────────────────
    // Cycle through Red, Green, Blue, and Off — one color per second.
    
    var colorIndex: UInt32 = 0
    
    while true {
        // Set RGB based on current index.
        // Brightness kept low (32/255) to avoid blinding intensity.
        var r: UInt32 = 0
        var g: UInt32 = 0
        var b: UInt32 = 0
        var name: StaticString = "Off"
        
        switch colorIndex % 4 {
        case 0:
            r = 32; name = "Red"
        case 1:
            g = 32; name = "Green"
        case 2:
            b = 32; name = "Blue"
        default:
            name = "Off"
        }
        
        // Set the first (and only) pixel to the current color.
        led_strip_set_pixel(ledStrip, 0, r, g, b)
        
        // Push the pixel data to the LED hardware.
        led_strip_refresh(ledStrip)
        
        print("LED: \(name)")
        
        // Wait 1 second using FreeRTOS task delay.
        vTaskDelay(pd_ms_to_ticks(1000))

        
        colorIndex += 1
    }
}
