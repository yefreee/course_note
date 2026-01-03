---
title: 基于k8s构建CICD
date: 
tags:
---

## 实验架构示意

本次实验采用 Master + Node 的基础架构，并部署 Harbor 作为私有镜像仓库。

| 节点角色        | 主机名 | 内存 | 硬盘 | IP地址         | 说明                   |
| :-------------- | :----- | :--- | :--- | :------------- | :--------------------- |
| **Master Node** | master | 12G  | 100G | 192.168.88.100 | 控制节点，兼Harbor仓库 |
| **Worker Node** | node   | 8G   | 100G | 192.168.88.101 | 工作节点               |

---

## 基础环境搭建-Kubernetes集群部署

### 基础环境初始化

在开始安装 K8s 组件前，必须确保所有节点的基础环境配置一致。

1. 在`master`节点中修改IP地址为`192.168.88.100`：

   ```shell
   # 编辑网卡配置文件
   vi /etc/sysconfig/network-scripts/ifcfg-ens33
   ```

   编辑文件如下：

   ```shell
   TYPE=Ethernet
   PROXY_METHOD=none
   BROWSER_ONLY=no
   BOOTPROTO=static        # 配置静态分配 IP
   DEFROUTE=yes
   IPV4_FAILURE_FATAL=no
   IPV6INIT=yes
   IPV6_AUTOCONF=yes
   IPV6_DEFROUTE=yes
   IPV6_FAILURE_FATAL=no
   IPV6_ADDR_GEN_MODE=stable-privacy
   NAME=ens33
   UUID=266c663e-d288-4d54-b100-00741dda6c70
   DEVICE=ens33
   ONBOOT=yes              # 配置开机激活网卡
   IPADDR=192.168.88.100      # 配置 IP 地址
   NETMASK=255.255.255.0   # 配置子网掩码
   GATEWAY=192.168.88.2       # 配置默认网关
   ```

   ```bash
   # 重启网络服务使配置生效
   [root@localhost ~]# systemctl restart network
   ```

2. 用同样的方法修改`node`节点的IP地址为`192.168.88.101`：

   ```shell
   # 编辑网卡配置文件
   vi /etc/sysconfig/network-scripts/ifcfg-ens33
   ```

   编辑文件如下：

   ```shell
   TYPE=Ethernet
   PROXY_METHOD=none
   BROWSER_ONLY=no
   BOOTPROTO=static        # 配置静态分配 IP
   DEFROUTE=yes
   IPV4_FAILURE_FATAL=no
   IPV6INIT=yes
   IPV6_AUTOCONF=yes
   IPV6_DEFROUTE=yes
   IPV6_FAILURE_FATAL=no
   IPV6_ADDR_GEN_MODE=stable-privacy
   NAME=ens33
   UUID=266c663e-d288-4d54-b100-00741dda6c70
   DEVICE=ens33
   ONBOOT=yes              # 配置开机激活网卡
   IPADDR=192.168.88.101      # 配置 IP 地址
   NETMASK=255.255.255.0   # 配置子网掩码
   GATEWAY=192.168.88.2       # 配置默认网关
   ```

   ```bash
   # 重启网络服务使配置生效
   [root@localhost ~]# systemctl restart network
   ```

3. **修改主机名与Hosts映射**

    所有节点都需要配置主机名解析，确保节点间可以通过名称通信。

    **Master 节点执行：**

    ```bash
    # 设置 Master 节点的主机名
    [root@localhost ~]# hostnamectl set-hostname master
    # 重新加载 shell 环境使主机名立即生效
    [root@localhost ~]# exec bash
    
    # 在 hosts 文件中添加集群节点的 IP 与主机名映射，确保节点间可通过名称通信
    [root@master ~]# vi /etc/hosts
    127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
    192.168.88.100 master
    192.168.88.101 node
    ```

    **Node 节点执行：**

    ```bash
    # 设置 Node 节点的主机名
    [root@localhost ~]# hostnamectl set-hostname node
    # 重新加载 shell 环境使主机名立即生效
    [root@localhost ~]# exec bash
    
    # 在 hosts 文件中添加集群节点的 IP 与主机名映射
    [root@node ~]# vi /etc/hosts
    127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
    192.168.88.100 master
    192.168.88.101 node
    ```

4. **关闭防火墙与SELinux**

    为了避免网络规则冲突，需在**所有节点**执行以下操作：

    ```bash
    # 永久关闭 SELinux（修改配置文件，重启后生效）
    [root@master ~]# sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    # 临时关闭 SELinux（立即生效，无需重启）
    [root@master ~]# setenforce 0
    
    # 停止并禁用防火墙服务，防止拦截集群内部通信
    [root@master ~]# systemctl stop firewalld && systemctl disable firewalld
    # 清空所有 iptables 规则、自定义链和计数器
    [root@master ~]# iptables -F && iptables -X && iptables -Z
    # 保存当前的空规则状态
    [root@master ~]# /usr/sbin/iptables-save
    ```

5. **配置本地 Yum 源**

    实验环境使用本地 ISO 镜像作为 Yum 源。将 `Chinaskill_Cloud_PaaS.iso`和`CentOS-7-x86_64-DVD-2009.iso` 上传至 **Master 节点**。

    **Master 节点配置（作为源服务器）：**

    ```bash
    # 挂载 ISO 镜像到 /mnt 和 /media 目录
    [root@master ~]# mount -o loop chinaskills_cloud_paas.iso /mnt/
    [root@master ~]# mount -o loop CentOS-7-x86_64-DVD-2009.iso /media/
    # 将 PaaS 镜像内容递归复制到本地目录 /opt
    [root@master ~]# cp -rfv /mnt/* /opt/
    # 卸载镜像并删除上传的临时文件
    [root@master ~]# umount /mnt/
    [root@master ~]# rm -f chinaskills_cloud_paas.iso
    
    # 备份系统自带的 Yum 源配置文件到 /home
    [root@master ~]# mv /etc/yum.repos.d/CentOS-* /home
    # 创建指向本地目录的 Yum 源配置文件
    [root@master ~]# vi /etc/yum.repos.d/local.repo
    [centos]
    name=centos
    baseurl=file:///media/      # 指向挂载的 CentOS 镜像
    gpgcheck=0
    enabled=1
    [k8s]
    name=k8s
    baseurl=file:///opt/kubernetes-repo # 指向复制到本地的 K8s 仓库
    gpgcheck=0
    enabled=1
    
    # 安装 FTP 服务以便为其他节点提供网络 Yum 源
    [root@master ~]# yum install -y vsftpd
    # 配置 FTP 根目录为系统根目录 /，方便访问镜像内容
    [root@master ~]# echo "anon_root=/" >> /etc/vsftpd/vsftpd.conf
    # 启动并设置 FTP 服务开机自启
    [root@master ~]# systemctl start vsftpd && systemctl enable vsftpd
    ```

    **Node 节点配置（使用 FTP 源）：**

    ```bash
    # 备份原有源配置文件
    [root@node ~]# mv /etc/yum.repos.d/CentOS-* /home
    # 创建指向 Master 节点的 FTP 源配置文件
    [root@node ~]# vi /etc/yum.repos.d/local.repo
    # 通过 FTP 协议访问 Master 节点提供的软件包
    [centos]
    name=centos
    baseurl=ftp://master/media  # 访问 Master 挂载的 CentOS 镜像
    gpgcheck=0
    enabled=1
    [k8s]
    name=k8s
    baseurl=ftp://master/opt/kubernetes-repo # 访问 Master 本地的 K8s 仓库
    gpgcheck=0
    enabled=1
    ```

### 部署 Harbor 私有仓库

Harbor 用于存储我们后续所需的 K8s 系统镜像。

1. **运行harbor部署脚本**

    ```bash
    # 如果前面重启过虚拟机，要重新挂载 ISO 镜像再执行脚本
    [root@master ~]# mount -o loop CentOS-7-x86_64-DVD-2009.iso /media/
    # 进入脚本所在目录
    [root@master ~]# cd /opt
    # 执行 Harbor 自动化安装脚本
    [root@master opt]# ./k8s_harbor_install.sh
    ```

    **Web 界面验证：**
    打开浏览器访问 `http://192.168.88.100`，使用用户名 `admin` 和密码 `Harbor12345` 登录。

2. **推送镜像到 Harbor**

    将本地镜像上传至私有仓库，供集群使用：

    ```bash
    # 执行推送脚本，将本地镜像批量上传至 Harbor 仓库
    [root@master opt]# ./k8s_image_push.sh
    # 根据提示输入仓库地址（192.168.88.100）、用户名(admin)和密码(Harbor12345)
    ```

    刷新下Harbor仓库，可以看到仓库数量。

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766977640.png" alt="1766977649208.png" title="1766977649208.png" />

### 部署 Kubernetes Master 节点

1. **运行master节点部署脚本**

    ```bash
    # 如果前面重启过虚拟机，要重新挂载 ISO 镜像
    [root@master ~]# mount -o loop CentOS-7-x86_64-DVD-2009.iso /media/
    # 进入脚本所在目录
    [root@master ~]# cd /opt
    # 执行 K8s Master 节点自动化安装脚本
    [root@master opt]# ./k8s_master_install.sh
    ```

### Worker Node 节点加入集群

1. **在node节点上获取并执行部署脚本**

    ```bash
    # 从 Master 节点远程拷贝 Node 安装脚本到当前目录
    [root@node ~]# scp root@192.168.88.100:/opt/k8s_node_install.sh ./
    root@192.168.88.100's password: 
    k8s_node_install.sh                                                          100% 3055     4.3MB/s   00:00    
    # 执行 K8s Node 节点自动化安装脚本
    [root@node ~]# ./k8s_node_install.sh 
    ```

2. **验证集群状态**

    回到 **Master 节点** 查看最终集群状态：

    ```bash
    # 在 Master 节点查看所有节点状态，确认 STATUS 为 Ready，表示集群部署成功
    [root@master ~]# kubectl get nodes
    NAME    STATUS   ROLES    AGE   VERSION
    master  Ready    master   56m   v1.18.1
    node    Ready    <none>   60s   v1.18.1
    ```

---

## 案例目标

* 了解 Jenkins 的离线安装与插件配置步骤。
* 掌握 GitLab 代码仓库的使用与项目管理。
* 掌握 CI/CD 流水线（Pipeline）的配置方法。
* 实现在 Kubernetes 环境下从代码提交到自动部署的全流程。

## 理论基础

**CI/CD** 是现代软件开发的核心实践：

* **持续集成 (CI)**：开发人员频繁地将代码合并到主干，通过自动化构建和测试及早发现问题。
* **持续部署 (CD)**：在集成通过后，自动将应用部署到目标环境（如 Kubernetes 集群）。
* **流水线 (Pipeline)**：将构建、测试、部署等步骤串联起来的自动化流程。

## 案例分析

### 节点规划

本实战案例的 CI/CD 环境规划如下：

| IP 地址 | 主机名 | 角色 |
| :--- | :--- | :--- |
| 192.168.88.100 | master | Master 节点、Harbor 仓库、GitLab、Jenkins |
| 192.168.88.101 | node | Worker 节点 |

### 基础准备

* 已部署双节点 Kubernetes 集群
* 准备好离线安装包 `CICD_Offline.tar`。

## 案例实施

### 安装 Jenkins 环境

#### 基础环境准备

首先检查集群状态，确保环境正常：

```bash
# 查看集群组件健康状态，确认各组件（如 scheduler, controller-manager）运行正常
[root@master ~]# kubectl get cs

# 查看集群节点状态，确保所有节点均为 Ready 状态
[root@master ~]# kubectl get nodes
```

解压离线包并导入 Jenkins 镜像：

```bash
# 解压 CI/CD 离线安装包到 /opt 目录
[root@master ~]# tar -zxvf CICD_Offline.tar -C /opt/

# 导入 Jenkins 镜像到本地 Docker 仓库，供后续容器启动使用
[root@master ~]# cd /opt/
[root@master opt]# docker load -i jenkins.tar
```

#### 部署 Jenkins 容器

使用 Docker Compose 进行编排部署：

```bash
# 创建并进入 Jenkins 工作目录
[root@master ~]# mkdir jenkins && cd jenkins

# 编写 Docker Compose 编排文件
[root@master jenkins]# vi docker-compose.yaml
version: '3.1'
services:
  jenkins:
    image: 'jenkins/jenkins:2.262-centos'
    volumes:
      - /home/jenkins_home:/var/jenkins_home      # 将容器内的 Jenkins 数据持久化到宿主机
      - /var/run/docker.sock:/var/run/docker.sock # 挂载 Docker 套接字，使容器内能调用宿主机 Docker
      - /usr/bin/docker:/usr/bin/docker           # 挂载宿主机 Docker 命令到容器内
      - /usr/bin/kubectl:/usr/local/bin/kubectl   # 挂载 kubectl 工具，使 Jenkins 能操作 K8s
      - /root/.kube:/root/.kube                   # 挂载 K8s 认证配置，提供操作权限
    ports:
      - "8080:8080"                               # 映射 Jenkins Web 访问端口
    expose:
      - "8080"
      - "50000"                                   # 暴露 Agent 连接端口
    privileged: true                              # 开启特权模式，确保容器有足够权限
    user: root                                    # 以 root 用户身份运行容器
    restart: always                               # 设置容器自启动
    container_name: jenkins                       # 指定容器名称

# 使用 Docker Compose 后台启动 Jenkins 服务
[root@master jenkins]# docker-compose -f docker-compose.yaml up -d 

# 查看容器运行状态，确认 Jenkins 已成功启动
[root@master jenkins]# docker-compose ps
```

#### 安装插件与初始化

```bash
# 拷贝离线插件包到 Jenkins 的插件目录
[root@master jenkins]# cp -rfv /opt/plugins/* /home/jenkins_home/plugins/

# 重启 Jenkins 容器使新拷贝的插件生效
[root@master jenkins]# docker restart jenkins

# 获取 Jenkins 初始管理员密码，用于首次登录 Web 界面
[root@master ~]# docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

访问 `http://192.168.88.100:8080`，使用查看到的密码登录，并根据提示创建新用户。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767433525.png" alt="1767433534673.png" title="1767433534673.png" />

退出admin用户登录，使用新创建的用户登录，在“系统配置”中设置 Jenkins URL 为 `http://192.168.88.100:8080`。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767433642.png" alt="1767433651824.png" title="1767433651824.png" />

### 部署 GitLab 服务

GitLab 作为代码托管平台，是流水线的触发源。

#### 启动 GitLab

```bash
# 创建并进入 GitLab 工作目录
[root@master ~]# mkdir ~/gitlab && cd ~/gitlab

# 编写 Docker Compose 编排文件
[root@master gitlab]# vi docker-compose.yaml
version: '3'
services:
  gitlab:
    image: 'gitlab/gitlab-ce:12.9.2-ce.0'
    container_name: gitlab
    restart: always
    hostname: '192.168.88.100'                       # 设置 GitLab 访问的主机名/IP
    privileged: true                              # 开启特权模式
    environment:
      TZ: 'Asia/Shanghai'                         # 设置容器时区为上海
    ports:
      - '81:80'                                   # 将容器 80 端口映射到宿主机 81 端口
      - '443:443'                                 # HTTPS 端口映射
      - '1022:22'                                 # 将容器 SSH 端口映射到宿主机 1022 端口
    volumes:
      - /srv/gitlab/config:/etc/gitlab            # 挂载配置文件目录
      - /srv/gitlab/gitlab/logs:/var/log/gitlab   # 挂载日志目录
      - /srv/gitlab/gitlab/data:/var/opt/gitlab   # 挂载数据目录

# 使用 Docker Compose 后台启动 GitLab 服务
[root@master gitlab]# docker-compose up -d
```

#### 创建项目并推送代码

1. Gitlab启动较慢，启动完成后访问 `http://192.168.88.100:81`，设置 root 密码并登录。
1. 点击“Create a project”，创建名为 `springcloud` 的公开项目。

    <img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767433795.png" alt="1767433804638.png" title="1767433804638.png" />

1. 在 Master 节点推送源代码：

    ```bash
    # 安装 Git 客户端工具
    [root@master ~]# yum install -y git

    # 进入项目源代码目录
    [root@master ~]# cd /opt/springcloud/
    # 配置 Git 全局用户名和邮箱
    [root@master springcloud]# git config --global user.name "administrator"
    [root@master springcloud]# git config --global user.email "admin@example.com"

    # 移除旧的远程仓库关联（如果有）
    [root@master springcloud]# git remote remove origin
    # 添加新的 GitLab 远程仓库地址
    [root@master springcloud]# git remote add origin http://192.168.88.100:81/root/springcloud.git
    # 将所有文件添加到暂存区
    [root@master springcloud]# git add .
    # 提交代码到本地仓库
    [root@master springcloud]# git commit -m "initial commit"
    # 推送代码到远程仓库的 master 分支
    [root@master springcloud]# git push -u origin master
    ```

1. 刷新网页，springcloud项目中文件已经更新了。

    <img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767433880.png" alt="1767433890194.png" title="1767433890194.png" />

### 配置 Jenkins 连接 GitLab

#### GitLab 权限设置

在 GitLab 管理员设置中，点击管理区域的扳手图标，进入 `Settings` -> `Network` -> `Outbound requests`，勾选 `Allow requests to the local network from web hooks and services` 并保存。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767434117.png" alt="1767434127285.png" title="1767434127285.png" />

#### 生成 API Token

点击Gitlab用户头像图标，点击“Settings”，进入 `Access Tokens`，创建一个名为 `jenkins` 的 Token，记录下生成的字符串。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767434184.png" alt="1767434193759.png" title="1767434193759.png" />

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767434201.png" alt="1767434211124.png" title="1767434211124.png" />

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767434224.png" alt="1767434233406.png" title="1767434233406.png" />

#### Jenkins 对接配置

在 Jenkins “系统管理” -> “系统配置” 中添加 GitLab 服务器信息，取消勾选“Enable authentication for '/project' end-point”，并使用上一步生成的 Token 创建凭据。点击 `Test Connection` 确认连接成功。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767434293.png" alt="1767434303186.png" title="1767434303186.png" />

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767434330.png" alt="1767434339601.png" title="1767434339601.png" />

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767434378.png" alt="1767434387638.png" title="1767434387638.png" />

### 配置 Maven 构建环境

#### 在 Jenkins 容器内安装 Maven

```bash
# 拷贝 Maven 安装包到 Jenkins 容器挂载的数据目录
[root@master ~]# cp -rf /opt/apache-maven-3.6.3-bin.tar.gz /home/jenkins_home/

# 进入 Jenkins 容器内部进行配置
[root@master ~]# docker exec -it jenkins bash

# 在容器内解压 Maven 安装包
[root@344d4fa5b8ea /]# tar -zxvf /var/jenkins_home/apache-maven-3.6.3-bin.tar.gz -C .
# 移动并重命名 Maven 目录
[root@344d4fa5b8ea /]# mv apache-maven-3.6.3/ /usr/local/maven
# 配置系统环境变量
[root@344d4fa5b8ea /]# vi /etc/profile
export M2_HOME=/usr/local/maven
export PATH=$PATH:$M2_HOME/bin

# 文件最后添加，确保环境变量在非交互式 shell 中也能生效
[root@344d4fa5b8ea /]# vi /root/.bashrc
source /etc/profile

# 验证 Maven 是否安装成功并查看版本

# 退出容器使环境变量生效后重新进入容器并执行：

[root@344d4fa5b8ea /]# exit
[root@master ~]# docker exec -it jenkins bash
[root@344d4fa5b8ea /]# mvn -v
```

#### Jenkins 全局工具配置

登录Jenkins首页，点击“系统管理”、进入“全局工具配置”，新增 Maven，指定名称为 `maven`，安装路径为 `/usr/local/maven`。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767444833.png" alt="1767444842698.png" title="1767444842698.png" />

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767444817.png" alt="1767444827435.png" title="1767444827435.png" />

### 配置 CI/CD 流水线

#### 新建流水线任务

登录Jenkins首页，点击左侧导航栏“新建任务”。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767444849.png" alt="1767444858815.png" title="1767444858815.png" />

新建名为 `springcloud` 的流水线任务，在“构建触发器”中勾选 `Build when a change is pushed to GitLab`，并记录 Webhook URL。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767444914.png" alt="1767444923972.png" title="1767444923972.png" />

#### 编写 Pipeline 脚本

配置流水线：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445021.png" alt="1767445031238.png" title="1767445031238.png" />

点击“流水线语法”，如图所示，示例步骤选择“git：Git”，将springcloud项目地址填入仓库URL。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445069.png" alt="1767445079425.png" title="1767445079425.png" />

点击“添加”→“jenkins”添加凭据，如图所示。类型选择“Username with password”，用户名和密码为Gitlab仓库的用户名和密码。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445112.png" alt="1767445122565.png" title="1767445122565.png" />

添加凭据后选择凭据：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445133.png" alt="1767445144545.png" title="1767445144545.png" />

点击“生成流水线脚本”，记录生成的值：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445188.png" alt="1767445198119.png" title="1767445198119.png" />

在流水线配置中输入以下脚本，其中**`gitlab-auth-id`**为上图生成的凭据ID：

```groovy
node{
    stage('git clone'){
        // 阶段 1：从 GitLab 仓库拉取项目源代码
        // credentialsId 需与 Jenkins 中创建的凭据 ID 一致
        git credentialsId: 'gitlab-auth-id', url: 'http://192.168.88.100:81/root/springcloud.git'
    }
    stage('maven build'){
        // 阶段 2：使用 Maven 进行项目编译打包
        // -DskipTests 跳过单元测试以加快构建速度
        sh '/usr/local/maven/bin/mvn package -DskipTests -f /var/jenkins_home/workspace/springcloud'
    }
    stage('image build'){
        // 阶段 3：构建 Docker 镜像
        // $BUILD_ID 是 Jenkins 内置变量，用于区分不同批次的镜像版本
        sh '''
              docker build -t 192.168.88.100/springcloud/gateway:$BUILD_ID -f /var/jenkins_home/workspace/springcloud/gateway/Dockerfile /var/jenkins_home/workspace/springcloud/gateway
              docker build -t 192.168.88.100/springcloud/config:$BUILD_ID -f /var/jenkins_home/workspace/springcloud/config/Dockerfile /var/jenkins_home/workspace/springcloud/config
           '''
    }
    stage('test'){
        // 阶段 4：运行临时容器验证镜像是否能正常启动
        sh '''
              docker run -itd --name gateway 192.168.88.100/springcloud/gateway:$BUILD_ID
              # 检查容器是否处于运行状态 (Up)
              docker ps -a | grep springcloud | grep Up
              if [ $? -eq 0 ]; then
                  echo "Success!"
                  docker rm -f gateway
              else
                  echo "Failed!"
                  docker rm -f gateway
                  exit 1
              fi
           '''
    }
    stage('upload registry'){
        // 阶段 5：登录私有仓库并将镜像推送至 Harbor
        sh '''
              docker login 192.168.88.100 -u=admin -p=Harbor12345
              docker push 192.168.88.100/springcloud/gateway:$BUILD_ID
              docker push 192.168.88.100/springcloud/config:$BUILD_ID
           '''
    }
    stage('deploy K8s'){
        // 阶段 6：更新 YAML 文件中的镜像版本并部署到 Kubernetes 集群
        sh '''
              # 使用 sed 替换 YAML 文件中的镜像地址为最新构建的镜像
              sed -i "s|sqshq/piggymetrics-gateway|192.168.88.100/springcloud/gateway:$BUILD_ID|g" yaml/deployment/gateway-deployment.yaml
              sed -i "s|sqshq/piggymetrics-config|192.168.88.100/springcloud/config:$BUILD_ID|g" yaml/deployment/config-deployment.yaml
              # 创建命名空间（如果不存在）
              kubectl create ns springcloud || true
              # 应用部署配置和服务配置
              kubectl apply -f yaml/deployment/ --kubeconfig=/root/.kube/config
              kubectl apply -f yaml/svc/ --kubeconfig=/root/.kube/config
           '''
    }
}
```

配置完成后点击应用：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445377.png" alt="1767445387316.png" title="1767445387316.png" />

开启Jenkins匿名访问:登录Jenkins首页，点击“系统管理”→“全局安全配置”，配置授权策略允许匿名用户访问

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445487.png" alt="1767445496684.png" title="1767445496684.png" />

### 触发与验证

#### 配置 Webhook

登录 GitLab 进入springcloud项目，点击左侧导航栏“Settings”→“Webhooks”，添加 Webhook，填入 Jenkins 记录的 URL，触发源选择 `Push events`。

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445576.png" alt="1767445585846.png" title="1767445585846.png" />

点击“Add webhook”添加webhook：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445607.png" alt="1767445617341.png" title="1767445617341.png" />

点击“Test”→“Push events”进行测试，结果返回HTTP 200则表明Webhook配置成功：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445631.png" alt="1767445641006.png" title="1767445641006.png" />

#### 创建Harbor项目

登录Harbor，新建项目springcloud，访问级别设置为公开，进入项目查看镜像列表，此时为空，无任何镜像：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767445776.png" alt="1767445786115.png" title="1767445786115.png" />

#### 触发自动构建

```bash
# 拷贝本地 Maven 依赖仓库到容器内，避免重复下载，加速构建过程
[root@master ~]# docker cp /opt/repository/ jenkins:/root/.m2/
# 重启 Jenkins 使配置生效
[root@master ~]# docker restart jenkins

# 在 Master 节点提交代码，触发 GitLab Webhook 自动调用 Jenkins 流水线
[root@master springcloud]# git add .
[root@master springcloud]# git commit -m "trigger build"
[root@master springcloud]# git push -u origin master
```

#### 结果检查

#### Jenkins查看

登录Jenkins，可以看到springcloud项目已经开始构建：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767446149.png" alt="1767446156725.png" title="1767446156725.png" />

点击项目名称查看流水线阶段视图：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767446169.png" alt="1767446178974.png" title="1767446178974.png" />

> 查看阶段视图（Stage View），确认所有阶段均为绿色通过。

#### Harbor仓库查看

进入Harbor仓库springcloud项目查看镜像列表，可以看到已自动上传了一个gateway镜像:：

<img src="https://lsky.taojie.fun:52222/i/2026/01/03/2026-01-03-1767449358.png" alt="1767449366328.png" title="1767449366328.png" />

#### Kubernetes查看

```bash
# 查看 springcloud 命名空间下的 Pod 运行状态
[root@master ~]# kubectl -n springcloud get pods

# 查看 Service 暴露的端口信息
[root@master ~]# kubectl -n springcloud get svc
```

访问 `http://192.168.88.100:30010` 验证业务是否正常运行。

---
**总结**：本案例实现了从代码提交到 K8s 部署的全自动化流程，是企业级 CI/CD 的典型应用场景。
