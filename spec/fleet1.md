# [WIP] Fleet 1 MQTT topic spec
MQTT topic specification for Fleet 1 layout.

### Format
The format is designed to best make use of single-level (`+`) and multi-level (`#`) wildcards:
```
ENVIRONMENT/AREA/PROPERTY
               └/DEVICE/PROPERTY
```
In addition to `DEVICE`s, `AREA`s can have their own top-level computed `PROPERTY` values.

### Topics
- __interior/__
  - __cab/__
    - __cabinet/__
  - __office/__
    - __temperature__ `NUMBER` average room temp
    - __driverDesk__
    - __passengerDesk__
  - __kitchen/__
    - __temperature__ `NUMBER` average room temp
    - __cabinet/__
    - __counter/__
    - __drawer/__
  - __hall/__
    - __temperature__ `NUMBER` average room temp
    - __cabinet/__
    - __counter/__
    - __drawer/__
  - __bathroom/__
    - __temperature__ `NUMBER` average room temp
  - __bedroom/__
    - __temperature__ `NUMBER` average room temp
  - __garage/__
    - __temperature__ `NUMBER` average room temp
- __exterior/__
  - __temperature__ `NUMBER` average exterior temp
  - __front/__
  - __rear/__
  - __driver/__
  - __passenger/__
  - __deck/__
    - __temperature__ `NUMBER` average deck temp
    - __isSolarOpen__
    - __isSolarLocked__
  - __belly/__
    - __temperature__ `NUMBER` average belly temp
    - __isGrayDraining__
    - __isFreshDraining__
  - __utility/__
    - __temperature__ `NUMBER` average room temp
