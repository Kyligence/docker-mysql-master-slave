#!/bin/bash

docker-compose down
rm -rf ./mysql_master_1/data/*
rm -rf ./mysql_master_2/data/*
docker-compose build
docker-compose up -d

until docker exec mysql_master_1 sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

priv_stmt='GRANT REPLICATION SLAVE ON *.* TO "replicauser"@"%" IDENTIFIED BY "111"; FLUSH PRIVILEGES;'
docker exec mysql_master_1 sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

until docker-compose exec mysql_master_2 sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done
docker exec mysql_master_2 sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

docker-ip() {
    docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@"
}

stmt() {
    MS_STATUS=`docker exec $1 sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
    CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
    CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

    echo "STOP SLAVE;CHANGE MASTER TO MASTER_HOST='$(docker-ip $1)',MASTER_USER='replicauser',MASTER_PASSWORD='111',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;" 
}
start_master_2_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_master_2_cmd+="$(stmt mysql_master_1)"
start_master_2_cmd+='"'
start_master_1_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_master_1_cmd+="$(stmt mysql_master_2)"
start_master_1_cmd+='"'
docker exec mysql_master_2 sh -c "$start_master_2_cmd"
docker exec mysql_master_2 sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"

docker exec mysql_master_1 sh -c "$start_master_1_cmd"
docker exec mysql_master_1 sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"


create_ha_user='export MYSQL_PWD=111; mysql -u root -e "'
create_ha_user+="CREATE USER 'haproxy_check'@'%';FLUSH PRIVILEGES;"
create_ha_user+='"'
docker exec mysql_master_1 sh -c "$create_ha_user"

