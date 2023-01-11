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
- `interior/`
  - `office/`
    - `temperature` \<NUMBER\> average room temp
    - `driverDesk`
    - `passengerDesk`
  - `kitchen/`
    - `temperature` \<NUMBER\> average room temp
  - `hall/`
    - `temperature` \<NUMBER\> average room temp
  - `bathroom/`
    - `temperature` \<NUMBER\> average room temp
  - `bedroom/`
    - `temperature` \<NUMBER\> average room temp
  - `garage/`
    - `temperature` \<NUMBER\> average room temp
- `exterior/`
  - `temperature` \<NUMBER\> average exterior temp
  - `front/`
  - `rear/`
  - `driver/`
  - `passenger/`
  - `deck/`
    - `temperature` \<NUMBER\> average deck temp
    - `isSolarOpen`
    - `isSolarLocked`
  - `belly/`
    - `temperature` \<NUMBER\> average belly temp
    - `isGrayDraining`
    - `isFreshDraining`
  - `utility/`
    - `temperature` \<NUMBER\> average room temp
