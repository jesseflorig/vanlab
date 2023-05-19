# [WIP] Vanlab
A containerized edge IoT environment built for Fleet 1.

## Components

- [x] __Node-RED__ _WYSIWYG logic flow application for setting up automations_
- [x] __Mosquitto__ _MQTT broker for lightweight IoT messaging_
- [x] __InfluxDB__ _Time-series datastore with automatic rollup_
- [x] __Grafana__ _Monitoring and data analytics visualisations for the IoT telemetry_
- [ ] __Vanlab UI__ _IoT front-end for Vanlab_

## Getting Started
Clone the project, navigate into the directory, create the `.env`, and run `make start`:
```
git clone git@github.com:jesseflorig/vanlab.git
cd vanlab
cp .env.example .env
make start
```

### MQTT node in Node-RED
In Node-RED, you can reference the Mosquitto container name, `mosquitto` when configuring your MQTT connection. In the "Security" tab, use `vanlab:test` for username and password.

## Utility Helpers

### Adding Mosquitto user accounts
With the `mosquitto` container running, you can use `make addUser`:
```
make addUser u=yourUserName p=yourPassword
```

### Deleting Mosquitto user accounts
With the `mosquitto` container running, you can use `make deleteUser`:
```
make deleteUser u=yourUserName
```
