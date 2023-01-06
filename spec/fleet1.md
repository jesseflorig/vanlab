# Fleet 1 MQTT topic spec

This is the spec for Fleet 1's MQTT topics.

## Format
```
SIDE/AREA/SUBAREA/PROPERTY
```
### Side
Side defines whether the child topic is interior or exterior.

### Area
Area defines a functional space that contains one or more sensors. Areas have top level properties that are not necessarily tied to a specific sensor.

### Sensor
Sensor defines a set of properties available for a specific device. A sensor can also represent an object whose state matters for the purposes of automation (e.g. door, light).

### Property
Property defines a name value available for an area or sensor.

## Wildcards
The format spec allows the use of single-level and multi-level wildcards.

### Single Level: +
All sensors with a light property
```
Interior/Bedroom/+/Light
```

### Multi Level: #
