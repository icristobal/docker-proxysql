#!/bin/bash

docker-compose up -d

# Connect to slave 1
until docker-compose exec mysql_slave1 sh -c 'export MYSQL_PWD=root; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave1 database connection..."
    sleep 4
done

MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=root; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

docker exec mysql_slave1 sh -c 'export MYSQL_PWD=root; mysql -u root -e "RESET SLAVE"'
docker exec mysql_slave1 sh -c 'export MYSQL_PWD=root; mysql -u root -e "STOP SLAVE"'

# Add master host details and start slave of slave1
start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='slave',MASTER_PASSWORD='slave',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS;"
start_slave_cmd='export MYSQL_PWD=root; mysql -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
docker exec mysql_slave1 sh -c "$start_slave_cmd"

docker exec mysql_slave1 sh -c 'export MYSQL_PWD=root; mysql -u root -e "START SLAVE"'
docker exec mysql_slave1 sh -c 'export MYSQL_PWD=root; mysql -u root -e "SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1; START SLAVE"'

docker exec mysql_slave1 sh -c "export MYSQL_PWD=root; mysql -u root -e 'SHOW SLAVE STATUS \G'"

# Connect to slave 2
until docker-compose exec mysql_slave2 sh -c 'export MYSQL_PWD=root; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave2 database connection..."
    sleep 4
done

MS_STATUS2=`docker exec mysql_master sh -c 'export MYSQL_PWD=root; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG2=`echo $MS_STATUS2 | awk '{print $6}'`
CURRENT_POS2=`echo $MS_STATUS2 | awk '{print $7}'`

docker exec mysql_slave2 sh -c 'export MYSQL_PWD=root; mysql -u root -e "RESET SLAVE"'
docker exec mysql_slave2 sh -c 'export MYSQL_PWD=root; mysql -u root -e "STOP SLAVE"'

# Add master host details and start slave of slave2
start_slave2_stmt="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='slave',MASTER_PASSWORD='slave',MASTER_LOG_FILE='$CURRENT_LOG2',MASTER_LOG_POS=$CURRENT_POS2;"
start_slave2_cmd='export MYSQL_PWD=root; mysql -u root -e "'
start_slave2_cmd+="$start_slave2_stmt"
start_slave2_cmd+='"'
docker exec mysql_slave2 sh -c "$start_slave2_cmd"

docker exec mysql_slave2 sh -c 'export MYSQL_PWD=root; mysql -u root -e "START SLAVE"'
docker exec mysql_slave2 sh -c 'export MYSQL_PWD=root; mysql -u root -e "SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1; START SLAVE"'

docker exec mysql_slave2 sh -c "export MYSQL_PWD=root; mysql -u root -e 'SHOW SLAVE STATUS \G'"

