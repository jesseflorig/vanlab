# Fleet 1 MQTT sensor spec
This is the MQTT topic spec for a variety of sensors

## Sensors
Values are

### Thermostat
- `thermostat/`
  - `temperature` \<NUMBER\> degrees in fahrenheit
  - `humidity`<sup>1</sup> \<NUMBER\> percentage of water per unit of air
  - `dewpoint` \<NUMBER\> degree at which dew forms (based on `humidity` & `temperature`
  - `isCooling` \<BOOLEAN\> whether or not the unit is actively cooling
  - `isHeating` \<BOOLEAN\> whether or not the unit is actively heating
  - `isFanOn` \<NOOLEAN\> whther or not the unit fan is on

  <sup>1</sup>: computed values by NODE-RED
