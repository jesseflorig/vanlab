start:
	docker compose -f compose.yaml up

# mosquitto container has to be running to add a user
# syntax: make addUser u=test p=password
addUser:
	docker exec mosquitto mosquitto_passwd -b /mosquitto/config/password.txt $u $p

# mosquitto container has to be running to delete a user
# syntax: make deleteUser u=test
deleteUser:
	docker exec mosquitto mosquitto_passwd -D /mosquitto/config/password.txt $u
