#!/bin/bash
# monitor.sh
# Opens a serial monitor for the connected ESP32 board.
#
# Reads serial output from the board and streams it to stdout.
# Designed to be invoked as the Xcode Scheme's Run Executable,
# routing device output to Xcode's debug console.
#
# Note: Input from Xcode's debug console is not supported,
# as the console is a stdout-only display. Use an external
# serial terminal for interactive input.

# Use ESP-IDF's Python environment (has pyserial pre-installed).
# Environments are named idf<IDF version>_py<Python version>_env, and
# both versions change between ESP-IDF releases, so pick the newest.
IDF_PYTHON=$(find "$HOME/.espressif/python_env" -maxdepth 1 -type d -name "idf*_py*_env" | sort -V | tail -1)/bin/python

if [ ! -x "$IDF_PYTHON" ]; then
    echo "Error: ESP-IDF Python environment not found." >&2
    echo "Please run install.sh first." >&2
    exit 1
fi

# Detect the connected board's port.
DETECT_PORT="$(dirname "$0")/detect_port.sh"
PORT=$(bash "$DETECT_PORT")

if [ $? -ne 0 ]; then
    echo "Error: No ESP32 board found." >&2
    echo "Make sure the device is connected via USB." >&2
    exit 1
fi

echo "================================================="
echo " ESP32 Serial Monitor"
echo " Port: $PORT @ 115200 baud"
echo "================================================="

# Stream serial output to stdout using pyserial.
# stdout flushing ensures real-time output to Xcode console.
"$IDF_PYTHON" -c "
import serial
import sys

port = '$PORT'
baud = 115200

try:
    ser = serial.Serial(port, baud, timeout=0.1)
    while True:
        data = ser.read(1024)
        if data:
            sys.stdout.write(data.decode('utf-8', errors='replace'))
            sys.stdout.flush()
except KeyboardInterrupt:
    ser.close()
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
