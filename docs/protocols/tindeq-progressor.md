# Tindeq Progressor BLE Protocol

Source: official Python client example (tindeq.com).

## Service & Characteristics

- Progressor Service: `7e4e1701-1ea6-40c9-9dcc-13d34ffead57`
- Data Characteristic (notify for samples): `7e4e1702-1ea6-40c9-9dcc-13d34ffead57`
- Control Point Characteristic (write commands): `7e4e1703-1ea6-40c9-9dcc-13d34ffead57`

Always enable notifications on Data before sending commands.

Device name prefix: "Progressor"

Auto power off after ~10 min disconnected.

All multi-byte little-endian.

## Commands (write single byte or more to Control)

```dart
const CMD_TARE_SCALE = 100;
const CMD_START_WEIGHT_MEAS = 101;
const CMD_STOP_WEIGHT_MEAS = 102;
const CMD_START_PEAK_RFD_MEAS = 103;
const CMD_START_PEAK_RFD_MEAS_SERIES = 104;
// ... others for calibration, battery, sleep, version
const CMD_GET_BATTERY_VOLTAGE = 111;
const CMD_ENTER_SLEEP = 110;
```

## Responses / Data (first byte = tag from Data char)

- 0: RES_CMD_RESPONSE
- 1: RES_WEIGHT_MEAS  — main data. Payload: [tag, len, (float32 weight_kg, uint32 usec) * N ]
- 2: RES_RFD_PEAK
- 3: RES_RFD_PEAK_SERIES
- 4: RES_LOW_PWR_WARNING

Example handler logic (from py):

```python
if data[0] == 1:  # WEIGHT
    # pairs every 8 bytes after header
    for ... :
        weight = struct.unpack('<f', x)[0]
        ts_us = struct.unpack('<I', y)[0]
```

In app: convert to N if needed ( * 9.81 ), store with host monotonic or relative ms.

## Tare

Send CMD_TARE_SCALE. Usually do before start. Device zeros current load.

## Measurement flow (typical)

1. Connect, discover by name or service.
2. Start notify on DATA.
3. (Optional) query version / battery.
4. Send TARE.
5. Send START_WEIGHT_MEAS (or RFD variant).
6. Receive ongoing WEIGHT_MEAS notifications (high rate).
7. On stop: send STOP.
8. Optionally sleep.

For series/RFD specific responses may be used.

## Notes for implementation

- flutter_blue_plus: use writeCharacteristic with response where needed.
- Use a single characteristic write for commands.
- Parse multiple samples per packet.
- Timestamp: use device us + offset or just use local elapsed for plotting; store raw too.
- Reconnection: device may need power cycle if timed out.
- Battery: query via CMD_GET_BATTERY_VOLTAGE → response gives mV.
