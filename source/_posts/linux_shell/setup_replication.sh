#!/bin/bash

# 简化版主从配置脚本
password="password"

echo "=== 1. 配置 Master (2221) ==="
ssh -p 2221 demo@localhost << REMOTE
    echo '$password' | sudo -S sh -c "echo 'log-bin=mysql-bin' >> /etc/mysql/my.cnf"
    echo '$password' | sudo -S sh -c "echo 'server-id=1' >> /etc/mysql/my.cnf"
    echo '$password' | sudo -S pkill mariadb
    echo '$password' | sudo -S /usr/bin/mariadbd-safe --datadir='/var/lib/mysql' &>/dev/null &
    sleep 3
    mysql -e "CREATE USER 'repl'@'%' IDENTIFIED BY 'repl_password'; GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';"
REMOTE

# 获取 Master 关键信息 (在宿主机执行)
master_ip=$(ssh -p 2221 demo@localhost "hostname -i")
master_log=$(ssh -p 2221 demo@localhost "mysql -e 'show master status'" | awk 'NR==2{print $1}')
master_pos=$(ssh -p 2221 demo@localhost "mysql -e 'show master status'" | awk 'NR==2{print $2}')

echo "Master $master_ip, Log: $master_log, Pos: $master_pos"

echo "=== 2. 配置 Slave (2222) ==="
ssh -p 2222 demo@localhost << REMOTE
    echo '$password' | sudo -S sh -c "echo 'server-id=2' >> /etc/mysql/my.cnf"
    echo '$password' | sudo -S pkill mariadb
    echo '$password' | sudo -S /usr/bin/mariadbd-safe --datadir='/var/lib/mysql' &>/dev/null &
    sleep 3
    mysql -e "CHANGE MASTER TO MASTER_HOST='$master_ip', MASTER_USER='repl', MASTER_PASSWORD='repl_password', MASTER_LOG_FILE='$master_log', MASTER_LOG_POS=$master_pos; START SLAVE;"
REMOTE

echo "=== 3. 验证状态 ==="
ssh -p 2222 demo@localhost "mysql -e 'show slave status\G'" | grep Running
