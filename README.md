# ProxySQL with PHPMyAdmin via Docker Compose

This Docker Compose file sets up a simple ProxySQL and MySQL with Group Replication. Also sets up PHPMyAdmin for management.

Run this file by running `docker compose up -d` in the folder. To clean all folders in `data`, run `build.sh`. Make sure to give it proper execution commands first. When restarting the server from a `down` state or `stopped` state, run `reup.sh` so the Group Replication can be set-up once again.
