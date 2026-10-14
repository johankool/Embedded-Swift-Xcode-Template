//
//  ESPIDF.h
//  ___PROJECTNAME___
//
//  Created by ___FULLUSERNAME___ on ___DATE___.
//

// The ESPIDF module: ESP-IDF's C APIs for Swift code, which uses them with
// `import ESPIDF`. Add any C headers you need to access from Swift here.

#ifndef ESPIDF_h
#define ESPIDF_h

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "sdkconfig.h"
#include "led_strip.h"

// ── FreeRTOS Macro Wrappers ──────────────────────────────────────
// C macros like pdMS_TO_TICKS() cannot be called directly from Swift.
// These inline functions wrap them for Swift compatibility.

/// Convert milliseconds to FreeRTOS ticks.
/// Assumes default tick rate of 100 Hz (configTICK_RATE_HZ=100),
/// so 1000 ms = 100 ticks.
static inline TickType_t pd_ms_to_ticks(uint32_t ms) {
    return pdMS_TO_TICKS(ms);
}

// ── Onboard RGB LED ──────────────────────────────────────────────
// Espressif's DevKit boards have a WS2812 RGB LED. Its pin depends on the
// chip (as in ESP-IDF's blink example); change it here for other boards.

#if CONFIG_IDF_TARGET_ESP32C5
#define BOARD_RGB_LED_GPIO 27
#elif CONFIG_IDF_TARGET_ESP32P4
#define BOARD_RGB_LED_GPIO 44
#else
#define BOARD_RGB_LED_GPIO 8
#endif

/// Creates a driver for the board's RGB LED. Uses the RMT peripheral on
/// chips that have one, and SPI on chips that don't (ESP32-C2, ESP32-C61).
static inline esp_err_t board_rgb_led_new(led_strip_handle_t *strip) {
    led_strip_config_t strip_config = {
        .strip_gpio_num = BOARD_RGB_LED_GPIO,
        .max_leds = 1,                        // Only one LED on board
    };
#if CONFIG_SOC_RMT_SUPPORTED
    led_strip_rmt_config_t rmt_config = {
        .resolution_hz = 10 * 1000 * 1000,    // 10 MHz tick resolution
        .mem_block_symbols = 64,
    };
    return led_strip_new_rmt_device(&strip_config, &rmt_config, strip);
#else
    led_strip_spi_config_t spi_config = {
        .clk_src = SPI_CLK_SRC_DEFAULT,
        .spi_bus = SPI2_HOST,
    };
    return led_strip_new_spi_device(&strip_config, &spi_config, strip);
#endif
}

#endif /* ESPIDF_h */
