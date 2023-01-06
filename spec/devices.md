# Fleet 1 MQTT sensor spec
MQTT topic specification for a variety of sensors

## Sensors

### Thermostat
- `thermostat/`
  - `temperature` \<NUMBER\> degrees in fahrenheit
  - `humidity`<sup>1</sup> \<NUMBER\> percentage of water per unit of air
  - `dewpoint` \<NUMBER\> degree at which dew forms (based on `humidity` & `temperature`
  - `isCooling` \<BOOLEAN\> whether or not the unit is actively cooling
  - `isHeating` \<BOOLEAN\> whether or not the unit is actively heating
  - `isFanOn` \<NOOLEAN\> whther or not the unit fan is on

### RGB Light
- `RgbLight/`
  - `color` \<NUMBER[]\> red, green, blue intensity values (0-255)
  - `brightness` <\NUMBER\> percentage of brightness (0-100)
  - `on` <\BOOLEAN\> whether or not the light is on

  <sup>1</sup>: computed values by NODE-RED for analysis
