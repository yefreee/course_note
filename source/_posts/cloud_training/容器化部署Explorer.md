---
title: 容器化部署KodExplorer
date: 
tags:
---

## 容器化部署 KodExplorer 资源管理器

### 可道云 (KodExplorer) 介绍

可道云是一款开源的 Web 文件管理系统，提供云端文件存储、管理和在线协作功能。

**主要特性：**

- **轻量级部署**：基于 PHP 开发，无需复杂配置即可快速部署
- **多用户支持**：支持多用户、多角色、权限管理
- **丰富的文件操作**：支持上传、下载、预览、编辑、压缩、分享等功能
- **在线编辑**：内置多种文档和代码编辑器
- **跨平台兼容**：支持 Windows、Linux、macOS，可在任何现代浏览器中使用
- **插件扩展**：提供插件机制支持功能扩展
- **文件预览**：支持图片、视频、音频、Office 文档等多种格式预览

**应用场景：**

适用于个人云盘、企业文件共享、团队协作、资源管理等场景，是传统网盘的轻量级替代方案。

### 案例目标

本案例旨在通过容器化技术部署 KodExplorer 资源管理系统，主要达成以下目标：

- 掌握 Dockerfile 的基本编写语法与规范。
- 掌握常用中间件（MariaDB, Redis, Nginx, PHP）的容器化构建方法。
- 了解并实现 KodExplorer 资源管理系统的全栈容器化编排部署。

### 案例准备

#### 规划节点

本案例采用 Kubernetes 单节点或 Docker 环境进行实验，节点规划如下表所示：

| IP | 主机名 | 节点说明 |
| :--- | :--- | :--- |
| 10.24.2.63 | master | Kubernetes ALL_IN_ONE 节点 / Docker 宿主机 |

#### 基础准备

- **环境要求**：确保主机已安装 Docker Engine 及 Docker Compose。
- **资源包**：需准备好 CentOS 7.9 基础镜像及 KodExplorer 安装包。

### 案例实施

#### 容器化部署 MariaDB

##### 基础环境准备

上传Explorer.tar.gz到系统家目录、解压、导入基础镜像：

{% nocopy %}

```bash
# 解压KodExplorer资源包
[root@master ~]# tar -zxvf Explorer.tar.gz
# 导入CentOS 7.9基础镜像
[root@master ~]# docker load -i KodExplorer/CentOS_7.9.2009.tar
```

{% endnocopy %}

##### 编写构建文件

进入目录，编写数据库初始化脚本 `mysql_init.sh`：

{% nocopy %}

```bash
# 进入KodExplorer工作目录
[root@master ~]# cd KodExplorer/
# 创建并编辑数据库初始化脚本
[root@master KodExplorer]# vi mysql_init.sh
```

{% endnocopy %}

{% nocopy %}

```bash
#!/bin/bash
# 初始化MariaDB数据库
mysql_install_db --user=root
# 后台启动MariaDB服务
mysqld_safe --user=root &
# 等待服务启动
sleep 8
# 设置数据库root用户密码为root
mysqladmin -u root password 'root'
# 授权root用户远程访问权限
mysql -uroot -proot -e "grant all on *.* to 'root'@'%' identified by 'root'; flush privileges;"
```

{% endnocopy %}

配置本地 YUM 源文件 `local.repo`：

{% nocopy %}

```ini
[yum]
name=yum
baseurl=file:///root/yum
gpgcheck=0
enabled=1
```

{% endnocopy %}

编写 `Dockerfile-mariadb`：

{% nocopy %}

```dockerfile
# 指定基础镜像
FROM centos:centos7.9.2009
# 维护者信息
MAINTAINER Chinaskills
# 清理默认yum源
RUN rm -rfv /etc/yum.repos.d/*
# 拷贝本地yum源配置
COPY local.repo /etc/yum.repos.d/
# 拷贝yum仓库数据
COPY yum /root/yum
# 设置系统语言环境
ENV LC_ALL en_US.UTF-8
# 安装MariaDB服务端
RUN yum -y install mariadb-server
# 拷贝初始化脚本
COPY mysql_init.sh /opt/
# 执行初始化脚本
RUN bash /opt/mysql_init.sh
# 暴露3306端口
EXPOSE 3306
# 容器启动时运行MariaDB服务
CMD ["mysqld_safe","--user=root"]
```

{% endnocopy %}

##### 构建镜像

执行构建命令：

{% nocopy %}

```bash
# 构建MariaDB镜像，指定镜像名为kod-mysql:v1.0
[root@master KodExplorer]# docker build -t kod-mysql:v1.0 -f Dockerfile-mariadb .
```

{% endnocopy %}

#### 容器化部署 Redis

##### 编写构建文件

编写 `Dockerfile-redis`，在安装后修改配置文件以允许远程连接并关闭保护模式：

{% nocopy %}

```dockerfile
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

##### 构建镜像

执行构建命令：

{% nocopy %}

```bash
# 构建Redis镜像，指定镜像名为kod-redis:v1.0
[root@master KodExplorer]# docker build -t kod-redis:v1.0 -f Dockerfile-redis .
```

{% endnocopy %}

#### 容器化部署 PHP

Explorer 的核心运行环境需要 PHP 支持。

##### 编写构建文件

编写 `Dockerfile-php`，安装 httpd 和 php 相关扩展，并部署代码包：

{% nocopy %}

```dockerfile
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
# 安装Apache、PHP及相关扩展
RUN yum install httpd php php-cli unzip php-gd php-mbstring -y
# 设置工作目录
WORKDIR /var/www/html
# 拷贝KodExplorer源码包
COPY php/kodexplorer4.37.zip .
# 解压源码包
RUN unzip kodexplorer4.37.zip
# 设置目录权限
RUN chmod -R 777 /var/www/html
# 修改Apache配置，设置ServerName
RUN sed -i 's/#ServerName www.example.com:80/ServerName localhost:80/g' /etc/httpd/conf/httpd.conf 
# 暴露80端口
EXPOSE 80
# 容器启动时以前台模式运行Apache服务
CMD ["/usr/sbin/httpd","-D","FOREGROUND"]
```

{% endnocopy %}

##### 构建镜像

执行构建命令：

{% nocopy %}

```bash
# 构建PHP镜像，指定镜像名为kod-php:v1.0
[root@master KodExplorer]# docker build -t kod-php:v1.0 -f Dockerfile-php .
```

{% endnocopy %}

#### 容器化部署 Nginx

Nginx 将作为前端反向代理或静态资源服务器。

##### 编写构建文件

编写 `Dockerfile-nginx`：

{% nocopy %}

```dockerfile
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
# 打印初始化完成信息
RUN /bin/bash -c 'echo init ok'
# 暴露80端口
EXPOSE 80
# 容器启动时以前台模式运行Nginx
CMD ["nginx","-g","daemon off;"]
```

{% endnocopy %}

##### 构建镜像

执行构建命令：

{% nocopy %}

```bash
# 构建Nginx镜像，指定镜像名为kod-nginx:v1.0
[root@master KodExplorer]# docker build -t kod-nginx:v1.0 -f Dockerfile-nginx .
```

{% endnocopy %}

#### 编排部署服务

使用 Docker Compose 对上述构建的服务进行统一编排。

##### 编写 docker-compose.yaml

```yaml
# 创建Docker Compose编排文件
version: '3.2' # Compose文件版本
services:
  nginx: # Nginx前端服务
    container_name: nginx # 容器名称
    image: kod-nginx:v1.0 # 使用的镜像
    volumes: # 挂载卷：持久化数据和日志
      - ./www:/data/www
      - ./nginx/logs:/var/log/nginx
    ports: # 端口映射：宿主机443 -> 容器443
      - "443:443"
    restart: always # 总是重启
    depends_on: # 依赖于php-fpm服务
      - php-fpm
    links: # 链接到php-fpm容器
      - php-fpm
    tty: true # 启用终端

  mysql: # MariaDB数据库服务
    container_name: mysql
    image: kod-mysql:v1.0
    volumes:
      - ./data/mysql:/var/lib/mysql
      - ./mysql/logs:/var/lib/mysql-logs
    ports:
      - "3306:3306"
    restart: always

  redis: # Redis缓存服务
    container_name: redis
    image: kod-redis:v1.0
    ports:
      - "6379:6379"
    volumes:
      - ./data/redis:/data
      - ./redis/redis.conf:/usr/local/etc/redis/redis.conf
    restart: always
    # 启动命令：加载自定义配置文件
    command: redis-server /usr/local/etc/redis/redis.conf

  php-fpm: # PHP核心运行环境
    container_name: php-fpm
    image: kod-php:v1.0
    ports:
      - "8090:80" # 端口映射：宿主机8090 -> 容器80
    links: # 链接到数据库和缓存容器
      - mysql
      - redis
    restart: always
    depends_on:
      - redis
      - mysql
```

##### 部署服务

在后台启动所有服务：

{% nocopy %}

```bash
# 后台启动所有编排的服务
[root@master KodExplorer]# docker-compose up -d
```

{% endnocopy %}

*输出：*

```text
Creating network "kodexplorer_default" with the default driver
Creating redis ... done
Creating mysql ... done
Creating php-fpm ... done
Creating nginx   ... done
```

##### 验证与访问

查看容器运行状态，确保所有服务状态为 `Up`：

{% nocopy %}

```bash
# 查看当前Compose管理的所有容器运行状态
[root@master KodExplorer]# docker-compose ps
```

{% endnocopy %}

*状态检查：*

```text
Name      Command                          State    Ports
--------------------------------------------------------------------------------------------
mysql     mysqld_safe --user=root          Up       0.0.0.0:3306->3306/tcp
nginx     nginx -g daemon off;             Up       0.0.0.0:443->443/tcp, 80/tcp
php-fpm   /usr/sbin/httpd -D FOREGROUND    Up       0.0.0.0:8090->80/tcp
redis     redis-server /usr/local/et...    Up       0.0.0.0:6379->6379/tcp
```

**浏览器访问：**

在浏览器地址栏输入 `http://<节点IP>:8090` (例如 `http://10.24.2.63:8090`) 即可访问 KodExplorer 安装界面。

1. **初始化设置**：设置管理员登录密码。
2. **登录系统**：使用管理员账号登录。
3. **系统预览**：登录成功后，即可进入 KodExplorer 文件管理界面进行操作。
