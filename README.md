# RowEdge - Outdoor Rowing App for Garmin Edge

<p align="center">
  <img src="images/RoundBage.png" width="200" alt="RowEdge Logo"/>
</p>

An open-source Connect IQ app that turns Garmin Edge cycling computers into
outdoor rowing performance computers.

## Why?

Outdoor rowing has very few sport performance computers. The dominant product
(NK SpeedCoach GPS, $400+) is expensive and limited. Meanwhile, many athletes
already own a Garmin Edge for cycling. RowEdge repurposes it for rowing with
features specific to the sport.

## Features

- **Split time /500m** from GPS distance (10s sliding window, proper v=dx/dt)
- **Stroke rate (SPM)** from accelerometer -- event-based interval averaging over last 6 strokes
- **Heart rate** from paired ANT+ HR sensor
- **Activity recording** as FIT SPORT_ROWING with custom fields
- **Wahoo-style zoom** -- UP/DOWN buttons to show fewer/more fields with auto-scaling fonts
- **Configurable data fields** -- reorder, add, remove fields via on-device menu
- **Auto gravity calibration** -- 2-second static sampling at activity start
- **Auto-pause/resume** -- GPS speed based with holdoff/cooldown hysteresis
- **Pause/resume** with lap marking
- **Pause display** -- distance, time, avg split, clock while paused
- **Activity summary** -- shown for 10s after save (distance, time, strokes, split, HR)
- **Demo mode** -- simulated data for testing without GPS/water
- **Feature toggles** -- enable/disable auto-pause, demo mode, accel logging via menu
- **Accelerometer logging** -- optional raw accel data in FIT for offline analysis
- **FIT data extraction** -- Python tool with gnuplot visualization (tools/fit_extract.py)

## Supported Devices

- Garmin Edge 540 / 540 Solar (primary target, 246x322)
- Garmin Edge 840 (same resolution)
- Other Edge devices with CIQ 6.0+ (untested)

## Available Data Fields

| Field             | Source                      |
|-------------------|-----------------------------|
| Split /500m       | GPS                         |
| Stroke Rate (SPM) | Accelerometer               |
| Heart Rate        | ANT+ sensor                 |
| Distance          | GPS                         |
| Elapsed Time      | Timer                       |
| Time of Day       | System clock                |
| Meters/Stroke     | GPS + accel                 |
| Stroke Count      | Accelerometer               |
| Speed             | GPS                         |
| Avg Split         | Calculated                  |
| Avg/Max Accel     | Accelerometer (calibration) |

## Zoom Levels

Wahoo-style zoom matching real ELEMNT behavior:

| Zoom | Fields | Layout                |
|------|--------|-----------------------|
| z1   | 1      | Full screen           |
| z2   | 2      | Hero + 1 row          |
| z3   | 3      | Hero 40% + 2 rows 30% |
| z4   | 5      | Hero + 2x2 grid       |
| z5   | 7      | Hero + 2x3 grid       |
| z6   | 9      | Hero + 2x4 grid       |
| z7   | 11     | Hero + 2x5 grid       |

## Button Mapping

| Button | Idle              | Recording | Paused       |
|--------|-------------------|-----------|--------------|
| ENTER  | Start (calibrate) | Pause     | Resume       |
| BACK   | Exit app          | Lap       | Save/Discard |
| UP     | -                 | Zoom in   | Zoom in      |
| DOWN   | -                 | Zoom out  | Zoom out     |
| MENU   | Settings          | Settings  | Settings     |

## Build

Requires Connect IQ SDK 9.1.0+ and Python 3 + Pillow.

```bash
make build           # compile for Edge 540
make fonts           # regenerate bitmap fonts from TTF
make run_simulator   # build + launch simulator + load app
make deploy          # copy to USB-connected Edge device
make clean           # remove build artifacts
```

## Install on Device

```bash
# Connect Edge 540 via USB, then:
make deploy
# Eject device. App appears in Connect IQ apps list.
```

## Configuration

Press MENU to access settings:
- **Data Fields**: reorder, add, remove fields (priority order)
- **Threshold**: stroke detection sensitivity (milliG, default 200)
- **Zoom Level**: number of visible fields
- **Features**: toggle auto-pause, demo mode, accel logging

## TODO

- [ ] Force curve graph -- real-time stroke force profile from accelerometer
- [ ] Varia radar obstacle detection (mount on boat nose for forward warning)
- [ ] Phone settings via settings.xml (requires Connect IQ Store publish)
- [ ] Roll-axis calibration for signed forward acceleration
- [ ] Edge 1040/1050 layout optimization
- [ ] Interval workouts
- [ ] Smart oar sensors (BLE IMU)

## License

GPLv3. See LICENSE file.
