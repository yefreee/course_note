---
title: k8s集群部署
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

1. **修改主机名与Hosts映射**

    所有节点都需要配置主机名解析，确保节点间可以通过名称通信。

    **Master 节点执行：**
    {% nocopy %}

    ```bash
    # 设置 Master 节点的主机名
    [root@localhost ~]# hostnamectl set-hostname master
    
    # 在 hosts 文件中添加集群节点的 IP 与主机名映射
    [root@master ~]# cat >> /etc/hosts <<EOF
    10.18.4.10 master
    10.18.4.11 node
    EOF
    ```

    {% endnocopy %}

    **Node 节点执行：**
    {% nocopy %}

    ```bash
    # 设置 Node 节点的主机名
    [root@localhost ~]# hostnamectl set-hostname node
    
    # 在 hosts 文件中添加集群节点的 IP 与主机名映射
    [root@node ~]# cat >> /etc/hosts <<EOF
    10.18.4.10 master
    10.18.4.11 node
    EOF
    ```

    {% endnocopy %}

2. **关闭防火墙与SELinux**

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

3. **配置本地 Yum 源**

    实验环境使用本地 ISO 镜像作为 Yum 源。将 `Chinaskill_Cloud_PaaS.iso` 上传至 **Master 节点**。

    **Master 节点配置（作为源服务器）：**
    {% nocopy %}

    ```bash
    # 挂载 ISO 镜像到 /mnt
    [root@master ~]# mount -o loop chinaskills_cloud_paas.iso /mnt/
    # 将镜像内容复制到本地目录 /opt
    [root@master ~]# cp -rfv /mnt/* /opt/
    # 卸载镜像
    [root@master ~]# umount /mnt/
    
    # 备份系统自带的 Yum 源配置文件
    [root@master ~]# mv /etc/yum.repos.d/CentOS-* /home
    # 创建指向本地目录的 Yum 源配置文件
    [root@master ~]# cat << EOF >/etc/yum.repos.d/local.repo
    [k8s]
    name=k8s
    baseurl=file:///opt/kubernetes-repo
    gpgcheck=0
    enabled=1
    EOF
    
    # 安装 FTP 服务以便为其他节点提供 Yum 源
    [root@master ~]# yum install -y vsftpd
    # 配置 FTP 根目录为 /opt
    [root@master ~]# echo "anon_root=/opt" >> /etc/vsftpd/vsftpd.conf
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
    [root@node ~]# cat << EOF >/etc/yum.repos.d/local.repo
    [k8s]
    name=k8s
    baseurl=ftp://master/kubernetes-repo
    gpgcheck=0
    enabled=1
    EOF
    ```

    {% endnocopy %}

### 部署 Harbor 私有仓库

Harbor 用于存储我们后续所需的 K8s 系统镜像。

1. **安装 Docker 环境**

    在 **所有节点** 安装 Docker：

    {% nocopy %}

    ```bash
    # 安装 Docker 所需的依赖包
    [root@master ~]# yum install -y yum-utils device-mapper-persistent-data lvm2
    # 安装 Docker 社区版
    [root@master ~]# yum install -y docker-ce
    
    # 配置 Docker 守护进程：
    # 1. 允许非安全仓库 (insecure-registries)
    # 2. 设置镜像加速器
    # 3. 设置 Cgroup 驱动为 systemd (K8s 推荐)
    [root@master ~]# mkdir -p /etc/docker
    [root@master ~]# tee /etc/docker/daemon.json <<-'EOF'
    {
      "insecure-registries" : ["0.0.0.0/0"],
      "registry-mirrors": ["https://5twf62k1.mirror.aliyuncs.com"], 
      "exec-opts": ["native.cgroupdriver=systemd"]
    }
    EOF
    
    # 重载配置并启动 Docker 服务
    [root@master ~]# systemctl daemon-reload
    [root@master ~]# systemctl restart docker && systemctl enable docker
    ```

    {% endnocopy %}

2. **安装 Docker-Compose**

    在 **Master 节点** 安装：

    {% nocopy %}

    ```bash
    # 从本地目录复制二进制文件到系统路径
    [root@master ~]# cp -rfv /opt/docker-compose/v1.25.5-docker-compose-Linux-x86_64 /usr/local/bin/docker-compose
    # 赋予可执行权限
    [root@master ~]# chmod +x /usr/local/bin/docker-compose
    # 验证安装版本
    [root@master ~]# docker-compose version
    docker-compose version 1.25.5, build 8a1c60f6
    ```

    {% endnocopy %}

3. **配置并安装 Harbor**

    在 **Master 节点** 部署 Harbor：

    {% nocopy %}

    ```bash
    # 导入 Harbor 运行所需的基础镜像
    [root@master ~]# docker load -i /opt/images/Kubernetes.tar
    
    # 解压 Harbor 离线安装包
    [root@master ~]# cd /root
    [root@master ~]# tar -zxvf /opt/harbor/harbor-offline-installer-v2.1.0.tgz
    [root@master ~]# cd harbor
    
    # 基于模板创建配置文件
    [root@master harbor]# cp harbor.yml.tmpl harbor.yml
    # 编辑配置文件 (vi/vim)
    [root@master harbor]# vi harbor.yml
    # 修改以下内容：
    # hostname: 10.18.4.10         <-- 修改为 Master IP
    # harbor_admin_password: Harbor12345
    # 注释掉 https 相关配置 (port, certificate, private_key)
    
    # 预处理配置文件
    [root@master harbor]# ./prepare
    # 执行安装脚本，并启用 Clair 镜像扫描功能
    [root@master harbor]# ./install.sh --with-clair
    ```

    {% endnocopy %}

4. **推送镜像到 Harbor**

    将本地镜像上传至私有仓库，供集群使用：

    {% nocopy %}

    ```bash
    # 进入镜像脚本目录
    [root@master ~]# cd /opt/images/
    # 执行推送脚本，将本地镜像批量上传至 Harbor
    [root@master images]# ./k8s_image_push.sh
    # 根据提示输入仓库地址(10.18.4.10)、用户名(admin)和密码(Harbor12345)
    ```

    {% endnocopy %}

5. **验证 Harbor 部署**

    确认 Harbor 服务正常运行并可访问：

    {% nocopy %}

    ```bash
    # 查看 Harbor 容器状态（需在 harbor 安装目录下执行）
    [root@master harbor]# docker-compose ps
    
    # 尝试在本地登录 Harbor
    [root@master harbor]# docker login 10.18.4.10 -u admin -p Harbor12345
    WARNING! Using --password via the CLI is insecure. Use --password-stdin.
    Login Succeeded
    ```

    {% endnocopy %}

    **Web 界面验证：**
    打开浏览器访问 `http://10.18.4.10`，使用用户名 `admin` 和密码 `Harbor12345` 登录，查看项目和镜像是否已成功上传。

### 部署 Kubernetes Master 节点

1. **安装 Kubeadm 工具**

    在 **所有节点** 安装核心组件：

    {% nocopy %}

    ```bash
    # 安装指定版本的 K8s 管理工具
    [root@master ~]# yum -y install kubeadm-1.18.1 kubectl-1.18.1 kubelet-1.18.1
    # 设置 kubelet 开机自启并立即启动
    [root@master ~]# systemctl enable kubelet && systemctl start kubelet
    ```

    {% endnocopy %}

2. **初始化集群**

    在 **Master 节点** 执行初始化。注意 `apiserver` 地址为 Master IP，镜像仓库指向阿里云（或本地Harbor，视实验要求而定，此处按文档指向阿里源）：

    {% nocopy %}

    ```bash
    # 初始化 K8s 控制平面
    [root@master ~]# kubeadm init \
      --kubernetes-version=1.18.1 \
      --apiserver-advertise-address=10.18.4.10 \
      --image-repository registry.aliyuncs.com/google_containers \
      --pod-network-cidr=10.244.0.0/16
    
    # 初始化成功后，会显示 "Your Kubernetes control-plane has initialized successfully!"
    # 并且会生成一段 kubeadm join 命令，请务必记录下来！
    ```

    {% endnocopy %}

3. **配置 Kubectl 认证**

    在 **Master 节点** 配置普通用户权限：

    {% nocopy %}

    ```bash
    # 创建 .kube 目录
    [root@master ~]# mkdir -p $HOME/.kube
    # 复制集群管理员配置文件到用户目录下
    [root@master ~]# cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    # 修改配置文件所有权
    [root@master ~]# chown $(id -u):$(id -g) $HOME/.kube/config
    
    # 查看集群组件健康状态
    [root@master ~]# kubectl get cs
    ```

    {% endnocopy %}

4. **安装 Flannel 网络插件**

    K8s 需要网络插件来实现 Pod 间的通信。在 **Master 节点** 执行：

    {% nocopy %}

    ```bash
    # 应用 Flannel 网络插件配置
    [root@master ~]# kubectl apply -f yaml/kube-flannel.yaml 
    
    # 等待片刻后查看 Master 节点状态，应由 NotReady 变为 Ready
    [root@master ~]# kubectl get nodes
    NAME     STATUS   ROLES    AGE   VERSION
    master   Ready    master   17m   v1.18.1
    ```

    {% endnocopy %}

### 安装 Kubernetes Dashboard

Dashboard 是 K8s 的 Web UI，方便用户管理集群。

1. **生成证书**

    {% nocopy %}

    ```bash
    # 创建证书存放目录
    [root@master ~]# mkdir dashboard-certs
    [root@master ~]# cd dashboard-certs/
    # 创建 Dashboard 专用的命名空间
    [root@master dashboard-certs]# kubectl create namespace kubernetes-dashboard
    
    # 生成私钥 (2048位 RSA)
    [root@master dashboard-certs]# openssl genrsa -out dashboard.key 2048
    # 生成证书签名请求 (CSR)
    [root@master dashboard-certs]# openssl req -days 36000 -new -out dashboard.csr -key dashboard.key -subj '/CN=dashboard-cert'
    
    # 使用私钥自签发证书 (有效期约100年)
    [root@master dashboard-certs]# openssl x509 -req -in dashboard.csr -signkey dashboard.key -out dashboard.crt
    
    # 将证书和私钥以 Secret 形式存入 K8s
    [root@master dashboard-certs]# kubectl create secret generic kubernetes-dashboard-certs --from-file=dashboard.key --from-file=dashboard.crt -n kubernetes-dashboard
    ```

    {% endnocopy %}

2. **部署 Dashboard**

    {% nocopy %}

    ```bash
    # 应用 Dashboard 的官方资源定义文件
    [root@master ~]# kubectl apply -f recommended.yaml 
    
    # 创建具有管理员权限的服务账号
    [root@master ~]# kubectl apply -f dashboard-adminuser.yaml 
    
    # 查看 Dashboard 服务的访问端口（NodePort 模式）
    [root@master ~]# kubectl get svc -n kubernetes-dashboard
    NAME                   TYPE       CLUSTER-IP      PORT(S)         
    kubernetes-dashboard   NodePort   10.98.134.7     443:30000/TCP   
    ```

    {% endnocopy %}

3. **获取登录 Token**

    {% nocopy %}

    ```bash
    # 获取 dashboard-admin 账号的 secret 名称并描述其内容以提取 token
    [root@master ~]# kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | grep dashboard-admin | awk '{print $1}')
    ```

    {% endnocopy %}
    复制输出中的 `token: eyJhbGciOiJSU...` 长字符串。

4. **配置 Master 参与调度（可选）**

    默认 Master 不运行业务 Pod，若需 Master 也作为工作节点：

    {% nocopy %}

    ```bash
    # 移除 Master 节点上的污点，允许调度 Pod
    [root@master ~]# kubectl taint node master node-role.kubernetes.io/master-
    ```

    {% endnocopy %}

### Worker Node 节点加入集群

1. **加入集群**

    在 **Node 节点** 执行初始化时生成的 `join` 命令：

    {% nocopy %}

    ```bash
    # 使用 kubeadm join 命令将工作节点加入集群
    [root@node ~]# kubeadm join 10.18.4.10:6443 \
      --token cxtb79.mqg7drycn5s82hhc \
      --discovery-token-ca-cert-hash sha256:d7465b10f81ecb32ca30459efc1e0efe4f22bfbddc0c17d9b691f611082f415c
    ```

    {% endnocopy %}
    *注意：Token 有效期为24小时，若过期需在 Master 节点运行 `kubeadm token create --print-join-command` 重新获取。*

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
