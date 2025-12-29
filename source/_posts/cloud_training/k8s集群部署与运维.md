---
title: k8s集群部署与运维
date: 
tags:
---

## Kubernetes(K8s)简介

Kubernetes（简称 K8s）是一个开源的容器编排引擎，用于自动部署、扩展和管理容器化应用程序。如果说 Docker 是将应用程序打包成集装箱（容器），那么 Kubernetes 就是码头的调度系统，负责管理这些集装箱的运输、堆叠和分发。

在云原生时代，Kubernetes 已成为管理大规模容器集群的事实标准。

### Kubernetes核心特点

* **自动装箱**：根据资源需求（CPU、内存）自动将容器调度到合适的节点上运行，无需人工干预。
* **自我修复**：当容器失败、节点故障时，K8s 会自动重启或重新调度容器，保证服务不中断。
* **服务发现与负载均衡**：无需修改应用程序，即可通过 Service 概念实现内部服务的相互访问和负载均衡。
* **存储编排**：自动挂载本地存储、网络存储（如 NFS、Ceph）或公有云存储。

### Kubernetes基本概念

* **Master 节点**：集群的大脑，负责管理整个集群的控制平面。包含 API Server、Scheduler（调度器）、Controller Manager（控制器）等组件。
* **Node 节点**：集群的工作节点，负责实际运行容器。包含 Kubelet、Kube-proxy 和容器运行时（如 Docker）。
* **Pod**：Kubernetes 调度的最小单元。一个 Pod 可以包含一个或多个共享网络和存储的容器。
* **Service**：定义一组 Pod 的逻辑集合和访问策略，提供稳定的访问入口（IP和端口）。
* **Harbor**：企业级私有镜像仓库，用于存储和分发 Docker 镜像。

### 实验架构示意

本次实验采用 Master + Node 的基础架构，并部署 Harbor 作为私有镜像仓库。

| 节点角色 | 主机名 | 内存 | 硬盘 | IP地址 | 说明 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Master Node** | master | 12G | 100G | 10.18.4.10 | 控制节点，兼Harbor仓库 |
| **Worker Node** | node | 8G | 100G | 10.18.4.11 | 工作节点 |

---

## Kubernetes集群部署实验

### 基础环境初始化

在开始安装 K8s 组件前，必须确保所有节点的基础环境配置一致。

1. 在`master`节点中修改IP地址为`192.168.88.100`：

   ```shell
   vi /etc/sysconfig/network-scripts/ifcfg-ens33
   ```

   编辑文件如下：

   ```shell
   TYPE=Ethernet
   PROXY_METHOD=none
   BROWSER_ONLY=no
   BOOTPROTO=static        # 1. 配置静态分配ip
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
   ONBOOT=yes              # 2. 配置开机激活网卡
   IPADDR=192.168.88.100   # 3. 配置ip地址
   NETMASK=255.255.255.0   # 4. 配置子网掩码
   GATEWAY=192.168.88.2    # 5. 配置默认网关
   ```

   ```bash
   # 重启网络后使用SecureCRT连接远程环境
   [root@localhost ~]# systemctl restart network
   ```

2. 用同样的方法修改`node`节点的IP地址为`192.168.88.101`：

   ```shell
   vi /etc/sysconfig/network-scripts/ifcfg-ens33
   ```

   编辑文件如下：

   ```shell
   TYPE=Ethernet
   PROXY_METHOD=none
   BROWSER_ONLY=no
   BOOTPROTO=static        # 1. 配置静态分配ip
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
   ONBOOT=yes              # 2. 配置开机激活网卡
   IPADDR=192.168.88.101   # 3. 配置ip地址
   NETMASK=255.255.255.0   # 4. 配置子网掩码
   GATEWAY=192.168.88.2    # 5. 配置默认网关
   ```

   ```bash
   # 重启网络后使用SecureCRT连接远程环境
   [root@localhost ~]# systemctl restart network
   ```

3. **修改主机名与Hosts映射**

    所有节点都需要配置主机名解析，确保节点间可以通过名称通信。

    **Master 节点执行：**
    {% nocopy %}

    ```bash
    # 设置 Master 节点的主机名
    [root@localhost ~]# hostnamectl set-hostname master
    [root@localhost ~]# exec bash
    
    # 在 hosts 文件中添加集群节点的 IP 与主机名映射
    [root@master ~]# vi /etc/hosts
    127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
    192.168.88.100 master
    192.168.88.101 node
    ```

    {% endnocopy %}

    **Node 节点执行：**
    {% nocopy %}

    ```bash
    # 设置 Node 节点的主机名
    [root@localhost ~]# hostnamectl set-hostname node
    # 重新加载 shell 环境使主机名生效
    [root@localhost ~]# exec bash
    
    # 在 hosts 文件中添加集群节点的 IP 与主机名映射
    [root@node ~]# vi /etc/hosts
    127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
    192.168.88.100 master
    192.168.88.101 node
    ```

    {% endnocopy %}

4. **关闭防火墙与SELinux**

    为了避免网络规则冲突，需在**所有节点**执行以下操作：

    {% nocopy %}

    ```bash
    # 永久关闭 SELinux（修改配置文件）
    [root@master ~]# sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    # 临时关闭 SELinux（立即生效）
    [root@master ~]# setenforce 0
    
    # 停止并禁用防火墙服务
    [root@master ~]# systemctl stop firewalld && systemctl disable firewalld
    # 清空所有 iptables 规则、链和计数器
    [root@master ~]# iptables -F && iptables -X && iptables -Z
    # 保存当前的 iptables 状态
    [root@master ~]# /usr/sbin/iptables-save
    ```

    {% endnocopy %}

5. **配置本地 Yum 源**

    实验环境使用本地 ISO 镜像作为 Yum 源。将 `Chinaskill_Cloud_PaaS.iso`和`CentOS-7-x86_64-DVD-2009.iso` 上传至 **Master 节点**。

    **Master 节点配置（作为源服务器）：**
    {% nocopy %}

    ```bash
    # 挂载 ISO 镜像到 /mnt和/media
    [root@master ~]# mount -o loop chinaskills_cloud_paas.iso /mnt/
    [root@master ~]# mount -o loop CentOS-7-x86_64-DVD-2009.iso /media/
    # 将镜像内容复制到本地目录 /opt
    [root@master ~]# cp -rfv /mnt/* /opt/
    # 卸载镜像
    [root@master ~]# umount /mnt/
    [root@master ~]# rm -f chinaskills_cloud_paas.iso
    
    # 备份系统自带的 Yum 源配置文件
    [root@master ~]# mv /etc/yum.repos.d/CentOS-* /home
    # 创建指向本地目录的 Yum 源配置文件
    [root@master ~]# vi /etc/yum.repos.d/local.repo
    [centos]
    name=centos
    baseurl=file:///media/
    gpgcheck=0
    enabled=1
    [k8s]
    name=k8s
    baseurl=file:///opt/kubernetes-repo
    gpgcheck=0
    enabled=1
    
    # 安装 FTP 服务以便为其他节点提供 Yum 源
    [root@master ~]# yum install -y vsftpd
    # 配置 FTP 根目录为 /
    [root@master ~]# echo "anon_root=/" >> /etc/vsftpd/vsftpd.conf
    # 启动并设置 FTP 服务开机自启
    [root@master ~]# systemctl start vsftpd && systemctl enable vsftpd
    ```

    {% endnocopy %}

    **Node 节点配置（使用 FTP 源）：**
    {% nocopy %}

    ```bash
    # 备份原有源
    [root@node ~]# mv /etc/yum.repos.d/CentOS-* /home
    # 创建指向 Master 节点的 FTP 源
    [root@node ~]# vi /etc/yum.repos.d/local.repo
    # 通过 FTP 协议访问 Master 节点提供的软件包
    [centos]
    name=centos
    baseurl=ftp://master/media
    gpgcheck=0
    enabled=1
    [k8s]
    name=k8s
    baseurl=ftp://master/opt/kubernetes-repo
    gpgcheck=0
    enabled=1
    ```

    {% endnocopy %}

6. **释放虚拟机资源**

    `master`节点关机，右键属性、硬盘、压缩，然后重新开机：

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766974382.png" alt="1766974391928.png" title="1766974391928.png" />

### 部署 Harbor 私有仓库

Harbor 用于存储我们后续所需的 K8s 系统镜像。

1. **运行harbor部署脚本**

    ```bash
    [root@master ~]# cd /opt
    [root@master opt]# ./k8s_harbor_install.sh
    ```

    **Web 界面验证：**
    打开浏览器访问 `http://192.168.88.100`，使用用户名 `admin` 和密码 `Harbor12345` 登录。

2. **推送镜像到 Harbor**

    将本地镜像上传至私有仓库，供集群使用：

    {% nocopy %}

    ```bash
    # 执行推送脚本，将本地镜像批量上传至 Harbor
    [root@master opt]# ./k8s_image_push.sh
    # 根据提示输入仓库地址、用户名(admin)和密码(Harbor12345)
    ```

    {% endnocopy %}

    刷新下Harbor仓库，可以看到仓库数量。

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766977640.png" alt="1766977649208.png" title="1766977649208.png" />

3. **再次释放虚拟机资源**

    删除多余的镜像原文件：

    ```bash
    [root@master opt]# rm -rf images
    ```

    `master`节点关机，右键属性、硬盘、压缩，然后重新开机：

### 部署 Kubernetes Master 节点

1. **运行master节点部署脚本**

    ```bash
    [root@master ~]# cd /opt
    [root@master opt]# ./k8s_master_install.sh
    ```

    **Web 界面验证：**
    打开浏览器访问 `http://192.168.88.100`，使用用户名 `admin` 和密码 `Harbor12345` 登录。

### Worker Node 节点加入集群

1. **在node节点上获取并执行部署脚本**

    ```bash
    [root@node ~]# scp root@192.168.88.100:/opt/k8s_node_install.sh ./
    root@192.168.88.100's password: 
    k8s_node_install.sh                                                          100% 3055     4.3MB/s   00:00    
    [root@node ~]# ./k8s_node_install.sh 
    ```

2. **验证集群状态**

    回到 **Master 节点** 查看最终集群状态：

    {% nocopy %}

    ```bash
    # 在 Master 节点查看所有节点状态，确认 STATUS 为 Ready
    [root@master ~]# kubectl get nodes
    NAME    STATUS   ROLES    AGE   VERSION
    master  Ready    master   56m   v1.18.1
    node    Ready    <none>   60s   v1.18.1
    ```

    {% endnocopy %}

## WordPress 应用部署

1. **部署 MySQL 数据库（持久化方式）**

    WordPress 的博客内容存储在数据库中，为了保证数据持久化，同样采用宿主机本地映射的方式。

    在 **Node 节点** 创建 MySQL 数据目录：

    ```bash
    [root@node ~]# mkdir -p /opt/mysql/data
    [root@node ~]# chmod 777 /opt/mysql/data
    ```

    在 **Master 节点** 编写部署文件 `mysql-persistent.yaml`：

    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: mysql
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: mysql
      template:
        metadata:
          labels:
            app: mysql
        spec:
          # 强制调度到 node 节点，确保 hostPath 挂载正确
          nodeSelector:
            kubernetes.io/hostname: node
          containers:
          - name: mysql
            image: 192.168.88.100/library/mysql:5.6
            env:
            - name: MYSQL_ROOT_PASSWORD
              value: "root"
            - name: MYSQL_DATABASE
              value: "wordpress"
            ports:
            - containerPort: 3306 # MySQL 默认端口
            volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql # 容器内数据库存储路径
          volumes:
          - name: mysql-data
            hostPath:
              path: /opt/mysql/data # 宿主机挂载路径
              type: DirectoryOrCreate
    ```

    运行应用：

    {% nocopy %}

    ```bash
    # 使用 apply 命令根据 YAML 文件创建或更新资源
    [root@master ~]# kubectl apply -f mysql-persistent.yaml
    deployment.apps/mysql created
    ```

    {% endnocopy %}

    验证 MySQL Pod 状态：

    {% nocopy %}

    ```bash
    # 查看 Pod 状态，确认 STATUS 为 Running
    [root@master ~]# kubectl get pods
    NAME                     READY   STATUS    RESTARTS   AGE
    mysql-7894b95f8-x2jkl    1/1     Running   0          15s
    ```

    {% endnocopy %}

    暴露 MySQL 服务，供 WordPress 内部连接：

    {% nocopy %}

    ```bash
    # 使用 expose 命令创建 Service，默认类型为 ClusterIP
    [root@master ~]# kubectl expose deployment mysql --port=3306
    service/mysql exposed
    ```

    {% endnocopy %}

    查看 MySQL 服务 IP：

    {% nocopy %}

    ```bash
    # 查看 Service 列表，获取 mysql 的 CLUSTER-IP
    [root@master ~]# kubectl get svc mysql
    NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
    mysql   ClusterIP   10.108.45.201   <none>        3306/TCP   10s
    ```

    {% endnocopy %}

2. **部署 WordPress 应用（持久化方式）**

    为了保证 WordPress 数据不丢失，采用宿主机本地映射（hostPath）的方式进行持久化部署。

    首先在 **Node 节点**（Pod 运行的节点）创建挂载目录：

    ```bash
    [root@node ~]# mkdir -p /opt/wordpress/data
    [root@node ~]# chmod 777 /opt/wordpress/data
    ```

    在 **Master 节点** 编写部署文件 `wordpress-persistent.yaml`：

    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: wordpress
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: wordpress
      template:
        metadata:
          labels:
            app: wordpress
        spec:
          # 强制调度到 node 节点
          nodeSelector:
            kubernetes.io/hostname: node
          containers:
          - name: wordpress
            image: 192.168.88.100/library/wordpress:latest
            ports:
            - containerPort: 80 # WordPress 默认端口
            volumeMounts:
            - name: wordpress-data
              mountPath: /var/www/html # 容器内网页根目录
          volumes:
          - name: wordpress-data
            hostPath:
              path: /opt/wordpress/data # 宿主机挂载路径
              type: DirectoryOrCreate
    ```

    运行应用：

    {% nocopy %}

    ```bash
    # 应用 WordPress 部署配置
    [root@master ~]# kubectl apply -f wordpress-persistent.yaml
    deployment.apps/wordpress created
    ```

    {% endnocopy %}

    查看 Pods 状态：

    {% nocopy %}

    ```bash
    # 确认 WordPress Pod 正常运行
    [root@master ~]# kubectl get pods
    NAME                         READY   STATUS    RESTARTS   AGE
    wordpress-68d7d6d678-4r2tx   1/1     Running   0          30s
    ```

    {% endnocopy %}

    使用 `NodePort` 方式暴露 WordPress 服务，以便从外部访问：

    {% nocopy %}

    ```bash
    # 暴露服务并指定类型为 NodePort，使外部可以通过宿主机 IP 访问
    [root@master ~]# kubectl expose deployment wordpress --port=80 --type=NodePort
    service/wordpress exposed
    ```

    {% endnocopy %}

    查看服务映射的端口：

    {% nocopy %}

    ```bash
    # 获取 NodePort 映射的随机端口（如 32123）
    [root@master ~]# kubectl get svc wordpress
    NAME        TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
    wordpress   NodePort   10.105.15.160   <none>        80:32123/TCP   5s
    ```

    {% endnocopy %}

    **访问测试：**
    打开浏览器访问 `http://192.168.88.100:32123`（端口以实际获取的为准），即可看到 WordPress 安装页面。

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766995999.png" alt="1766996008564.png" title="1766996008564.png" />

    在 WordPress 安装界面中，数据库主机填写 `mysql` 或其 `CLUSTER-IP`ip地址 即可完成关联。

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766995980.png" alt="1766995988110.png" title="1766995988110.png" />

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766996103.png" alt="1766996111943.png" title="1766996111943.png" />

    在仪表盘上创建第一篇博客：

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766996248.png" alt="1766996257000.png" title="1766996257000.png" />

    简单编辑博客后右上角发布,然后打开博客链接：

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766996219.png" alt="1766996227934.png" title="1766996227934.png" />

    <img src="https://lsky.taojie.fun:52222/i/2025/12/29/2025-12-29-1766996314.png" alt="1766996323726.png" title="1766996323726.png" />

3. **WordPress持久化验证**

    * 删除wordpress和mysql两个deployment，验证数据是否持久化:

        ```bash
        [root@master ~]# kubectl delete deployment wordpress mysql
        deployment.apps "wordpress" deleted
        deployment.apps "mysql" deleted
        ```

    * 重新创建两个deployment:

        ```bash
        [root@master ~]# kubectl apply -f mysq-persistent.yaml
        deployment.apps/mysql created
        [root@master ~]# kubectl apply -f wordpress-persistent.yaml
        deployment.apps/wordpress created
        ```

    **重新打开或者刷新博客网页验证，此时能看到即使deployment已经重建也能看到之前创建的博客，说明数据持久化成功。**

---

## Kubernetes 应用运维：健康检查

在生产环境中，我们需要确保应用不仅在运行，而且是健康的。Kubernetes 提供了探针（Probes）机制来实现这一目标。

### 为 WordPress 配置健康检查

我们将修改 `wordpress-persistent.yaml`，为其添加 `livenessProbe`（存活探针）和 `readinessProbe`（就绪探针）。为了演示自动修复效果，我们使用非持久化路径 `/tmp/healthy` 作为探测对象。

* **Liveness Probe**：用于判断容器是否存活。如果探测失败，kubelet 会杀掉容器并根据重启策略重启。
* **Readiness Probe**：用于判断容器是否准备好接收流量。如果探测失败，端点控制器将从服务的所有 Pod 端点中删除该 Pod 的 IP 地址。

修改后的 `wordpress-persistent.yaml` 如下：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  replicas: 2  # 部署 2 个副本以演示切换
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      # 强制调度到 node 节点
      nodeSelector:
        kubernetes.io/hostname: node
      containers:
      - name: wordpress
        image: 192.168.88.100/library/wordpress:latest
        ports:
        - containerPort: 80
        # 启动后自动创建一个临时健康文件（非持久化路径）
        # lifecycle 钩子用于在容器生命周期的特定阶段执行操作
        lifecycle:
          postStart:
            exec:
              command: ["/bin/sh", "-c", "touch /tmp/healthy"]
        # 存活探针：检查临时文件是否存在
        # 如果文件不存在，K8s 会认为容器不健康并重启它
        livenessProbe:
          exec:
            command: ["ls", "/tmp/healthy"]
          initialDelaySeconds: 10 # 容器启动后等待 10 秒开始探测
          periodSeconds: 5        # 每隔 5 秒探测一次
        # 就绪探针：检查临时文件是否存在
        # 如果文件不存在，K8s 会停止向该 Pod 发送流量
        readinessProbe:
          exec:
            command: ["ls", "/tmp/healthy"]
          initialDelaySeconds: 5  # 容器启动后等待 5 秒开始探测
          periodSeconds: 5        # 每隔 5 秒探测一次
        volumeMounts:
        - name: wordpress-data
          mountPath: /var/www/html
      volumes:
      - name: wordpress-data
        hostPath:
          path: /opt/wordpress/data
          type: DirectoryOrCreate
```

### 模拟故障与自动切换验证

1. **应用配置**：

    ```bash
    # 应用包含探针配置的 YAML 文件
    [root@master ~]# kubectl apply -f wordpress-persistent.yaml
    deployment.apps/wordpress configured
    ```

2. **等待20秒后确认双副本运行**：

    ```bash
    # 查看 Pod 列表，确认两个副本都处于 Running 状态
    [root@master ~]# kubectl get pods -l app=wordpress
    NAME                         READY   STATUS    RESTARTS   AGE
    wordpress-5f5977b7-abc12    1/1     Running   0          1m
    wordpress-5f5977b7-def34    1/1     Running   0          1m
    ```

3. **模拟单点故障**：
    删除**其中一个** Pod 里的临时文件（例如 `abc12`）：

    ```bash
    # 使用 exec 命令在容器内执行删除操作，模拟应用故障
    [root@master ~]# kubectl exec wordpress-5f5977b7-abc12 -- rm -rf /tmp/healthy
    ```

4. **验证流量切换（Readiness）**：
    约 5 秒后，该 Pod 的 `READY` 状态变为 `0/1`。

    ```bash
    [root@master ~]# kubectl get pods -l app=wordpress
    NAME                         READY   STATUS    RESTARTS   AGE
    wordpress-5f5977b7-abc12    0/1     Running   0          2m
    wordpress-5f5977b7-def34    1/1     Running   0          2m
    ```

    **结果**：此时访问博客，流量会全部由健康的 `def34` 接收。由于 `def34` 的文件没被删，它依然保持在线，服务不会中断。

5. **验证自动修复（Liveness）**：
    再过约 10 秒，Liveness 探针发现文件缺失，触发容器重启。

    ```bash
    [root@master ~]# kubectl get pods -l app=wordpress
    NAME                         READY   STATUS    RESTARTS   AGE
    wordpress-5f5977b7-abc12    1/1     Running   1          3m
    wordpress-5f5977b7-def34    1/1     Running   0          3m
    ```

    **结果**：容器重启后，`postStart` 钩子再次执行并重新创建了 `/tmp/healthy`。Pod 自动恢复为 `1/1 READY`，重新加入负载均衡。

### 实验总结

* **Readiness Probe**：实现了“**故障隔离**”。当一个 Pod 出问题时，迅速将其从服务列表中剔除，由另一个 Pod 顶上。
* **Liveness Probe**：实现了“**自我修复**”。通过重启容器，配合 `postStart` 或镜像初始环境，让 Pod 回到健康状态。
* **非持久化路径的意义**：在实验中，使用非持久化路径（如 `/tmp`）可以确保重启后的容器是“干净”的，从而能够真正演示出从故障到自动恢复的完整闭环。
