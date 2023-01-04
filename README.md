# [WIP] Vanlab
A containerized edge IoT environment built for Fleet 1.

## Components

### Node-RED
A WSYWIG logic flow application for setting up automations

### Mosquitto
An MQTT broker for lightweight IoT messaging

### [WIP] InfluxDB
Time-series datastore with automatic rollup

### [WIP] Grafana
Data visualisation UI for the IoT telemetry

## Getting Started
Clone the project, navigate into the directory and run `make start`.
```
git clone git@github.com:jesseflorig/vanlab.git

cd vanlab

make start
```

### MQTT node in Node-RED
In Node-RED, you can reference the Mosquitto container name, `mosquitto` when configuring your MQTT connection. In the "Security" tab, use `vanlab:test` for username and password.

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

## Todo:
- [ ] Export (Pre-load?) example NR flow
- [ ] Integrate InfluxDB
- [ ] Integrate Grafana
