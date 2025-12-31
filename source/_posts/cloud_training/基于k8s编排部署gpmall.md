---
title: Kubernetes应用容器化部署
date:  2023-12-02 14:20:00
tags:
---

## 实验背景与目标

在完成了 Kubernetes 集群的搭建后，接下来的核心任务是将传统的应用系统迁移至云原生环境。本实验以 GPMall 商城系统为例，通过编写 `Dockerfile` 构建各个组件的镜像，并使用 Kubernetes 的 `YAML` 文件进行编排部署。

### 实验目标

* **掌握镜像构建**：学会编写 Redis、MariaDB、ZooKeeper、Kafka 及 Nginx 应用的 Dockerfile。
* **理解多容器 Pod**：了解如何在单个 Pod 中通过 `localhost` 进行容器间通信。
* **掌握服务编排**：编写 Kubernetes 资源配置文件，实现从镜像仓库拉取镜像并启动服务。

### 中间件简介

在 GPMall 商城系统中，各中间件发挥着至关重要的作用：

* **Redis**：高性能的内存键值数据库，主要用于数据缓存，减轻后端数据库压力，提升系统并发访问性能。
* **MariaDB**：开源关系型数据库，作为 MySQL 的增强替代品，负责存储商城系统的用户信息、商品数据及订单记录。
* **ZooKeeper**：分布式协调服务，在微服务架构中负责配置维护、域名服务及分布式同步，是 Kafka 运行的基础。
* **Kafka**：分布式流处理平台，作为消息中间件实现服务间的异步通信与解耦，确保高并发场景下的数据可靠传输。
* **Nginx**：高性能 Web 服务器及反向代理，负责静态资源托管、负载均衡以及将外部请求分发至后端容器。

### 案例分析与架构

GPMall 商城是一个典型的微服务架构应用，本实验为了简化教学，采用**All-in-One Pod** 模式，即将所有服务组件（数据库、中间件、前端、后端）运行在同一个 Pod 的不同容器中。

**节点规划：**

| 节点角色 | 主机名 | IP地址 | 说明 |
| :--- | :--- | :--- | :--- |
| **Master Node** | master | 10.24.2.156 | K8s 控制节点，兼 Harbor 仓库 |
| **Worker Node** | node | 10.24.2.157 | K8s 工作节点 |

> **注意**：本试验可使用k8sallinone的环境，请根据实际实验环境替换上述 IP 地址。

**基础准备：**

1. Kubernetes 集群状态正常。
2. 将实验提供的 `GPMall.tar.gz` 上传至 master 节点 `/root` 目录并解压。

---

## 中间件服务容器化

### 1. 基础环境准备

进入解压后的目录，确认基础文件存在：

{% nocopy %}

```bash
[root@master ~]# tar -zxvf GPMall.tar.gz
[root@master ~]# cd gpmall/
```

{% endnocopy %}

查看并配置本地 Yum 源文件（用于容器内部安装软件）：

{% nocopy %}

```bash
[root@master gpmall]# cat local.repo 
[gpmall]
name=gpmall
baseurl=file:///opt/gpmall
gpgcheck=0
enabled=1
```

{% endnocopy %}

### 2. Redis 容器化

Redis 用于商城的缓存服务。

1. **编写 Dockerfile**

    查看 `Dockerfile-redis` 文件内容：

    ```dockerfile
    FROM centos:centos7.5.1804
    MAINTAINER Guo
    
    # 配置容器内的 Yum 源
    ADD gpmall.tar /opt
    RUN rm -rfv /etc/yum.repos.d/*
    ADD local.repo /etc/yum.repos.d/
    
    # 安装 Redis
    RUN yum -y install redis && yum clean all
    
    # 修改配置：允许远程连接，关闭保护模式
    RUN sed -i -e 's@bind 127.0.0.1@bind 0.0.0.0@g' /etc/redis.conf
    RUN sed -i -e 's@protected-mode yes@protected-mode no@g' /etc/redis.conf
    
    EXPOSE 6379
    ENTRYPOINT [ "/usr/bin/redis-server","/etc/redis.conf"]
    ```

2. **构建镜像**

    {% nocopy %}

    ```bash
    [root@master gpmall]# docker build -t gpmall-redis:v1.0 -f Dockerfile-redis .
    
    # 构建完成后查看镜像
    [root@master gpmall]# docker images | grep redis
    gpmall-redis    v1.0    0e71dea163a7    2 minutes ago    465MB
    ```

    {% endnocopy %}

### 3. MariaDB 容器化

MariaDB 用于存储商城的用户和商品数据。

1. **准备初始化脚本**

    数据库容器启动时需要初始化表结构和权限。查看 `mysql_init.sh`：

    ```bash
    #!/bin/bash
    mysql_install_db --user=mysql
    (mysqld_safe &) | grep a
    sleep 3s
    # 设置 root 密码
    mysqladmin -u root password '123456'
    sleep 3s
    # 授权远程访问
    mysql -uroot -p123456 -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '123456'" 
    sleep 3s
    # 导入商城数据
    mysql -uroot -p123456 -e "create database gpmall;use gpmall;source /opt/gpmall.sql;"
    ```

2. **编写 Dockerfile**

    查看 `Dockerfile-mariadb`：

    ```dockerfile
    FROM centos:centos7.5.1804
    MAINTAINER Chinaskill
    
    # 配置源
    ADD gpmall.tar /opt
    RUN rm -rfv /etc/yum.repos.d/*
    ADD local.repo /etc/yum.repos.d/
    
    # 安装 MariaDB
    RUN yum install -y MariaDB-server expect net-tools && yum clean all
    
    # 注入数据文件和脚本
    COPY gpmall.sql /opt/
    ADD mysql_init.sh /opt/
    RUN chmod +x /opt/mysql_init.sh
    
    # 执行初始化脚本（构建阶段执行）
    RUN /opt/mysql_init.sh
    
    ENV LC_ALL en_US.UTF-8
    EXPOSE 3306
    CMD ["mysqld_safe"]
    ```

3. **构建镜像**

    {% nocopy %}

    ```bash
    [root@master gpmall]# docker build -t gpmall-mariadb:v1.0 -f Dockerfile-mariadb .
    ```

    {% endnocopy %}

### 4. ZooKeeper 与 Kafka 容器化

ZooKeeper 用于管理 Kafka 集群，Kafka 用于消息队列。

1. **构建 ZooKeeper 镜像**

    ```bash
    # 编辑 Dockerfile (略，主要涉及 JDK 安装和 ZK 解压配置)
    [root@master gpmall]# cat Dockerfile-zookeeper
    FROM centos:centos7.5.1804
    MAINTAINER Chinaskill

    # 配置yum源
    ADD gpmall.tar /opt
    RUN rm -rfv /etc/yum.repos.d/*
    ADD local.repo /etc/yum.repos.d/

    # 安装JDK
    RUN yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel

    ENV work_path /usr/local

    WORKDIR $work_path

    # 安装ZooKeeper
    ADD zookeeper-3.4.14.tar.gz /usr/local
    ENV ZOOKEEPER_HOME /usr/local/zookeeper-3.4.14

    # PATH
    ENV PATH $PATH:$JAVA_HOME/bin:$JRE_HOME/bin:$ZOOKEEPER_HOME/bin
    RUN cp $ZOOKEEPER_HOME/conf/zoo_sample.cfg $ZOOKEEPER_HOME/conf/zoo.cfg

    EXPOSE 2181

    # 设置开机自启
    CMD $ZOOKEEPER_HOME/bin/zkServer.sh start-foreground
    ```

    {% nocopy %}

    ```bash
    # 构建镜像
    [root@master gpmall]# docker build -t gpmall-zookeeper:v1.0 -f Dockerfile-zookeeper .
    ```

    {% endnocopy %}

2. **构建 Kafka 镜像**

    ```bash
    # 编辑 Dockerfile
    [root@master gpmall]# cat Dockerfile-kafka
    FROM centos:centos7.5.1804
    MAINTAINER Chinaskill

    # 配置yum源
    ADD gpmall.tar /opt
    RUN rm -rfv /etc/yum.repos.d/*
    ADD local.repo /etc/yum.repos.d/

    # 安装JDK
    RUN yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel

    # 安装Kafka
    RUN mkdir /opt/kafka
    ADD kafka_2.11-1.1.1.tgz /opt/kafka
    RUN sed -i 's/num.partitions.*$/num.partitions=3/g' /opt/kafka/kafka_2.11-1.1.1/config/server.properties

    RUN echo "source /root/.bash_profile" > /opt/kafka/start.sh &&\
        echo "cd /opt/kafka/kafka_2.11-1.1.1" >> /opt/kafka/start.sh &&\
        echo "sed -i 's%zookeeper.connect=.*$%zookeeper.connect=zookeeper.mall:2181%g' /opt/kafka/kafka_2.11-1.1.1/config/server.properties" >> /opt/kafka/start.sh &&\
        echo "bin/kafka-server-start.sh config/server.properties" >> /opt/kafka/start.sh &&\
        chmod a+x /opt/kafka/start.sh

    EXPOSE 9092

    ENTRYPOINT ["sh", "/opt/kafka/start.sh"]
    ```

    > Kafka 的 Dockerfile 中包含了一个启动脚本，用于动态替换配置文件中的 Zookeeper 连接地址。

    {% nocopy %}

    ```bash
    # 构建镜像
    [root@master gpmall]# docker build -t gpmall-kafka:v1.0 -f Dockerfile-kafka .
    ```

    {% endnocopy %}

---

## 应用系统容器化

前端与后端服务将被打包在一个“富容器”中，使用 Nginx 作为反向代理和静态资源服务器，后台 Java 进程通过脚本启动。

### 1. 配置 Nginx 与 启动脚本

1. **Nginx 配置 (`default.conf`)**

    配置反向代理，将 `/user`, `/shopping`, `/cashier` 等请求转发给本地运行的 Java 端口（8081, 8082, 8083）。

    ```nginx
    server {
        listen       80;
        server_name  localhost;
        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }
        location /user { proxy_pass http://127.0.0.1:8082; }
        location /shopping { proxy_pass http://127.0.0.1:8081; }
        location /cashier { proxy_pass http://127.0.0.1:8083; }
    }
    ```

2. **启动脚本 (`front-start.sh`)**

    该脚本会在容器启动时依次启动 4 个 Jar 包，最后启动 Nginx。

    ```bash
    #!/bin/bash
    nohup java -jar /root/user-provider-0.0.1-SNAPSHOT.jar &
    sleep 6
    nohup java -jar /root/shopping-provider-0.0.1-SNAPSHOT.jar &
    sleep 6
    nohup java -jar /root/gpmall-shopping-0.0.1-SNAPSHOT.jar &
    sleep 6
    nohup java -jar /root/gpmall-user-0.0.1-SNAPSHOT.jar &
    sleep 6
    nginx -g "daemon off;"
    ```

### 2. 构建应用镜像

编写并构建 `Dockerfile-nginx`：

```bash
[root@master gpmall]# cat Dockerfile-nginx
FROM centos:centos7.5.1804
MAINTAINER Chinaskill

# 配置yum源
ADD gpmall.tar /opt
RUN rm -rfv /etc/yum.repos.d/*
ADD local.repo /etc/yum.repos.d/

RUN yum install -y cmake pcre pcre-devel openssl openssl-devel zlib-devel gcc gcc-c++ net-tools
# 安装JDK
RUN yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel

RUN yum install nginx -y
RUN rm -rf /usr/share/nginx/html/*
ADD dist.tar /usr/share/nginx/html/
COPY default.conf /etc/nginx/conf.d/
COPY gpmall-shopping-0.0.1-SNAPSHOT.jar /root
COPY gpmall-user-0.0.1-SNAPSHOT.jar /root
COPY shopping-provider-0.0.1-SNAPSHOT.jar /root
COPY user-provider-0.0.1-SNAPSHOT.jar /root
COPY front-start.sh /root
RUN chmod +x /root/front-start.sh

EXPOSE 80 443
CMD nginx -g "daemon off;"
```

{% nocopy %}

```bash
[root@master gpmall]# docker build -t gpmall-nginx:v1.0 -f Dockerfile-nginx .
```

{% endnocopy %}

---

## Kubernetes 编排部署

### 1. 推送镜像至 Harbor

为了让 K8s 集群的所有节点都能下载镜像，必须将构建好的本地镜像推送到 Harbor 私有仓库。

{% nocopy %}

```bash
# 批量打标签并推送 (将 IP 10.24.2.156 替换为你的 Harbor 地址)
[root@master gpmall]# for i in `docker images|grep gpmall|awk '{print$1":"$2}'`; do \
    docker tag $i 10.24.2.156/library/$i; \
    docker push 10.24.2.156/library/$i; \
done
```

{% endnocopy %}

### 2. 编写编排文件 (gpmall.yaml)

我们将创建一个名为 `chinaskill-mall` 的 Pod，其中包含上述 5 个容器。

**关键点解析：**

* **hostAliases**：由于所有容器在同一个 Pod 内，它们共享网络命名空间（即 IP 为 127.0.0.1）。我们需要配置 host 别名，确保应用配置文件中通过域名（如 `mysql.mall`）访问时能解析到 `127.0.0.1`。
* **NodePort**：通过 Service 将 80 端口暴露为节点的 30080 端口，供外部访问。

新建 `gpmall.yaml` 文件：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: chinaskill-mall
  labels:
    app: chinaskill-mall
spec:
  containers:
  # 1. 数据库容器
  - name: chinaskill-mariadb
    image: 10.24.2.156/library/gpmall-mariadb:v1.0
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 3306

  # 2. Redis容器
  - name: chinaskill-redis
    image: 10.24.2.156/library/gpmall-redis:v1.0
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 6379

  # 3. Zookeeper容器
  - name: chinaskill-zookeeper
    image: 10.24.2.156/library/gpmall-zookeeper:v1.0
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 2181

  # 4. Kafka容器
  - name: chinaskill-kafka
    image: 10.24.2.156/library/gpmall-kafka:v1.0
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 9092

  # 5. 前端与应用容器
  - name: chinaskill-nginx
    image: 10.24.2.156/library/gpmall-nginx:v1.0
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 80
    - containerPort: 443
    command: ["/bin/bash","/root/front-start.sh"]
  
  # 域名解析映射（Pod内容器共享host文件）
  hostAliases:
  - ip: "127.0.0.1"
    hostnames:
    - "mysql.mall"
    - "redis.mall"
    - "zookeeper.mall"
    - "kafka.mall"

---
# 定义 Service 暴露服务
apiVersion: v1
kind: Service
metadata:
  name: chinaskill-mall
spec:
  selector:
    app: chinaskill-mall
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
  type: NodePort
```

### 3. 部署与验证

1. **应用配置**

    {% nocopy %}

    ```bash
    [root@master gpmall]# kubectl apply -f gpmall.yaml 
    pod/chinaskill-mall created
    service/chinaskill-mall created
    ```

    {% endnocopy %}

2. **查看状态**

    等待所有容器状态变为 `Running`（5/5 表示 Pod 内 5 个容器全部就绪）。

    {% nocopy %}

    ```bash
    [root@master gpmall]# kubectl get pods,service
    NAME                  READY   STATUS    RESTARTS   AGE
    pod/chinaskill-mall   5/5     Running   0          40s
    
    NAME                      TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
    service/chinaskill-mall   NodePort   10.106.85.20   <none>        80:30080/TCP   40s
    ```

    {% endnocopy %}

3. **访问商城**

    打开浏览器，访问 `http://<任意节点IP>:30080` (例如 `http://10.24.2.156:30080`)。
