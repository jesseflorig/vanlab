# [WIP] Fleet 1 MQTT sensor spec
MQTT topic specification for a variety of sensors

## Sensor Table of Contents
1. [Access](## Access)
  1. Door
  1. Lock
  1. Motion
1. HVAC
  1. Fan
  1. Thermostat
  1. Vent
  1. Water Heater
1. Lighting
  1. Light
  1. RGB Light
1. Utility
  1. Tank
  1. Valve

## Access
Allowing or detecting access

### Door
- `door/`
  - `open` \<BOOLEAN\> whether the door is open

## HVAC
Heating, venting, and air conditioning

### Thermostat
- `thermostat/`
  - `targetTemp` \<NUMBER\> target temperature degrees in fahrenheit
  - `humidity` \<NUMBER\> percentage of water per unit of air
  - `dewpoint`<sup>1</sup> \<NUMBER\> degree at which dew forms (based on `humidity` & `temperature`
  - `isCooling` \<BOOLEAN\> whether the unit is actively cooling
  - `isHeating` \<BOOLEAN\> whether the unit is actively heating
  - `isFanOn` \<NOOLEAN\> whther the unit fan is on

## Lighting
Let there be light

### IR Light
- `irLight/`
  - `on` <\BOOLEAN\> whether the light is on

### Light
- `light/`
  - `on` <\BOOLEAN\> whether the light is on

### RGB Light
- `rgbLight/`
  - `on` <\BOOLEAN\> whether the light is on
  - `color` \<NUMBER[]\> red, green, blue intensity values (0-255)
  - `brightness` <\NUMBER\> percentage of brightness (0-100)

## Utility
Miscellaneous sensors

#### Notes
1. Computed values by NODE-RED for analysis
