---
title: MinIO 存储应用部署
date: 
tags:
---

## 实验简介与理论基础

### 实验背景

在云计算时代，我们需要存储海量的非结构化数据（如图片、视频、日志、备份镜像）。传统的硬盘存储（块存储）在扩展性和共享性上存在局限。
**MinIO** 是一个基于 Go 语言开发的高性能**对象存储**服务。

* **特点**：轻量级、兼容亚马逊 AWS S3 接口、适合云原生环境。
* **核心概念**：
  * **Bucket (存储桶)**：相当于操作系统中的"顶级文件夹"，用于隔离不同类别的数据。
  * **Object (对象)**：存入的文件（图片、视频等），包含数据本身和元数据。

### 实验目标

本实验将在单台 CentOS 7.9 服务器上部署 MinIO 服务，实现：

1. 手动启动 MinIO 并访问控制台。
2. 配置 Systemd 实现服务开机自启和后台运行。
3. 通过网页端上传和预览文件。

### 节点规划

| IP地址 | 主机名 | 角色 | 挂载数据路径 |
| :--- | :--- | :--- | :--- |
| **172.128.11.63** | **minio** | MinIO 单机服务节点 | `/opt/data/minio` |

---

## 基础环境准备 (MinIO Node)

使用 CentOS7.9 镜像创建一台主机，主机配置使用 4VCPU/8GB 内存/100GB 硬盘。

**⚠️ 注意：** 本章所有命令均在 **172.128.11.63** 节点执行。

### 修改主机名

为了在网络中清晰标识服务器身份，首先修改主机名。

{% nocopy %}

```bash
[root@localhost ~]# hostnamectl set-hostname minio
[root@localhost ~]# bash
[root@minio ~]#
```

{% endnocopy %}

> **💡 解释**：`bash` 命令用于重新加载 Shell 环境，让新的主机名 `minio` 立即显示在命令行提示符中。

### 关闭防火墙

```bash
[root@minio ~]# systemctl stop firewalld
[root@minio ~]# systemctl disable firewalld
```

### 创建数据存储目录

MinIO 需要一个专门的目录来存放上传的文件。

```bash
[root@minio ~]# mkdir -p /opt/data/minio
```

* `/opt/data/minio`: 这是我们将要在启动命令中指定的**数据存储区**。

---

## 手动部署与测试

这一步旨在让大家快速体验 MinIO 的运行过程，验证软件是否可用。

### 上传并授权

假设你已经通过 FTP 或 SCP 工具将 `minio` 二进制文件上传到了 `/root` 目录。

**1. 检查文件**

```bash
[root@minio ~]# cd /root
[root@minio ~]# ll

# 此时应该能看到 minio 文件，但权限可能是 -rw-r--r-- (不可执行)

-rw-r--r--. 1 root root 94375936 May  9 03:26 minio
```

**2. 赋予执行权限**
Linux 系统中，必须显式给予文件"执行"权限，它才能像程序一样运行。

```bash

# 赋予执行权限: +x 表示添加执行(execute)权限

[root@minio ~]# chmod +x minio
[root@minio ~]# ll

# 此时文件名通常变绿，权限变为 -rwxr-xr-x

-rwxr-xr-x. 1 root root 94375936 May  9 03:26 minio
```

### 临时启动 MinIO

使用命令行直接启动 MinIO Server，并将 `/opt/data/minio` 指定为数据盘。

```bash

# 启动 MinIO 服务: server 子命令启动服务器模式, 参数指定数据存储目录

[root@minio ~]# ./minio server /opt/data/minio/
```

**观察启动日志（不要按 Ctrl+C）：**
当看到以下信息时，说明启动成功：

```text
API: <http://172.128.11.63:9000>  <http://127.0.0.1:9000>
RootUser: minioadmin
RootPass: minioadmin

Console: <http://172.128.11.63:37172> ...
WARNING: Console endpoint is listening on a dynamic port...
```

> **💡 理论加油站**：
>
> * **API 端口 (9000)**：程序代码（如 Java SDK）连接 MinIO 上传下载文件的端口。
> * **Console 端口 (随机/动态)**：浏览器访问的管理界面端口。老版本 MinIO 只有 9000 端口，新版本分离了控制台端口。当你浏览器访问 9000 时，它会自动重定向到那个随机端口。
> * **默认账号密码**：均为 `minioadmin`。

### 浏览器验证

1. 打开浏览器，访问 `<http://172.128.11.63:9000`。>
2. 页面会自动跳转到一个登录界面。
3. 输入账号 `minioadmin`，密码 `minioadmin` 进行登录。
4. 如果能看到红色的 MinIO 界面，说明环境正常。

**停止服务：**
回到终端，按 `Ctrl + C` 终止当前进程。
> **注意**：这种方式启动，一旦关闭 SSH 窗口或按 Ctrl+C，服务就会停止，不适合生产使用。接下来我们将把它配置为系统服务。

---

## 配置 Systemd 系统服务 (生产环境部署)

本章节将把 MinIO 配置为后台守护进程，实现开机自启和故障自动重启。

### 规范化程序目录

为了方便管理，我们将 MinIO 的**程序文件**和**数据文件**分开存放。

**1. 创建程序存放目录**

```bash

# 创建 MinIO 程序存放目录

[root@minio ~]# mkdir -p /data/minio_data/
```

**2. 移动程序文件**
将刚才在 root 目录下的 `minio` 程序移动到新目录。

```bash

# 复制 MinIO 程序文件到指定目录

[root@minio ~]# cp /root/minio /data/minio_data/
[root@minio ~]# ll /data/minio_data/

# 确保有 minio 文件且有执行权限

```

### 编写启动脚本

为了方便管理启动参数（如指定端口、指定配置文件），我们创建一个 Shell 脚本来启动它。

**1. 创建脚本文件**

```bash
[root@minio ~]# cd /data/minio_data/
[root@minio minio_data]# vi run.sh
```

**2. 写入以下内容**

```bash
# !/bin/bash

# 启动 minio，指定数据目录为 /opt/data/minio

/data/minio_data/minio server /opt/data/minio
```

**3. 赋予脚本执行权限**

```bash

# 赋予脚本所有权限: 777 表示所有用户都有读、写、执行权限(rwxrwxrwx)

[root@minio minio_data]# chmod 777 run.sh
```

### 编写 Systemd 服务文件

Linux 的 Systemd 是管理系统服务的标准方式。

**1. 创建 service 文件**

```bash
[root@minio minio_data]# vi /usr/lib/systemd/system/minio.service
```

**2. 写入以下内容**

```ini
[Unit]
Description=Minio service
Documentation=<https://docs.minio.io/>

[Service]

# 工作目录：程序所在的文件夹

WorkingDirectory=/data/minio_data

# 启动命令：指向我们刚才写的脚本

ExecStart=/data/minio_data/run.sh

# 故障重启机制：如果非正常退出，5秒后自动重启

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 启动服务并设置开机自启

**1. 启动 MinIO 服务**

```bash

# 启动 MinIO 服务

[root@minio minio_data]# systemctl start minio
```

**2. 查看服务状态**

```bash

# 查看服务运行状态

[root@minio minio_data]# systemctl status minio
```

**验证关键点**：

* 看到 `Active: active (running)` 表示启动成功。
* 日志中应包含 `API: http://...:9000`。

**3. 设置开机自启**

```bash

# 设置 MinIO 服务开机自启

[root@minio minio_data]# systemctl enable minio

# 输出 Created symlink ... 表示设置成功

```

---

## MinIO 功能应用体验

### 登录控制台

1. 浏览器再次访问 `<http://172.128.11.63:9000`。>
2. 使用 `minioadmin` / `minioadmin` 登录。

### 创建存储桶 (Create Bucket)

MinIO 存储文件前必须先创建桶。

1. 点击右下角的 **"+"** 号按钮（或页面上的 "Create Bucket"）。
2. 输入 Bucket Name（桶名）：例如 `test`。
3. 按回车键确认。

### 上传文件 (Upload Object)

1. 点击进入刚才创建的 `test` 桶。
2. 点击右下角的 **上传按钮**（Upload file）。
3. 从你的电脑本地选择一张图片（如 `.jpg` 或 `.png`）。
4. 上传成功后，列表中会显示该文件。

### 预览与分享 (Preview)

1. 点击上传的文件名。
2. 右侧会弹出详情页。
3. 点击 **"Share"** 按钮，可以生成一个临时的下载链接。
4. 点击 **"Preview"**（如果支持），可以直接在浏览器中看到图片内容。

> **💡 实验成果**：如果你能成功上传图片并在浏览器中预览，说明你的私有云对象存储服务已经搭建完毕！

---

## 常见问题排查 (Troubleshooting)

**Q1: 浏览器访问 IP:9000 打不开？**

* **原因 1**：MinIO 服务没启动。
  * *解决*：执行 `systemctl status minio` 查看状态。
* **原因 2**：防火墙拦截。
  * *解决*：测试环境可临时关闭防火墙 `systemctl stop firewalld`。
* **原因 3**：浏览器自动跳转的随机端口（如 35282）被防火墙拦截。
  * *解决*：如果你在外部网络，可能需要放行所有高位端口，或者在启动命令中指定固定控制台端口（例如 `--console-address ":9001"`，本实验使用默认设置，请确保网络通畅）。

**Q2: 启动脚本报错 "Permission denied"？**

* *解决*：检查 `run.sh` 和 `minio` 二进制文件是否都有执行权限 (`chmod +x ...`)。

**Q3: 之前上传的文件不见了？**

* *解决*：检查启动命令中的数据目录是否正确。如果在步骤 3.2 和 4.2 中指定的目录不一致（例如一个是 `/opt/data` 一个是 `/opt/minio`），数据就不会互通。本实验统一要求使用 `/opt/data/minio`。
