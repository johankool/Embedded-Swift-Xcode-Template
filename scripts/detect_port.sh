#!/bin/bash

# detect_port.sh
# Detects the serial port of a connected ESP32 board.
#
# ESP32 boards appear on macOS under /dev/cu.* with names that depend
# on the board's USB interface:
#
# 1. Native USB-CDC (Espressif): /dev/cu.usbmodem*
#    The chip's own USB peripheral acts as the USB device.
# 2. USB-Serial Bridge (WCH CH340): /dev/cu.wchusbserial*
#    Common on third-party boards with a CH340 USB-to-UART chip.
# 3. USB-Serial Bridge (Silicon Labs CP210x): /dev/cu.SLAB_USBtoUART
#    Name used by the legacy Silicon Labs VCP driver.
# 4. USB-Serial Bridge (CP210x, FTDI, etc.): /dev/cu.usbserial*
#    Name used by macOS's built-in driver, e.g. for the CP2102N on
#    official Espressif DevKitC boards.
#
# Exits with code 0 and prints the port path on success.
# Exits with code 1 if no device is found.

# Check each known pattern in priority order.
for pattern in /dev/cu.usbmodem* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/cu.usbserial*; do
    # The glob expands to the literal pattern if no files match,
    # so we need to test that the path actually exists.
    for port in $pattern; do
        if [ -e "$port" ]; then
            echo "$port"
            exit 0
        fi
    done
done

echo "Error: No ESP32 board found." >&2
echo "Make sure the device is connected via USB." >&2
exit 1