# [WIP] Fleet 1 MQTT sensor spec
MQTT topic specification for a variety of sensors

## Table of Contents
1. [Access](#access)
    1. [Door](#door)
    1. [Lock](#lock)
    1. [Motion Sensor](#motion-sensor)
1. [HVAC](#hvac)
    1. [Fan](#fan)
    1. [Thermostat](#thermostat)
    1. [Vent](#vent)
    1. [Water Heater](#water-heater)
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

### Lock
- __lock/__
  - __locked__ `BOOLEAN` whether the lock is engaged

### Motion Sensor
- __motionSensor/__
  - __movement__ `BOOLEAN` whether movement is detected

[Back to top](#table-of-contents)

## HVAC
Heating, venting, and air conditioning

### Fan
- __fan/__
  - __on__ `BOOLEAN` whether the fan is on

### Thermostat
- __thermostat/__
  - __targetTemp__ `NUMBER` target temperature degrees in fahrenheit
  - __temperature__ `NUMBER` current temperature degrees in fahrenheit
  - __humidity__ `NUMBER` percentage of water per unit of air
  - __dewpoint__<sup>1</sup> `NUMBER` degree at which dew forms (based on __humidity__ & __temperature__)
  - __isCooling__ `BOOLEAN` whether the unit is actively cooling
  - __isHeating__ `BOOLEAN` whether the unit is actively heating
  - __isFanOn__ `BOOLEAN` whther the unit fan is on

### Vent
- __vent/__
  - __open__ `BOOLEAN` whether the vent is open

[Back to top](#table-of-contents)

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

[Back to top](#table-of-contents)

## Utility
Miscellaneous sensors

### Tank
- __tank__
  - __fill__ `NUMBER` percentage of tank filled

### Valve
- __valve/__
  - __open__ `BOOLEAN` whether the valve is open

[Back to top](#table-of-contents)

#### Notes
1. Computed values by NODE-RED for analysis
