# [WIP] MQTT Messages spec
MQTT Messages specification

### Format
The intention is to simplify the structure of the MQTT traffic as much as possible to reduce the amount of data travelling across the wire to and from the sensors.

Previous iterations have used JSON as the payload with metadata such as reason for trigger. However, its possible to keep this metadata out of the MQTT traffic, while shipping it to a time-series data store, such as InflixDB, for further analysis and on-demand monitoring.

- __message__
  - __topic__ `STRING` sub/pub path
  - __payload__ `STRING` | `NUMBER` value for the topic property
