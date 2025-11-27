---
title: SkyWalking 分布式链路追踪部署实验指导书
date: 
tags:
---

## 1. 实验简介与理论基础

### 1.1 实验背景

在微服务架构中，一个用户请求往往需要经过多个服务节点（如：前端 -> 网关 -> 业务服务 -> 数据库）。如果系统出现故障或响应变慢，传统的日志排查非常困难。
**SkyWalking** 是一个国产开源的 APM（应用性能管理）系统，它可以像“X光”一样扫描整个系统，生成调用链路图，帮助开发者快速定位性能瓶颈。

### 1.2 实验架构组件

* **SkyWalking Agent (探针)**: 安装在应用服务器（Mall）上，自动收集程序的运行数据，发送给 OAP。
* **SkyWalking OAP (分析服务)**: 接收探针数据，进行聚合分析（生成拓扑图、计算耗时）。
* **Elasticsearch (存储服务)**: OAP 分析后的数据需要持久化存储，ES 是其首选的高性能数据库。
* **SkyWalking UI (可视化界面)**: 网页控制台，展示监控结果。

### 1.3 节点规划

| IP地址 | 主机名 | 角色 | 部署组件 |
| :--- | :--- | :--- | :--- |
| **172.128.11.32** | **node-1** | SkyWalking 服务端 | Elasticsearch + OAP Server + Web UI |
| **172.128.11.42** | **mall** | 应用商城节点 | Nginx + Java应用(4个) + MySQL + Redis + Kafka + ZK + **Agent探针** |

---

## 2. 部署 SkyWalking 服务端 (Node-1)

**⚠️ 注意：** 本章所有命令均在 **172.128.11.32** 节点执行。

### 2.1 基础环境准备

**1. 修改主机名**
为了方便集群管理和日志识别,首先修改主机名。

```bash
# 设置永久主机名为 node-1
[root@localhost ~]# hostnamectl set-hostname node-1
# 重新加载 shell 环境,使新主机名立即在命令提示符中生效
[root@localhost ~]# bash
[root@node-1 ~]# 
```

> **💡 解释**：`bash` 命令用于重新加载 Shell 环境，使主机名修改立即在提示符中显示。

**2. 安装 JDK 1.8**
SkyWalking 和 Elasticsearch 均依赖 Java 环境。

```bash
# 假设安装包已上传至 /root 目录
[root@node-1 ~]# cd /root
[root@node-1 ~]# tar -zxvf jdk-8u144-linux-x64.tar.gz -C /usr/local/

# 配置环境变量
[root@node-1 ~]# vi /etc/profile
```

在文件末尾添加以下内容：

```bash
# 设置 JAVA_HOME 环境变量,指向 JDK 安装目录
export JAVA_HOME=/usr/local/jdk1.8.0_144
# 配置 Java 类路径,包含运行时库、开发工具包等核心 jar 文件
export CLASSPATH=.:${JAVA_HOME}/jre/lib/rt.jar:${JAVA_HOME}/lib/dt.jar:${JAVA_HOME}/lib/tools.jar
# 将 Java 可执行文件路径添加到系统 PATH,使 java、javac 等命令全局可用
export PATH=$PATH:${JAVA_HOME}/bin
```

使其生效并验证：

```bash
[root@node-1 ~]# source /etc/profile
[root@node-1 ~]# java -version
java version "1.8.0_144" ...
```

### 2.2 部署 Elasticsearch 7.17.0 (存储层)

**1. 解压与目录创建**

```bash
# 解压 Elasticsearch 安装包到 /opt 目录
# -z: 使用 gzip 解压  -x: 提取文件  -v: 显示详细过程  -f: 指定文件  -C: 指定解压目标目录
[root@node-1 ~]# tar -zxvf elasticsearch-7.17.0-linux-x86_64.tar.gz -C /opt
[root@node-1 ~]# cd /opt/elasticsearch-7.17.0/
# 创建数据存储目录
[root@node-1 elasticsearch-7.17.0]# mkdir data
```

**2. 创建专用用户**
> **💡 理论加油站**：Elasticsearch 默认禁止使用 `root` 用户启动。这是因为 ES 拥有强大的脚本执行能力，如果被黑客攻破且是 root 权限，会对服务器造成毁灭性打击。因此必须创建普通用户。

```bash
# 创建名为 elsearch 的用户组
[root@node-1 elasticsearch-7.17.0]# groupadd elsearch
# 创建用户 elsearch: -g 指定主组, -p 设置密码(已加密)
[root@node-1 elasticsearch-7.17.0]# useradd elsearch -g elsearch -p elasticsearch
# 递归修改目录所有权: -R 递归处理所有子目录和文件, 格式为 用户:组
[root@node-1 elasticsearch-7.17.0]# chown -R elsearch:elsearch /opt/elasticsearch-7.17.0
```

**3. 修改配置文件**

```bash
[root@node-1 elasticsearch-7.17.0]# vi config/elasticsearch.yml
```

**添加/修改内容如下（注意冒号后必须有一个空格）：**

```yaml
cluster.name: my-application              # 集群名称
node.name: node-1                         # 当前节点名称
path.data: /opt/elasticsearch-7.17.0/data # 数据存储路径
path.logs: /opt/elasticsearch-7.17.0/logs # 日志路径
network.host: 0.0.0.0                     # 允许任何IP访问（不仅是本地）
cluster.initial_master_nodes: ["node-1"]  # 初始化时的主要节点

# 允许跨域（便于后续安装可视化插件调试）
http.cors.enabled: true
http.cors.allow-origin: "*"
http.cors.allow-headers: Authorization,X-Requested-With,Content-Length,Content-Type
```

**4. 修改系统内核参数**
> **💡 理论加油站**：Elasticsearch 基于 Lucene，大量使用 `mmap` 技术来映射文件到内存。Linux 默认的内存映射数量限制（vm.max_map_count）太小，会导致 ES 启动失败。同时 ES 会打开大量文件，需要增加文件句柄限制。

```bash
# 1. 修改文件句柄限制
[root@node-1 ~]# vi /etc/security/limits.conf
# 在文件末尾添加：
# * 表示对所有用户生效
# hard: 硬限制(不可超越)  soft: 软限制(可临时超越但不超过 hard)
# nofile: 最大打开文件数  65536: 允许同时打开 65536 个文件
* hard    nofile           65536
* soft    nofile           65536

# 2. 修改虚拟内存限制
[root@node-1 ~]# vi /etc/sysctl.conf
# 添加：
# vm.max_map_count: 限制进程可拥有的虚拟内存区域(VMA)数量
# 262144: ES 推荐值,确保有足够的内存映射区域用于索引文件
vm.max_map_count=262144

# 3. 使参数立即生效 (-p 表示从配置文件重新加载内核参数)
[root@node-1 ~]# sysctl -p
```

**⚠️ 提示**：建议执行完上述步骤后，执行 `reboot` 重启服务器以确保所有系统限制彻底生效。

**5. 启动 Elasticsearch**

```bash
[root@node-1 ~]# cd /opt/elasticsearch-7.17.0/
# 切换到 elsearch 用户(ES 不允许 root 启动)
[root@node-1 elasticsearch-7.17.0]# su elsearch   
# 以守护进程(后台)模式启动 Elasticsearch, -d 参数表示 daemon 后台运行
[elsearch@node-1 elasticsearch-7.17.0]$ ./bin/elasticsearch -d
# 退出 elsearch 用户,返回 root 用户环境
[elsearch@node-1 elasticsearch-7.17.0]$ exit
```

* `su elsearch`: 切换到普通用户 elsearch,因为 ES 禁止 root 启动。
* `-d`: Daemon(守护进程)模式,在后台运行不阻塞终端。
* `exit`: 退出当前用户 shell,返回到 root 用户。

**验证**：

```bash
# 检查端口 9200 是否正在监听
# -n: 以数字形式显示地址和端口  -t: 显示 TCP 连接  -p: 显示进程信息  -l: 仅显示监听状态的套接字
[root@node-1 ~]# netstat -ntpl | grep 9200
# 看到 tcp6 :::9200 LISTEN 则成功
```

### 2.3 部署 SkyWalking OAP 服务 (分析层)

**1. 解压安装包**

```bash
[root@node-1 ~]# cd /root
[root@node-1 ~]# tar -zxvf apache-skywalking-apm-es7-8.0.0.tar.gz -C /opt
[root@node-1 ~]# cd /opt/apache-skywalking-apm-bin-es7/
```

**2. 配置 OAP 连接 ES**
我们需要告诉 OAP 服务，数据不要存内存，而是存到刚才搭建的 ES 里。

```bash
[root@node-1 apache-skywalking-apm-bin-es7]# vi config/application.yml
```

找到 `storage:` 模块,修改如下：

```yaml
cluster:
  # 集群选择器: standalone=单机模式(不做集群), cluster=集群模式
  selector: ${SW_CLUSTER:standalone}

storage:
  # 存储选择器: 指定使用 elasticsearch7 作为持久化存储
  selector: ${SW_STORAGE:elasticsearch7}
  elasticsearch7:
    # 命名空间: 用于在同一个 ES 中隔离不同环境的数据(如 dev/prod),空字符串表示不使用命名空间
    nameSpace: ${SW_NAMESPACE:""}
    # ES 集群节点地址: 格式为 IP:端口, 多个节点用逗号分隔
    clusterNodes: ${SW_STORAGE_ES_CLUSTER_NODES:172.128.11.32:9200}
```

**3. 启动 OAP**

```bash
[root@node-1 apache-skywalking-apm-bin-es7]# ./bin/oapService.sh
SkyWalking OAP started successfully!
```

**验证**：
检查端口 `11800` (gRPC，用于接收探针数据) 和 `12800` (HTTP，用于UI查询)。

```bash
[root@node-1 ~]# netstat -ntpl | grep -E '11800|12800'
```

### 2.4 部署 SkyWalking UI 服务 (展现层)

**1. 修改 UI 端口**
默认端口是 8080，极易与 Tomcat 或 Nginx 冲突，我们将其改为 8888。

```bash
[root@node-1 apache-skywalking-apm-bin-es7]# vi webapp/webapp.yml
```

```yaml
server:
  port: 8888
```

**2. 启动 UI**

```bash
[root@node-1 apache-skywalking-apm-bin-es7]# ./bin/webappService.sh
SkyWalking Web Application started successfully!
```

**验证**：
浏览器访问 `http://172.128.11.32:8888`。此时页面为空白，因为还没有应用接入。

---

## 3. 部署应用商城服务 (Mall Node)

**⚠️ 注意：** 本章所有命令均在 **172.128.11.42** 节点执行。

### 3.1 基础环境准备

**1. 修改主机名与 Hosts**

```bash
[root@localhost ~]# hostnamectl set-hostname mall
[root@localhost ~]# bash
[root@mall ~]# vi /etc/hosts
```

> **💡 技巧**：在 hosts 文件中做域名映射，可以让应用程序代码中写死的域名（如 mysql.mall）正确指向本地 IP，避免修改源码。

添加如下内容：

```text
127.0.0.1   localhost
172.128.11.42 mall
172.128.11.42 kafka.mall
172.128.11.42 mysql.mall
172.128.11.42 redis.mall
172.128.11.42 zookeeper.mall
```

**2. 配置本地 Yum 源**

```bash
[root@mall ~]# mv /etc/yum.repos.d/* /media/ # 备份原有源
[root@mall ~]# mkdir -p /root/gpmall
[root@mall ~]# tar -zxvf gpmall-single.tar.gz -C /root/gpmall
[root@mall ~]# vi /etc/yum.repos.d/local.repo
```

写入内容：

```ini
[mall]                                                    # yum 源标识 ID
name=mall                                                 # yum 源显示名称
baseurl=file:///root/gpmall/gpmall-single/gpmall-repo   # 本地源路径(file:// 协议)
gpgcheck=0                                                # 是否检查 GPG 签名: 0=不检查, 1=检查
enabled=1                                                 # 是否启用该源: 0=禁用, 1=启用
```

**3. 安装基础软件**

```bash
# 清理 yum 缓存并重建索引: clean all=清除所有缓存, makecache=生成新缓存
[root@mall ~]# yum clean all && yum makecache
# 安装软件包: -y 自动确认, 安装 JDK、Redis、Nginx、MariaDB 数据库及其服务端
[root@mall ~]# yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel redis nginx mariadb mariadb-server
```

### 3.2 部署中间件

**1. 部署 ZooKeeper (分布式协调)**
Kafka 依赖 ZK 运行。

```bash
[root@mall ~]# cd /root/gpmall-single
# 解压 ZooKeeper 安装包
[root@mall gpmall-single]# tar -zxvf zookeeper-3.4.14.tar.gz
[root@mall gpmall-single]# cd zookeeper-3.4.14/conf/
# 将示例配置文件重命名为正式配置文件(ZK 启动时会读取 zoo.cfg)
[root@mall conf]# mv zoo_sample.cfg zoo.cfg
[root@mall conf]# cd ../bin
# 启动 ZooKeeper 服务
[root@mall bin]# ./zkServer.sh start
```

**2. 部署 Kafka (消息队列)**

```bash
[root@mall bin]# cd /root/gpmall-single
[root@mall gpmall-single]# tar -zxvf kafka_2.11-1.1.1.tgz
[root@mall gpmall-single]# cd kafka_2.11-1.1.1/bin/
# -daemon 表示后台启动
[root@mall bin]# ./kafka-server-start.sh -daemon ../config/server.properties
```

**3. 初始化数据库 MariaDB**

```bash
# 启动 MariaDB 数据库服务
[root@mall ~]# systemctl start mariadb
# 设置开机自启动
[root@mall ~]# systemctl enable mariadb

# 使用 mysqladmin 工具设置 root 用户密码: -u 指定用户名, password 子命令设置密码
[root@mall ~]# mysqladmin -uroot password 123456

# 配置编码 (避免中文乱码)
[root@mall ~]# vi /etc/my.cnf
```

添加`[mysqld]`,在 `[mysqld]` 下方添加：

```ini
# 客户端连接时自动执行的 SQL: 设置连接校对规则为 utf8_unicode_ci
init_connect='SET collation_connection = utf8_unicode_ci'
# 设置客户端连接字符集为 utf8
init_connect='SET NAMES utf8'
# 服务器默认字符集设为 utf8
character-set-server=utf8
# 服务器默认校对规则(排序、比较规则)
collation-server=utf8_unicode_ci
# 跳过客户端字符集握手,强制使用服务器端字符集配置
skip-character-set-client-handshake
```

重启数据库并导入数据：

```bash
[root@mall ~]# systemctl restart mariadb
[root@mall ~]# mysql -uroot -p123456
```

在 `MariaDB [(none)]>` 提示符下执行 SQL：

```sql
-- 授予本地 root 用户所有权限: *.* 表示所有数据库的所有表, with grant option 允许此用户给其他用户授权
grant all privileges on *.* to root@localhost identified by '123456' with grant option;
-- 授予远程访问权限: % 表示任意 IP 都可以连接
grant all privileges on *.* to root@"%%" identified by '123456' with grant option;
-- 创建商城数据库
create database gpmall;
-- 切换到 gpmall 数据库
use gpmall;
-- 导入 SQL 脚本文件(包含表结构和初始数据)
source /root/gpmall/gpmall/gpmall.sql
-- 退出 MySQL 客户端
exit;
```

**4. 启动 Redis**

```bash
[root@mall ~]# vi /etc/redis.conf
# 1. 注释掉 bind 127.0.0.1 (前面加#): 默认只允许本地访问,注释后允许外部访问
# 2. 将 protected-mode yes 改为 no: 关闭保护模式,允许无密码远程连接(生产环境建议设置密码)
# 启动 Redis 服务
[root@mall ~]# systemctl start redis
```

### 3.3 部署前端 Nginx

**1. 部署静态资源**

```bash
# 清空 Nginx 默认网站目录: -r 递归删除, -f 强制删除不提示
[root@mall ~]# rm -rf /usr/share/nginx/html/*
# 复制前端编译后的静态文件到 Nginx 目录: -r 递归, -v 显示详细信息, -f 强制覆盖
[root@mall ~]# cp -rvf /root/gpmall/gpmall-single/dist/* /usr/share/nginx/html/
```

**2. 配置反向代理**
> **💡 理论加油站**：浏览器访问的是 80 端口，Nginx 负责根据路径（如 `/user`）将请求转发给后端不同的 Java 服务端口（如 8082）。

```bash
[root@mall ~]# vi /etc/nginx/conf.d/default.conf
```

```nginx
server {
    listen       80;                        # 监听 80 端口(HTTP 默认端口)
    server_name  localhost;                 # 服务器名称
    location / {                            # 根路径匹配
        root   /usr/share/nginx/html;       # 静态文件根目录
        index  index.html index.htm;        # 默认首页文件
    }
    # 转发到用户服务: 所有 /user 开头的请求转发到本机 8082 端口(用户微服务)
    location /user {
        proxy_pass http://127.0.0.1:8082;
    }
    # 转发到商品服务: 所有 /shopping 开头的请求转发到 8081 端口(商品微服务)
    location /shopping {
        proxy_pass http://127.0.0.1:8081;
    }
    # 转发到收银台服务: 所有 /cashier 开头的请求转发到 8083 端口(支付微服务)
    location /cashier {
        proxy_pass http://127.0.0.1:8083;
    }
}
```

**3. 解决 SELinux 权限并启动**

```bash
# 永久允许 Nginx(httpd) 发起网络连接(反向代理需要): -P 永久生效, 1 表示开启
[root@mall ~]# setsebool -P httpd_can_network_connect 1
# 重启 Nginx 服务使配置生效
[root@mall ~]# systemctl restart nginx
```

### 3.4 部署 SkyWalking Agent 并启动应用 (核心步骤)

**1. 获取 Agent 包**
Agent 不需要安装,只需要把文件放到服务器上。我们直接从 node-1 节点复制过来。

```bash
# 使用 scp 从远程服务器复制文件: -r 递归复制整个目录
# 格式: scp -r 用户名@源IP:源路径 目标路径
[root@mall ~]# scp -r root@172.128.11.32:/opt/apache-skywalking-apm-bin-es7/agent /root/
# 输入 node-1 的 root 密码
```

**2. 配置 Agent 全局信息**

```bash
[root@mall ~]# vi /root/agent/config/agent.config
```

修改以下关键项：

```properties
# 1. 探针名称
agent.service_name=${SW_AGENT_NAME:my-application}

# 2. OAP 后端收集器地址: 探针将数据发送到此地址，11800 是 OAP 的 gRPC 接收端口
collector.backend_service=${SW_AGENT_COLLECTOR_BACKEND_SERVICES:172.128.11.32:11800}
```

**3. 启动应用（挂载探针）**
> **💡 理论加油站**：Java Agent 技术允许我们在不修改源代码的情况下，通过 `-javaagent` 参数在 JVM 启动时“注入”监控代码。
> 关键参数解析：
>
> * `-javaagent:/xxx/skywalking-agent.jar`: 指定探针路径。
> * `-Dskywalking.agent.service_name=xxx`: **非常重要**，为当前微服务起一个在监控大屏上显示的名字。

```bash
[root@mall ~]# cd /root/gpmall/gpmall-single
```

**依次执行以下 4 条命令（建议复制粘贴）：**

**① 启动 Shopping Provider (商品服务)**

```bash
# nohup: 忽略挂断信号,即使终端关闭进程也继续运行,输出会重定向到 nohup.out
# -javaagent: JVM 启动参数,在应用启动前加载 SkyWalking 探针 jar 包
# -Dskywalking.agent.service_name: 设置 JVM 系统属性,指定服务名称(覆盖配置文件)
# -jar: 指定要运行的 Spring Boot 应用 jar 包
# &: 在后台运行
[root@mall gpmall-single]# nohup java -javaagent:/root/agent/skywalking-agent.jar \
-Dskywalking.agent.service_name=shopping-provider \
-jar shopping-provider-0.0.1-SNAPSHOT.jar &
```

**② 启动 User Provider (用户服务)**

```bash
# 启动用户服务提供者,指定服务名为 user-provider
[root@mall gpmall-single]# nohup java -javaagent:/root/agent/skywalking-agent.jar \
-Dskywalking.agent.service_name=user-provider \
-jar user-provider-0.0.1-SNAPSHOT.jar &
```

**③ 启动 Gpmall Shopping (商城Web层)**

```bash
# 启动商城 Web 应用,负责处理前端商品相关请求
[root@mall gpmall-single]# nohup java -javaagent:/root/agent/skywalking-agent.jar \
-Dskywalking.agent.service_name=gpmall-shopping \
-jar gpmall-shopping-0.0.1-SNAPSHOT.jar &
```

**④ 启动 Gpmall User (用户Web层)**

```bash
# 启动用户 Web 应用,负责处理前端用户相关请求
[root@mall gpmall-single]# nohup java -javaagent:/root/agent/skywalking-agent.jar \
-Dskywalking.agent.service_name=gpmall-user \
-jar gpmall-user-0.0.1-SNAPSHOT.jar &
```

---

## 4. 实验验证

### 4.1 产生业务流量

SkyWalking 是被动监控系统，**没有访问就没有数据**。

1. 打开本地电脑浏览器，访问 `http://172.128.11.42`。
2. **登录**：用户名 `test`，密码 `test`。
3. **购物**：点击首页商品 -> 点击“现在购买” -> 提交订单。
4. 多操作几次，确保产生足够的调用链数据。

### 4.2 查看监控效果

1. 浏览器访问 SkyWalking UI：`http://172.128.11.32:8888`。
2. 点击右上角 **“Auto”** 开启自动刷新。
3. **Dashboard (仪表盘)**：查看 Service 列表，应包含 `shopping-provider` 等4个服务。
4. **Topology (拓扑图)**：这是最酷的功能。点击顶部菜单 "Topology"，你可以看到一个完整的调用关系图：
    * 用户 -> Nginx -> `gpmall-user` -> `user-provider` -> MySQL
    * 这种可视化的链路图能帮你瞬间看懂系统架构。

---

## 5. 常见问题排查 (Troubleshooting)

**Q1: SkyWalking UI 只有界面，没有数据？**

* **检查时间范围**：UI 右下角的时间是否是“Current”或者包含了当前时间。
* **检查探针日志**：在 Mall 节点查看 `/root/agent/logs/skywalking-api.log`。如果看到 `Connect to 172.128.11.32:11800 [GRPC] failed`，说明网络不通或 OAP 服务没起。
* **检查时间同步**：如果 Node-1 和 Mall 的系统时间相差太大，数据会被丢弃。执行 `date` 命令检查。

**Q2: Elasticsearch 启动报错 "max virtual memory areas vm.max_map_count ... is too low"**

* 这是最经典的错误。说明 `sysctl -p` 没执行或者没生效。重新执行 `sysctl -w vm.max_map_count=262144` 即可。

**Q3: 应用启动后无法访问商城？**

* 使用 `jps` 命令(Java Process Status)查看所有 Java 进程,应该有 5 个（1个 Kafka, 4个应用 Jar包）。
* 如果没有,查看当前目录下的 `nohup.out` 文件查找报错原因（通常是数据库连不上或 ZK 没起）。
* 也可以使用 `ps aux | grep java` 查看进程详情,或 `tail -f nohup.out` 实时查看日志。
