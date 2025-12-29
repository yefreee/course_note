---
title: 容器化部署ERP
date: 
tags:
---

## 容器化部署ERP管理系统

### ERP 系统简介

**企业资源计划**（Enterprise Resource Planning, **ERP**）是一种集成化的企业管理系统。它建立在信息技术基础上，以系统化的管理思想为企业决策层及员工提供决策和运行手段的管理平台。

#### 什么是 ERP？

可以将 ERP 理解为一个大型的"企业数据中心"，它将企业的各个部门（如销售、采购、生产、财务、人力资源等）的信息整合在一个系统中，使不同部门能够共享数据，提高工作效率和决策质量。

#### ERP 的核心功能

ERP 系统集成了以下主要模块：

- 生产资源计划与制造管理
- 财务管理与会计
- 销售与采购管理
- 库存与分销管理
- 质量管理与实验室管理
- 人力资源管理
- 业务流程管理与数据分析

#### 为什么需要 ERP？

ERP 的主要目标是改善企业业务流程，提高企业核心竞争力，帮助企业在网络经济时代实现资源的优化配置。

## 容器化部署 MariaDB

### 基础环境准备

- 首先上传资源包ERP.tar.gz到家目录下、解压、导入docker镜像。

  {% nocopy %}

  ```bash
  # 下载并解压资源包，-z: gzip压缩，-x: 解压，-v: 显示过程，-f: 指定文件
  [root@master ~]# tar -zxvf ERP.tar.gz

  # 导入CentOS基础镜像到本地Docker镜像库
  [root@master ~]# docker load -i ERP/CentOS_7.9.2009.tar
  ```

  {% endnocopy %}

### 编写 Dockerfile 及相关脚本

切换到 Worker 节点的工作目录，准备构建所需的配置文件。

**1. 编写 yum 源配置文件 `local.repo`**

{% nocopy %}

```ini
# 进入ERP工作目录
[root@master ~]# cd ERP/
# 使用vi编辑器创建并编辑local.repo文件
[root@master ERP]# vi local.repo

[erp]
name=erp
baseurl=file:///root/yum
gpgcheck=0
enabled=1
```

{% endnocopy %}

**2. 编写数据库初始化脚本 `mysql_init.sh`**

{% nocopy %}

```bash
# 创建数据库初始化脚本
[root@master ERP]# vi mysql_init.sh

#!/bin/bash
# 初始化MariaDB数据库文件
mysql_install_db --user=root
# 后台启动MariaDB服务
mysqld_safe --user=root &
# 等待8秒确保服务启动完成
sleep 8
# 设置数据库root用户密码
mysqladmin -u root password 'tshoperp'
# 授权root用户远程访问权限
mysql -uroot -ptshoperp -e "grant all on *.* to 'root'@'%' identified by 'tshoperp'; flush privileges;"
# 创建业务数据库并导入SQL初始化数据
mysql -uroot -ptshoperp -e " create database jsh_erp;use jsh_erp;source /opt/jsh_erp.sql;"
```

{% endnocopy %}

**3. 编写 `Dockerfile-mariadb`**

{% nocopy %}

```dockerfile
# 创建MariaDB镜像构建文件
[root@master ERP]# vi Dockerfile-mariadb

# 指定基础镜像
FROM centos:centos7.9.2009
# 维护者信息
MAINTAINER Chinaskills
# 清理默认yum源
RUN rm -rf /etc/yum.repos.d/*
# 拷贝本地yum源配置
COPY local.repo /etc/yum.repos.d/
# 拷贝yum仓库数据
COPY yum /root/yum
# 设置系统语言环境
ENV LC_ALL en_US.UTF-8
# 安装MariaDB服务端
RUN yum -y install mariadb-server
# 拷贝数据库脚本和初始化脚本
COPY jsh_erp.sql /opt/
COPY mysql_init.sh /opt/
# 执行初始化脚本
RUN bash /opt/mysql_init.sh
# 暴露3306端口
EXPOSE 3306
# 容器启动时运行MariaDB服务
CMD ["mysqld_safe","--user=root"]
```

{% endnocopy %}

### 构建镜像

在 Master 节点执行镜像构建命令：

{% nocopy %}

```bash
# 构建MariaDB镜像，-t指定镜像名和标签，-f指定Dockerfile文件
[root@master ERP]# docker build -t erp-mysql:v1.0 -f Dockerfile-mariadb .
```

{% endnocopy %}

*输出示例：*

{% nocopy %}

```text
[+] Building 0.3s (13/13) FINISHED                             docker:default 
 => [internal] load build definition from Dockerfile-mariadb              0.0s
 ...
 => => naming to docker.io/library/erp-mysql:v1.0                        0.0s
```

{% endnocopy %}

## 容器化部署 Redis

### 编写 Dockerfile

Redis 服务需要修改配置文件以允许外部访问并关闭保护模式。

{% nocopy %}

```dockerfile
# 创建Redis镜像构建文件
[root@master ERP]# vi Dockerfile-redis

# 指定基础镜像
FROM centos:centos7.9.2009
# 维护者信息
MAINTAINER Chinaskills
# 清理默认yum源
RUN rm -rf /etc/yum.repos.d/*
# 拷贝本地yum源配置
COPY local.repo /etc/yum.repos.d/
# 拷贝yum仓库数据
COPY yum /root/yum
# 安装Redis服务
RUN yum -y install redis
# 修改Redis配置：允许所有IP访问，关闭保护模式
RUN sed -i 's/127.0.0.1/0.0.0.0/g' /etc/redis.conf && \
    sed -i 's/protected-mode yes/protected-mode no/g' /etc/redis.conf
# 暴露6379端口
EXPOSE 6379
# 容器启动时运行Redis服务并加载配置文件
CMD ["/usr/bin/redis-server","/etc/redis.conf"]
```

{% endnocopy %}

### 构建镜像

{% nocopy %}

```bash
# 构建Redis镜像
[root@master ERP]# docker build -t erp-redis:v1.0 -f Dockerfile-redis .
```

{% endnocopy %}

*输出示例：*

{% nocopy %}

```text
[+] Building 14.0s (11/11) FINISHED
 ...
 => => naming to docker.io/library/erp-redis:v1.0                       0.0s
```

{% endnocopy %}

## 容器化部署前端服务 (Nginx)

### 编写 Dockerfile

前端服务基于 Nginx 构建，需将静态资源包 `app.tar.gz` 解压至容器内。

{% nocopy %}

```dockerfile
# 创建Nginx前端镜像构建文件
[root@master ERP]# vi Dockerfile-nginx

# 指定基础镜像
FROM centos:centos7.9.2009
# 维护者信息
MAINTAINER Chinaskills
# 清理默认yum源
RUN rm -rf /etc/yum.repos.d/*
# 拷贝本地yum源配置
COPY local.repo /etc/yum.repos.d/
# 拷贝yum仓库数据
COPY yum /root/yum
# 安装Nginx服务
RUN yum -y install nginx
# 拷贝自定义Nginx配置文件
COPY nginx/nginx.conf /etc/nginx/nginx.conf
# 拷贝前端静态资源包
COPY nginx/app.tar.gz /
# 解压静态资源到根目录
RUN tar -zxvf /app.tar.gz -C /
# 打印初始化完成信息
RUN /bin/bash -c 'echo init ok'
# 暴露80端口
EXPOSE 80
# 容器启动时以前台模式运行Nginx
CMD ["nginx","-g","daemon off;"]
```

{% endnocopy %}

### 构建镜像

{% nocopy %}

```bash
# 构建Nginx前端镜像
[root@master ERP]# docker build -t erp-nginx:v1.0 -f Dockerfile-nginx .
```

{% endnocopy %}

## 容器化部署 ERP 后端服务

### 编写 Dockerfile

后端服务依赖 Java 环境，需安装 OpenJDK。

{% nocopy %}

```dockerfile
# 创建ERP后端服务镜像构建文件
[root@master ERP]# vi Dockerfile-erp

# 指定基础镜像
FROM centos:centos7.9.2009
# 维护者信息
MAINTAINER Chinaskills
# 拷贝后端可执行jar包
COPY app.jar /root
# 添加yum仓库数据
ADD yum /root/yum
# 清理默认yum源
RUN rm -rfv /etc/yum.repos.d/*
# 拷贝本地yum源配置
COPY local.repo /etc/yum.repos.d/local.repo
# 安装JDK 1.8环境
RUN yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
# 暴露后端服务端口9999
EXPOSE 9999
# 容器启动时运行Java后端程序
CMD java -jar /root/app.jar
```

{% endnocopy %}

### 构建镜像

{% nocopy %}

```bash
# 构建ERP后端服务镜像
[root@master ERP]# docker build -t erp-service:v1.0 -f Dockerfile-erp .
```

{% endnocopy %}

## 编排部署 ERP

使用 Docker Compose 对上述四个服务（MySQL, Redis, ERP-Server, Nginx）进行统一编排。

### 编写 docker-compose.yaml

{% nocopy %}

```yaml
# 创建Docker Compose编排文件
[root@master ERP]# vi docker-compose.yaml

version: '3' # Compose文件版本
services:
  erp-mysql: # 数据库服务
    restart: always # 容器退出时总是重启
    image: erp-mysql:v1.0 # 使用的镜像
    container_name: erp-mysql # 容器名称
    environment:
      - "MYSQL_DATABASE=jsh_erp" # 设置环境变量：数据库名
    ports:
      - 3306:3306 # 端口映射：宿主机3306 -> 容器3306
  erp-redis: # Redis缓存服务
    image: erp-redis:v1.0
    container_name: erp-redis
    restart: always
    ports:
      - 6379:6379
    # 启动命令：设置端口、密码并开启AOF持久化
    command: redis-server --port 6379 --requirepass tshoperp --appendonly yes

  erp-server: # ERP后端服务
    restart: always
    image: erp-service:v1.0
    container_name: erp-server
    ports:
      - 9999:9999

  erp-web-ui: # ERP前端服务
    restart: always
    image: erp-nginx:v1.0
    container_name: erp-web-ui
    ports:
      - 8888:80 # 端口映射：宿主机8888 -> 容器80
```

{% endnocopy %}

### 启动服务与验证

**安装docker-compose工具：**

{% nocopy %}

```bash
[root@master ERP]# cp /root/compose/docker-compose /usr/bin/docker-compose
[root@master ERP]# chmod +x /usr/bin/docker-compose
```

{% endnocopy %}

**启动服务：**

{% nocopy %}

```bash
# 后台启动所有编排的服务
[root@master ERP]# docker-compose up -d
```

{% endnocopy %}

*输出：*

{% nocopy %}

```text
Creating network "erp_default" with the default driver
Creating erp-redis  ... done
Creating erp-mysql  ... done
Creating erp-server ... done
Creating erp-web-ui ... done
```

{% endnocopy %}

**查看运行状态：**

{% nocopy %}

```bash
# 查看当前Compose管理的所有容器运行状态
[root@master ERP]# docker-compose ps
```

{% endnocopy %}

*状态检查：*

{% nocopy %}

```text
   Name                 Command               State                    Ports                  
----------------------------------------------------------------------------------------------
erp-mysql    mysqld_safe --user=root          Up      0.0.0.0:3306->3306/tcp,:::3306->3306/tcp
erp-redis    redis-server --port 6379 - ...   Up      0.0.0.0:6379->6379/tcp,:::6379->6379/tcp
erp-server   /bin/sh -c java -jar /root ...   Up      0.0.0.0:9999->9999/tcp,:::9999->9999/tcp
erp-web-ui   nginx -g daemon off;             Up      0.0.0.0:8888->80/tcp,:::8888->80/tcp    
```

{% endnocopy %}

### 访问测试

在浏览器中输入访问地址：`http://<IP地址>:8888`。

**登录操作：**

- **用户名**：admin
- **密码**：123456

登录成功后进入系统首页
