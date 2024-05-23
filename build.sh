#!/bin/bash

# Docker reinit
docker-compose down -v
sudo rm -rf ./data/*
docker-compose build
docker-compose up -d

# Connect to Master
until docker exec mysql_master sh -c 'export MYSQL_PWD=root; mysql -u root -e ";"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

echo "Setting up MySQL Source..."
sleep 2

# Create slave user (used by both slaves)
slaveuser='CREATE USER "slave"@"%" IDENTIFIED WITH mysql_native_password BY "slave"; GRANT REPLICATION SLAVE ON *.* TO "slave"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=root; mysql -u root -e '$slaveuser'"

echo "Master Status: "
docker exec mysql_master sh -c "export MYSQL_PWD=root; mysql -u root -e 'SHOW MASTER STATUS \G'"

echo "Done!"
sleep 1

# Connect to slave 1
until docker-compose exec mysql_slave1 sh -c 'export MYSQL_PWD=root; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave1 database connection..."
    sleep 4
done

echo "Setting up MySQL Replica #1..."
sleep 2

readonly_stmt='FLUSH TABLES WITH READ LOCK; SET GLOBAL read_only = ON;'
docker-compose exec mysql_slave1 sh -c "export MYSQL_PWD=root; mysql -u root -e \"$readonly_stmt\""

MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=root; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

# Add master host details and start slave of slave1
start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='slave',MASTER_PASSWORD='slave',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd='export MYSQL_PWD=root; mysql -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
docker exec mysql_slave1 sh -c "$start_slave_cmd"

echo "Done!"
sleep 1

echo "Replica #1 Status: "
docker exec mysql_slave1 sh -c "export MYSQL_PWD=root; mysql -u root -e 'SHOW SLAVE STATUS \G'"

# Connect to slave 2
until docker-compose exec mysql_slave2 sh -c 'export MYSQL_PWD=root; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave2 database connection..."
    sleep 4
done

echo "Setting up MySQL Replica #2..."
sleep 2

docker-compose exec mysql_slave1 sh -c "export MYSQL_PWD=root; mysql -u root -e \"$readonly_stmt\""

MS_STATUS2=`docker exec mysql_master sh -c 'export MYSQL_PWD=root; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG2=`echo $MS_STATUS2 | awk '{print $6}'`
CURRENT_POS2=`echo $MS_STATUS2 | awk '{print $7}'`

# Add master host details and start slave of slave2
start_slave2_stmt="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='slave',MASTER_PASSWORD='slave',MASTER_LOG_FILE='$CURRENT_LOG2',MASTER_LOG_POS=$CURRENT_POS2; START SLAVE;"
start_slave2_cmd='export MYSQL_PWD=root; mysql -u root -e "'
start_slave2_cmd+="$start_slave2_stmt"
start_slave2_cmd+='"'
docker exec mysql_slave2 sh -c "$start_slave2_cmd"

echo "Replica #2 Status: "
docker exec mysql_slave2 sh -c "export MYSQL_PWD=root; mysql -u root -e 'SHOW SLAVE STATUS \G'"

# Connect to proxysql
until docker-compose exec proxysql sh -c 'export MYSQL_PWD=admin; mysql -u admin -h 127.0.0.1 -P6032 -e ";"'
do
    echo "Waiting for proxysql connection..."
    sleep 4
done

echo "Setting up ProxySQL..."
sleep 2

proxyuser='CREATE USER "proxyuser"@"%" IDENTIFIED BY "proxypassword"; GRANT ALL PRIVILEGES ON *.* TO "proxyuser"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=root; mysql -u root -e '$proxyuser'"
monitoruser='CREATE USER "monitor"@"%" IDENTIFIED BY "monitor"; GRANT USAGE, REPLICATION CLIENT ON *.* TO "monitor"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=root; mysql -u root -e '$monitoruser'"

proxysql_setup='
INSERT INTO mysql_servers(hostgroup_id,hostname,port,max_replication_lag) VALUES (0,"192.168.0.51", 3306, 20); 
INSERT INTO mysql_servers(hostgroup_id,hostname,port,max_replication_lag) VALUES (1,"192.168.0.52", 3306, 20); 
INSERT INTO mysql_servers(hostgroup_id,hostname,port,max_replication_lag) VALUES (1,"192.168.0.53", 3306, 20); 

UPDATE global_variables SET variable_value="monitor" WHERE variable_name="mysql-monitor_username"; 
UPDATE global_variables SET variable_value="monitor" WHERE variable_name="mysql-monitor_password"; 
UPDATE global_variables SET variable_value="2000" WHERE variable_name IN ("mysql-monitor_connect_interval","mysql-monitor_ping_interval","mysql-monitor_read_only_interval"); 

INSERT INTO mysql_users(username, password, active, default_hostgroup, max_connections) VALUES ("proxyuser", "proxypassword", 1, 0, 200); 
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, "^SELECT .* FOR UPDATE", 0, NULL); 
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, "^SELECT .*", 1, NULL); 
INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup) VALUES (0, 1); 

LOAD MYSQL USERS TO RUNTIME; 
SAVE MYSQL USERS TO DISK; 
LOAD MYSQL QUERY RULES TO RUNTIME; 
SAVE MYSQL QUERY RULES TO DISK; 
LOAD MYSQL VARIABLES TO RUNTIME; 
SAVE MYSQL VARIABLES TO DISK; 
LOAD MYSQL SERVERS TO RUNTIME; 
SAVE MYSQL SERVERS TO DISK;'

# Execute SQL statements
docker-compose exec proxysql sh -c "
    export MYSQL_PWD=admin;
    mysql -u admin -h 127.0.0.1 -P6032 -e '$proxysql_setup'"

echo "Done!"
sleep 1
echo "ProxySQL Active Servers: "
docker-compose exec proxysql sh -c "
    export MYSQL_PWD=admin;
    mysql -u admin -h 127.0.0.1 -P6032 -e 'SELECT * from runtime_mysql_servers;'"