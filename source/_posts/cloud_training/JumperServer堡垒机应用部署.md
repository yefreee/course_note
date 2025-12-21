---
title: Jumpserver 堡垒机应用部署
date:
tags:
---

## 实验简介与理论基础

### 实验背景

企业生产环境中，直接从外网登录内部服务器存在较大安全风险。**堡垒机（Bastion Host）**作为统一入口，提供账号集中管理、授权控制、操作审计等能力，从而满足合规与安全要求。**Jumpserver** 是国产开源堡垒机方案，支持完整的 4A 规范。

### 实验目标

1. 通过离线包与 Docker 在一台 CentOS 7.9 节点上部署 Jumpserver。
2. 初始化系统并在 Web 端完成基本配置。
3. 纳管一台 OpenStack 控制节点，实现 Web 终端远程登录与审计。

### 理论加油站

- 4A 能力：
  - 认证（Authentication）：确认身份，例如登录用户名与密码/多因子。
  - 授权（Authorization）：分配可访问的资产与操作范围。
  - 账号（Account）：统一管理目标资产上的系统账号（如 root、appuser）。
  - 审计（Auditing）：记录并回放操作（命令、会话录像）。
- 组件架构（容器化部署常见组件）：
  - Core：后端核心服务（Django），提供业务逻辑与 API。
  - Koko：终端访问网关（Go），负责 SSH/Telnet；与浏览器 Web 终端协同。
  - Lion：图形化远程访问（RDP/VNC）。
  - Nginx：反向代理与静态资源分发。
  - Redis：缓存/会话管理。
  - MySQL：持久化数据库。
- 认证与登录链路：浏览器 → Nginx → Core（认证与授权）→ Koko/Lion（建立终端/图形连接）→ 目标资产主机。
- 资产与系统用户模型：资产（如一台服务器）与系统用户（在资产上的具体登录身份）进行绑定，再通过“资产授权”将其分配给平台用户或用户组。

---

## 基础环境准备（Node: jumpserver）

**⚠️ 注意：** 本章所有命令均在 **192.168.200.13 (jumpserver)** 节点执行，且与目标资产节点网络互通。

### 修改主机名

为了区分服务器角色，首先修改主机名。

{% nocopy %}

```bash
[root@localhost ~]# hostnamectl set-hostname jumpserver
[root@localhost ~]# bash
[root@jumpserver ~]# 
```

{% endnocopy %}

> **💡 解释**：执行 `bash` 是为了重新加载 Shell 环境，让新的主机名立即显示在提示符中。

### 关闭安全策略（教学环境）

为了防止实验过程中端口被拦截，暂时关闭防火墙和 SELinux（生产不建议）。

{% nocopy %}

```bash
# 1. 关闭防火墙
[root@jumpserver ~]# systemctl stop firewalld
[root@jumpserver ~]# systemctl disable firewalld
[root@jumpserver ~]# iptables -F  # 清空 iptables 规则
# 2. 关闭 SELinux
[root@jumpserver ~]# setenforce 0
[root@jumpserver ~]# sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
```

{% endnocopy %}

### 配置本地 YUM 源（离线仓库）

假设提供的安装包 `jumpserver.tar.gz` 已经上传至 `/root` 目录，该安装包内含离线 YUM 仓库。

{% nocopy %}

```bash
# 解压安装包到 /opt 目录
[root@jumpserver ~]# tar -zxvf jumpserver.tar.gz -C /opt/
# 备份原有 repo 文件
[root@jumpserver ~]# mv /etc/yum.repos.d/* /media/
# 创建本地 repo 文件
[root@jumpserver ~]# vi /etc/yum.repos.d/jumpserver.repo
```

{% endnocopy %}

写入以下内容：

```ini
[jumpserver]
name=jumpserver
baseurl=file:///opt/jumpserver-repo
gpgcheck=0
enabled=1
```

验证源是否生效：

{% nocopy %}

```bash
[root@jumpserver ~]# yum repolist
# 看到 jumpserver 源且状态数字非 0 即为成功
```

{% endnocopy %}

---

## 安装依赖与 Docker 环境

### 安装 Python 依赖

{% nocopy %}

```bash
[root@jumpserver ~]# yum install python2 -y
```

{% endnocopy %}

### 安装与配置 Docker（离线二进制）

本案例使用离线二进制方式安装 Docker（与在线 `yum install docker` 不同）。

{% nocopy %}

```bash
# 1. 复制 Docker 二进制文件到系统路径
[root@jumpserver ~]# cp -rf /opt/docker/* /usr/bin/
[root@jumpserver ~]# chmod 775 /usr/bin/docker*
# 2. 配置 Docker 系统服务
[root@jumpserver ~]# cp -rf /opt/docker.service /etc/systemd/system/
[root@jumpserver ~]# chmod 755 /etc/systemd/system/docker.service
# 3. 启动 Docker 并设置开机自启
[root@jumpserver ~]# systemctl daemon-reload
[root@jumpserver ~]# systemctl enable docker --now
# 4. 验证安装
[root@jumpserver ~]# docker --version
[root@jumpserver ~]# docker-compose --version
```

{% endnocopy %}

> **💡 提示**：如果 `docker-compose --version` 无法输出版本，请确认 `docker-compose` 可执行文件已包含在 `/usr/bin/`，并具备执行权限。

---

## 部署 Jumpserver 服务

### 加载离线镜像

Jumpserver 由多个组件（Redis、MySQL、Nginx、Core、Koko、Lion 等）组成，需要先导入容器镜像。

{% nocopy %}

```bash
[root@jumpserver ~]# cd /opt/images/
[root@jumpserver images]# sh load.sh
```

{% endnocopy %}

> **⏳ 等待**：导入过程可能需要几分钟，请耐心等待所有镜像加载完成。

### 准备配置文件与数据目录

{% nocopy %}

```bash
# 创建数据持久化目录
[root@jumpserver images]# mkdir -p /opt/jumpserver/{core,koko,lion,mysql,nginx,redis}
# 复制配置文件
[root@jumpserver images]# cp -rf /opt/config /opt/jumpserver/
```

{% endnocopy %}

### 使用 Compose 启动服务

通过 Docker Compose 编排启动所有容器。

{% nocopy %}

```bash
[root@jumpserver images]# cd /opt/compose/
# 加载环境变量
[root@jumpserver compose]# source /opt/static.env
# 执行启动脚本
[root@jumpserver compose]# sh up.sh
```

{% endnocopy %}

**观察输出**：看到一列绿色的 `Creating ... done` 表示容器启动成功。

> **💡 理论加油站**：
>
> - Core：后端核心服务，负责认证/授权/审计等业务逻辑。
> - Koko：终端网关，承担 SSH/Telnet 会话建立。
> - Lion：图形会话网关，承担 RDP/VNC 会话建立。
> - Nginx：统一入口与静态资源代理。
> - Redis/MySQL：缓存与数据库存储。

**快速验证容器状态**：

{% nocopy %}

```bash
docker ps -a
```

{% endnocopy %}

---

## Jumpserver 初始化配置（Web端）

### 登录系统

1. 打开浏览器，访问 `http://192.168.200.13`。
2. 默认账号：`admin`；默认密码：`admin`。
3. 首次登录会强制要求修改密码（例如修改为 `Admin@123`）。

> **⚠️ 注意**：首次登录后请尽快更改默认密码，并启用复杂度策略以提升安全性。

---

## 纳管 OpenStack 资产（核心步骤）

在 Jumpserver 中纳管一台服务器，逻辑顺序如下：
**创建管理用户 → 创建系统用户 → 创建资产 → 资产授权**。

### 创建管理用户（特权账号）

> **💡 概念**：管理用户用于“连接”目标服务器，获取硬件信息、推送系统用户公钥等。通常是目标机的 root 账号。

1. 左侧菜单：资产管理 → 管理用户。
2. 点击“创建”。
3. 填写信息：
    - 名称：`root`（或自定义）
    - 用户名：`root`（必须是目标机真实存在的特权账号）
    - 密码：填写目标机（Controller 节点）的 root 密码
4. 点击“提交”。

### 创建系统用户（登录账号）

> **💡 概念**：运维人员通过堡垒机登录资产时，自动切换成的身份。例如设置为 `root` 则拥最高权限。

1. 左侧菜单：资产管理 → 系统用户。
2. 点击“创建”。
3. 填写信息：
    - 名称：`System-Root`（或自定义）
    - 协议：`SSH`
    - 用户名：`root`（登录后变成的身份）
    - 认证方式：
      - 方式一（自动推送）：选择“自动生成密钥”，Jumpserver 会将公钥推送到目标机（推荐）。
      - 方式二（密码托管）：手动输入目标机密码。
      - 实验建议：输入Controller节点的密码，或勾选自动生成（依赖管理用户权限）。
4. 点击“提交”。

### 创建资产（添加服务器）

1. 左侧菜单：资产管理 → 资产列表。
2. 点击“创建”。
3. 填写信息：
    - 主机名：`controller`
    - IP（主机）：`192.168.200.11`
    - 系统平台：`Linux`
    - 管理用户：选择刚才创建的 `root` 管理用户
4. 点击“提交”。
    - 验证：提交后，列表中的“可连接”状态应变绿（若管理用户与网络配置正确）。

### 资产授权（分配权限）

没有授权，即便是管理员也看不到资产。

1. 左侧菜单：权限管理 → 资产授权。
2. 点击“创建”。
3. 填写信息：
    - 名称：`Auth-Rule-01`
    - 用户：选择 `Administrator`（当前登录的 Web 用户）
    - 用户组：`Default`
    - 资产：选择刚才创建的 `controller`
    - 系统用户：选择刚才创建的 `System-Root`
4. 点击“提交”。

---

## 远程连接测试

1. 点击页面右上角“用户图标” → Web 终端（或左侧菜单的 Web 终端）。
2. 在左侧文件树中，展开 `Default` 文件夹。
3. 点击 `controller` 资产。
4. 如果配置正确，浏览器将在右侧窗口打开一个 SSH 会话，显示 `[root@controller ~]#` 提示符。
5. 试着输入命令：`ip a` 或 `ls`，验证是否操作成功。

---

## 常见问题排查（Troubleshooting）

**浏览器访问 IP 报 502 Bad Gateway？**

- 原因：Jumpserver 的后端服务还没完全启动。
- 解决：Docker 启动需要时间，等待 1-2 分钟后刷新。如果长时间不行，检查容器状态：

**资产列表中“可连接”状态是红色？**

- 原因：管理用户配置错误或无法连通目标机。
- 解决：
  - 检查 `192.168.200.11` 网络连通：`ping -c 3 192.168.200.11`
  - 检查 22 端口：`ss -tunlp | grep :22`（目标机）
  - 检查在“创建管理用户”步骤中填写的 root 密码是否正确。

**容器服务异常/重启频繁？**

- 观察具体容器日志：`docker logs -f <service-name>`。
- 检查磁盘空间与目录权限：确保 `/opt/jumpserver/*` 目录存在并可写。
- 校验环境变量：确认 `/opt/static.env` 内容与 compose 服务名一致。
