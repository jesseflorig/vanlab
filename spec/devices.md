# [WIP] Fleet 1 MQTT sensor spec
MQTT topic specification for a variety of sensors

## Sensor Table of Contents
1. [Access](#access)
    1. [Door](#door)
    1. Lock
    1. Motion
1. [HVAC](#hvac)
    1. Fan
    1. [Thermostat](#thermostat)
    1. Vent
    1. Water Heater
1. [Lighting](#lighting)
    1. [IR Light](#ir-light)
    1. [Light](#light)
    1. [RGB Light](#rgb-light)
1. [Utility](#utility)
    1. [Tank](#tank)
    1. [Valve](#valve)

## Access
Allowing or detecting access

### Door
- __door/__
  - __open__ `BOOLEAN` whether the door is open

## HVAC
Heating, venting, and air conditioning

### Thermostat
- __thermostat/__
  - __targetTemp__ `NUMBER` target temperature degrees in fahrenheit
  - __humidity__ `NUMBER` percentage of water per unit of air
  - __dewpoint__<sup>1</sup> `NUMBER` degree at which dew forms (based on __humidity__ & __temperature__)
  - __isCooling__ `BOOLEAN` whether the unit is actively cooling
  - __isHeating__ `BOOLEAN` whether the unit is actively heating
  - __isFanOn__ `BOOLEAN` whther the unit fan is on

## Lighting
Let there be light

### IR Light
- __irLight/__
  - __on__ `BOOLEAN` whether the light is on

### Light
- __light/__
  - __on__ `BOOLEAN` whether the light is on

### RGB Light
- __rgbLight/__
  - __on__ `BOOLEAN` whether the light is on
  - __color__ `NUMBER[]` red, green, blue intensity values (0-255)
  - __brightness__ `NUMBER` percentage of brightness (0-100)

## Utility
Miscellaneous sensors

### Tank
- __tank__
  - __fill__ `NUMBER` percentage of tank filled

### Valve
- __valve/__
  - __open__ `BOOLEAN` whether the valve is open

#### Notes
1. Computed values by NODE-RED for analysis
