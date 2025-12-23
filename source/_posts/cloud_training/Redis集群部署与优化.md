---
title: Redis 集群部署与优化
date: 
tags:
---

## 实验简介与理论基础

### 实验背景

在生产环境中，Redis 作为高性能的内存数据库，常用于缓存、会话管理等场景。但单节点 Redis 存在单点故障风险：一旦主节点宕机，服务将完全不可用。
**Redis 哨兵模式（Sentinel）** 是 Redis 官方提供的高可用解决方案。它能够自动监控主从节点健康状态，在主节点故障时自动完成主从切换，无需人工干预，保证服务持续可用。

### 实验目标

本实验将在三台 CentOS 7.9 服务器上部署 Redis 哨兵集群，实现：

1. 部署一主二从 Redis 主从复制架构。
2. 配置三节点哨兵模式实现自动故障转移。
3. 验证主节点宕机后的自动切换机制。

### 节点规划

| IP地址 | 主机名 | 角色 | 备注 |
| :--- | :--- | :--- | :--- |
| **192.168.200.21** | **redis1** | Redis 主节点 + 哨兵 | 初始主节点 |
| **192.168.200.22** | **redis2** | Redis 从节点 + 哨兵 | 从节点1 |
| **192.168.200.23** | **redis3** | Redis 从节点 + 哨兵 | 从节点2 |

> **⚠️ 注意**：本实验需要三台服务器，规格建议为 1vCPU/2GB内存/20GB硬盘。

---

## 理论基础：Redis 哨兵模式

### 哨兵模式概述

在传统的 Redis 主从复制模式中，一旦主节点出现故障无法提供服务，需要人工介入手动将从节点调整为主节点，同时应用端还需要修改新的主节点地址。这种故障转移方式对于很多生产场景是无法容忍的。

**Redis Sentinel（哨兵）** 正是为了解决这个问题而生。它是一个分布式架构，本身也是一个独立的 Redis 进程，但它不存储业务数据，只负责监控和管理。

> **💡 理论加油站**：
>
> Redis Sentinel 架构包含：
>
> * **Sentinel 节点**：监控进程，通常部署 3/5/7 个节点（奇数）
> * **Redis 数据节点**：主节点 + 多个从节点
>
> 每个 Sentinel 节点会对所有数据节点和其他 Sentinel 节点进行监控。当发现主节点异常时，会与其他 Sentinel 协商，当**大多数** Sentinel 都认为主节点不可达时，会发起选举，自动完成故障转移，并通知应用方。整个过程完全自动化，无需人工干预。

### 哨兵模式主要功能

Sentinel 主要提供以下四大核心功能：

1. **监控（Monitoring）**：定期检测 Redis 数据节点和其他 Sentinel 节点是否可达。
2. **通知（Notification）**：将故障转移的结果通知给应用方。
3. **主节点故障转移（Automatic Failover）**：当主节点不可用时，自动将某个从节点晋升为新主节点，并维护后续的主从关系。
4. **配置提供者（Configuration Provider）**：客户端在初始化时连接 Sentinel 节点集合，从中获取当前主节点信息。

**高可用保障**：多个 Sentinel 节点共同判断故障，可以有效防止误判。即使个别 Sentinel 节点不可用，整个 Sentinel 集群依然能正常工作。

### 哨兵模式工作流程

Redis Sentinel 是 Redis 的高可用性解决方案：

* 由一个或多个 Sentinel 实例组成的 Sentinel 系统可以监视任意多个主服务器及其所有从服务器。
* 当被监视的主服务器进入下线状态时，Sentinel 会自动将该主服务器的某个从服务器升级为新的主服务器。
* 新的主服务器会代替已下线的主服务器继续处理命令请求。
* 其余从节点会自动指向新的主节点进行数据同步。
* 当原主节点恢复后，会自动成为新主节点的从节点。

**为什么需要 3 个或更多哨兵？**

哨兵通过**选举算法**保证高可用，遵循"过半原则"：

* 至少需要 **3 个哨兵**（推荐 3/5/7 个奇数节点）
* 只有当**超过半数**的哨兵认为主节点下线，才能选举出 Leader 执行故障转移
* 这种机制避免了"脑裂"问题，确保集群决策的一致性

---

## 部署一主二从 Redis 集群

使用 CentOS 7.9 镜像创建三台主机，主机配置 1VCPU/2GB 内存/20GB 硬盘。

**⚠️ 注意：** 本章节需要在三台服务器上分别执行对应命令。

### 基础环境准备（所有节点）

**1. 修改主机名**

{% nocopy %}

```bash
# redis1 节点
[root@localhost ~]# hostnamectl set-hostname redis1
[root@localhost ~]# bash
[root@redis1 ~]#
# redis2 节点
[root@localhost ~]# hostnamectl set-hostname redis2
[root@localhost ~]# bash
[root@redis2 ~]#
# redis3 节点
[root@localhost ~]# hostnamectl set-hostname redis3
[root@localhost ~]# bash
[root@redis3 ~]#
```

{% endnocopy %}

> **💡 解释**：`bash` 命令用于重新加载 Shell 环境，使新主机名立即在命令提示符中生效。修改主机名后需要重新连接 SSH 会话。

**2. 配置本地 YUM 源**

假设已将 `redis-3.2.12.tar.gz` 上传到三台服务器的 `/root` 目录。

{% nocopy %}

```bash
# 解压 Redis YUM 源到 /opt 目录
[root@redis1 ~]# tar -xf redis-3.2.12.tar.gz -C /opt/
# 备份原有 YUM 源配置
[root@redis1 ~]# mv /etc/yum.repos.d/* /media/
# 创建本地 Redis YUM 源配置文件
[root@redis1 ~]# cat << EOF > /etc/yum.repos.d/redis.repo
[redis]
name=redis
baseurl=file:///opt/redis
gpgcheck=0
enabled=1
EOF
[root@redis1 ~]# yum clean all && yum repolist
# 安装 Redis 服务并启动（三台虚拟机操作一致，以 redis1 主机为例）
[root@redis1 ~]# yum install -y redis
[root@redis1 ~]# systemctl start redis
[root@redis1 ~]# systemctl enable redis
```

{% endnocopy %}

### Redis 主从配置

#### redis1 节点配置

```ini
# /etc/redis.conf
# 第一处修改 原文 bind 127.0.0.1
# bind 127.0.0.1                     # 加上井号注释掉该行
# 第二处修改 原文 protected-mode yes
protected-mode no                    # 将 yes 修改为 no，外部网络可以访问
# 第三处修改 原文 daemonize no
daemonize yes                        # 将 no 修改为 yes，开启守护进程
# 第四处修改 原文 # requirepass foobared
requirepass "123456"                 # 设置访问密码
# 第五处修改 原文 # masterauth <master-password>
masterauth "123456"                  # 设定主库密码与当前库密码同步
# 第六处修改 原文 appendonly no
appendonly yes                       # 打开 AOF 持久化支持
```

{% nocopy %}

```bash
[root@redis1 ~]# systemctl restart redis
```

{% endnocopy %}

#### redis2 节点配置

```ini
# /etc/redis.conf
# 第一处修改
# bind 127.0.0.1                     # 加上井号注释掉该行
# 第二处修改 原文 protected-mode yes
protected-mode no                    # 将 yes 修改为 no，外部网络可以访问
# 第三处修改 原文 daemonize no
daemonize yes                        # 将 no 修改为 yes，开启守护进程
# 第四处修改 原文 # requirepass foobared
requirepass "123456"                 # 设置访问密码
# 第五处修改 原文 # slaveof <masterip> <masterport>
slaveof 192.168.200.21 6379          # 添加主节点 IP 与端口
# 第六处修改 原文 # masterauth <master-password>
masterauth "123456"                  # 添加主节点密码
# 第七处修改 原文 # appendonly no
appendonly yes                       # 打开 AOF 持久化支持
```

{% nocopy %}

```bash
[root@redis2 ~]# systemctl restart redis
```

{% endnocopy %}

#### redis3 节点配置

{% nocopy %}

```bash
[root@redis3 ~]# scp root@192.168.200.22:/etc/redis.conf /etc/redis.conf
# 接着输入yes和密码000000，这一步将上面在redis2上配置好的redis.conf直接推送到当前的redis3
# 然后重启redis服务
[root@redis3 ~]# systemctl restart redis
```

{% endnocopy %}

### 集群信息查询

{% nocopy %}

```bash
# redis1 主节点
[root@redis1 ~]# redis-cli -h 192.168.200.21 -p 6379 -a 123456 info replication
# Replication
role:master
connected_slaves:2
slave0:ip=192.168.200.22,port=6379,state=online,offset=9383,lag=0
slave1:ip=192.168.200.23,port=6379,state=online,offset=9238,lag=1
master_repl_offset:9383
repl_backlog_active:1
repl_backlog_size:1048576
repl_backlog_first_byte_offset:2
repl_backlog_histlen:9382
# redis2 从节点
[root@redis2 ~]# redis-cli -h 192.168.200.22 -p 6379 -a 123456 info replication
# Replication
role:slave
master_host:192.168.200.21
master_port:6379
master_link_status:up
master_last_io_seconds_ago:1
master_sync_in_progress:0
slave_repl_offset:2648
slave_priority:100
slave_read_only:1
connected_slaves:0
master_repl_offset:0
repl_backlog_active:0
repl_backlog_size:1048576
repl_backlog_first_byte_offset:0
repl_backlog_histlen:0
# redis3 从节点
[root@redis3 ~]# redis-cli -h 192.168.200.23 -p 6379 -a 123456 info replication
# Replication
role:slave
master_host:192.168.200.21
master_port:6379
master_link_status:up
master_last_io_seconds_ago:0
master_sync_in_progress:0
slave_repl_offset:8658
slave_priority:100
slave_read_only:1
connected_slaves:0
master_repl_offset:0
repl_backlog_active:0
repl_backlog_size:1048576
repl_backlog_first_byte_offset:0
repl_backlog_histlen:0
```

{% endnocopy %}

---

## Redis 哨兵模式配置

### redis1 节点哨兵配置

{% nocopy %}

```ini
# /etc/redis-sentinel.conf
# 第一处修改 原文 # protected-mode no
protected-mode no                    # 将井号删除，允许外部网络访问
# 第二处修改 原文 sentinel monitor mymaster 127.0.0.1 6379 2
sentinel monitor mymaster 192.168.200.21 6379 2  # 监控主节点，quorum 为 2
# 第三处修改 原文 sentinel down-after-milliseconds mymaster 30000
sentinel down-after-milliseconds mymaster 5000   # 主节点无响应超时时间为 5000ms
# 第四处修改 原文 sentinel failover-timeout mymaster 180000
sentinel failover-timeout mymaster 15000         # 故障转移超时时间为 15000ms
# 第五处修改 原文 sentinel parallel-syncs mymaster 1
sentinel parallel-syncs mymaster 2               # 故障转移后并行同步从节点数为 2
# 第六处修改 原文 # sentinel auth-pass mymaster MySUPER--secret-0123passw0rd
sentinel auth-pass mymaster 123456               # 连接主节点的认证密码
```

{% endnocopy %}

### redis2、redis3 节点哨兵配置

内容与 redis1 主节点的 `/etc/redis-sentinel.conf` 配置文件一致，可以用scp命令从redis1上复制到redis2和redis3

{% nocopy %}

```bash
# 依次输入密码000000
# 用scp命令将redis-sentinel.conf从redis1上复制到redis2和redis3
[root@redis1 ~]# scp /etc/redis-sentinel.conf root@192.168.200.22:/etc/redis-sentinel.conf
[root@redis1 ~]# scp /etc/redis-sentinel.conf root@192.168.200.23:/etc/redis-sentinel.conf
```

{% endnocopy %}

### 启动哨兵服务

{% nocopy %}

```bash
# 所有节点启动哨兵
systemctl restart redis-sentinel
systemctl enable redis-sentinel
```

{% endnocopy %}

---

## 哨兵模式信息查看

{% nocopy %}

```bash
# redis1 节点
[root@redis1 ~]# redis-cli -h 192.168.200.21 -p 26379 INFO Sentinel
# Sentinel
sentinel_masters:1
sentinel_tilt:0
sentinel_running_scripts:0
sentinel_scripts_queue_length:0
sentinel_simulate_failure_flags:0
master0:name=mymaster,status=ok,address=192.168.200.21:6379,slaves=2,sentinels=3
# redis2 节点
[root@redis2 ~]# redis-cli -h 192.168.200.22 -p 26379 INFO Sentinel
# Sentinel
sentinel_masters:1
sentinel_tilt:0
sentinel_running_scripts:0
sentinel_scripts_queue_length:0
sentinel_simulate_failure_flags:0
master0:name=mymaster,status=ok,address=192.168.200.21:6379,slaves=2,sentinels=3
# redis3 节点
[root@redis3 ~]# redis-cli -h 192.168.200.23 -p 26379 INFO Sentinel
# Sentinel
sentinel_masters:1
sentinel_tilt:0
sentinel_running_scripts:0
sentinel_scripts_queue_length:0
sentinel_simulate_failure_flags:0
master0:name=mymaster,status=ok,address=192.168.200.21:6379,slaves=2,sentinels=3
```

{% endnocopy %}

---

## 哨兵模式验证

### 主节点故障转移测试

{% nocopy %}

```bash
# redis1 节点，手动停止服务
[root@redis1 ~]# systemctl stop redis
# 切换到 redis2 节点，查看主从信息
[root@redis2 ~]# redis-cli -h 192.168.200.22 -p 6379 -a 123456 info replication
# Replication
role:slave
master_host:192.168.200.23
master_port:6379
master_link_status:up
master_last_io_seconds_ago:1
master_sync_in_progress:0
slave_repl_offset:6591
slave_priority:100
slave_read_only:1
connected_slaves:0
master_repl_offset:0
repl_backlog_active:0
repl_backlog_size:1048576
repl_backlog_first_byte_offset:0
repl_backlog_histlen:0
# redis3 节点，查看主从信息
[root@redis3 ~]# redis-cli -h 192.168.200.23 -p 6379 -a 123456 info replication
# Replication
role:master
connected_slaves:1
slave0:ip=192.168.200.22,port=6379,state=online,offset=7461,lag=0
master_repl_offset:7461
repl_backlog_active:1
repl_backlog_size:1048576
repl_backlog_first_byte_offset:2
repl_backlog_histlen:7460
```

{% endnocopy %}

### 主节点恢复

{% nocopy %}

```bash
[root@redis1 ~]# systemctl restart redis
[root@redis1 ~]# systemctl restart redis-sentinel
[root@redis1 ~]# redis-cli -h 192.168.200.21 -p 6379 -a 123456 info replication
# Replication
role:slave
master_host:192.168.200.23
master_port:6379
master_link_status:up
master_last_io_seconds_ago:1
master_sync_in_progress:0
slave_repl_offset:103524
slave_priority:100
slave_read_only:1
connected_slaves:0
master_repl_offset:0
repl_backlog_active:0
repl_backlog_size:1048576
repl_backlog_first_byte_offset:0
repl_backlog_histlen:0
```

{% endnocopy %}

Redis 哨兵模式的验证成功。
