---
title: Ansible集群服务部署
date: 
tags:
---

## 实验简介与理论基础

### 实验背景

日志是定位问题与审计合规的关键数据。通过 ELK（Elasticsearch、Logstash、Kibana）可以实现日志的集中采集、存储、检索与可视化分析。本实验将使用 Ansible 一次性在三台业务节点上部署 ELK 集群，实现日志从系统文件汇聚至 Elasticsearch，并在 Kibana 中展示。

### 实验目标

1. 搭建 3 节点 Elasticsearch 集群（1 主控节点 + 2 数据节点）。
2. 在 node1 部署 Kibana，node2 部署 Logstash，形成采集-存储-展示链路。
3. 使用 Ansible 编排整个安装与配置流程，支持一键部署与回放。
4. 完成基础验证：集群健康、Kibana 页面访问、Logstash 采集系统日志。

---

## 实验环境准备

### 节点规划

节点规划如下：

| IP             | 主机名   | 节点                 |
|----------------|----------|----------------------|
| 172.128.11.160 | ansible  | Ansible节点          |
| 172.128.11.161 | node1    | Elasticsearch/Kibana |
| 172.128.11.162 | node2    | Elasticsearch/Logstash|
| 172.128.11.163 | node3    | Elasticsearch        |

### 基础准备

- 使用CentOS 7.9镜像创建四台云主机，配置为1VCPU/2GB内存/20GB硬盘。
- 所有节点需保持网络互通，且时间同步。

---
**⚠️ 注意：** 本章除特别说明外，所有命令均在 172.128.11.160（ansible）节点执行。

## 实验实施

### ELK 介绍

**常见架构：**

1. **Elasticsearch + Logstash + Kibana**  
   - 最简单的架构，通过Logstash收集日志，Elasticsearch分析日志，Kibana展示日志。
   - **Elasticsearch**：分布式搜索引擎，提供存储、分析和搜索功能。
   - **Logstash**：日志收集、过滤和转发框架。
   - **Kibana**：日志报表系统，提供Web界面。

2. **Elasticsearch + Logstash + Filebeat + Kibana**  
   - 增加轻量级日志收集代理Filebeat，节省资源，但存在Logstash故障时日志丢失的风险。
3. **Elasticsearch + Logstash + Filebeat + Redis + Kibana**  
   - 通过中间件（如Redis）避免日志丢失。

---

**💡 理论加油站（建议先看再做）**

- 集群角色：
  - master 节点：负责选主与集群元数据管理，稳定性要求高，通常不存储业务数据（node.master: true，node.data: false）。
  - data 节点：负责数据存储与查询计算（node.master: false，node.data: true）。
- 分片与副本：
  - 分片（shard）水平拆分索引以提升并发与容量；副本（replica）提供高可用与读扩展。
- 端口约定：
  - Elasticsearch HTTP 端口 9200；节点间通信默认 9300。
  - Kibana 默认 5601；Logstash 可按 pipeline 配置监听不同输入。
- 发现机制：
  - 本实验使用单播发现（unicast），通过主机名或 IP 指定集群成员列表。

### ELK 部署步骤

#### 配置主机映射

**操作节点：ansible**

{% nocopy %}

```bash
# 添加主机名映射
[root@ansible ~]#  vi /etc/hosts
172.128.11.160 ansible
172.128.11.161 node1
172.128.11.162 node2
172.128.11.163 node3
```

{% endnocopy %}

{% nocopy %}

```bash
# 配置免密登录（所有节点密码为000000）
[root@ansible ~]# ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
[root@ansible ~]# ssh-copy-id root@172.128.11.161
[root@ansible ~]# ssh-copy-id root@172.128.11.162
[root@ansible ~]# ssh-copy-id root@172.128.11.163
# 复制hosts文件到其他节点（从 ansible 节点 /root）
[root@ansible ~]# scp /etc/hosts root@172.128.11.161:/etc/
[root@ansible ~]# scp /etc/hosts root@172.128.11.162:/etc/
[root@ansible ~]# scp /etc/hosts root@172.128.11.163:/etc/
# 关闭防火墙和 Selinux（在各节点上执行）
[root@ansible ~]# systemctl stop firewalld
[root@ansible ~]# setenforce 0
```

{% endnocopy %}

**⚠️注意：**

- 免密登录需确认所有节点密码一致。
- 若Selinux未关闭，可能导致服务启动失败。

#### 软件包上传及Yum源配置

**操作节点：ansible**

{% nocopy %}

```bash
# 在 ansible 节点
[root@ansible ~]# ls /root
# 应包含：elasticsearch-6.0.0.rpm、kibana-6.0.0-x86_64.rpm、logstash-6.0.0.rpm、ansible.tar.gz
# 分发软件包（从 ansible 推送到各节点）
[root@ansible ~]# scp elasticsearch-6.0.0.rpm root@172.128.11.161:/root/
[root@ansible ~]# scp elasticsearch-6.0.0.rpm root@172.128.11.162:/root/
[root@ansible ~]# scp elasticsearch-6.0.0.rpm root@172.128.11.163:/root/
[root@ansible ~]# scp kibana-6.0.0-x86_64.rpm root@172.128.11.161:/root/
[root@ansible ~]# scp logstash-6.0.0.rpm root@172.128.11.162:/root/
# 配置本地 Yum 源（在 ansible 节点 /root）
[root@ansible ~]# tar -zxvf ansible.tar.gz -C /opt/
[root@ansible ~]# mv /etc/yum.repos.d/* /media/  # 备份原有源
```

{% endnocopy %}

在 `/etc/yum.repos.d/local.repo` 创建如下内容：

{% nocopy %}

```ini
[ansible]
name=ansible
baseurl=file:///opt/ansible
gpgcheck=0
enabled=1
```

```bash
[root@ansible ~]# yum -y install ansible
```

{% endnocopy %}

**⚠️注意：**

- 若`/etc/yum.repos.d/`目录下有其他源文件，需先备份或移除，避免冲突。

#### 配置Ansible主机清单

{% nocopy %}

```bash
# 在 ansible 节点创建示例目录并进入
[root@ansible ~]# mkdir -p /root/example
[root@ansible ~]# cd /root/example
[root@ansible ~/example]# 
```

{% endnocopy %}

将 `/etc/ansible/hosts` 更新为：

```ini
[node1]
172.128.11.161
[node2]
172.128.11.162
[node3]
172.128.11.163
```

#### 配置 FTP 服务用于 Java 安装

{% nocopy %}

```bash
# 在 ansible 节点以 root 执行
[root@ansible ~]# mkdir -p /opt/centos
[root@ansible ~]# mount /root/CentOS-7-x86_64-DVD-2009.iso /opt/centos/
# 更新 Yum 源配置（增加挂载的本地 ISO 源，便于离线安装 Java 等依赖）
```

```ini
[ansible]
name=ansible
baseurl=file:///opt/ansible
gpgcheck=0
enabled=1
[centos]
name=centos
baseurl=file:///opt/centos
gpgcheck=0
enabled=1
```

```bash
# 安装并配置 VSFTPD
[root@ansible ~]# yum install -y vsftpd
[root@ansible ~]# echo "anon_root=/opt" >> /etc/vsftpd/vsftpd.conf
[root@ansible ~]# systemctl restart vsftpd
```

在 `/root/example` 下创建 `ftp.repo`，写入：

```ini
[centos]
name=centos
baseurl=ftp://172.128.11.160/centos/
gpgcheck=0
enabled=1
```

{% endnocopy %}

**⚠️注意：**

- 确保防火墙关闭，否则节点可能无法访问FTP服务。
- 安装 Elasticsearch 6.x 需要 Java 8（本实验通过本地 ISO 源与 FTP 分发到各节点）。

#### 生成Elasticsearch配置文件

**操作节点：ansible**

{% nocopy %}

```bash
# 在 ansible 节点生成 Elasticsearch 配置
[root@ansible ~]# rpm -ivh /root/elasticsearch-6.0.0.rpm
# 生成 node1 配置（拷贝到 /root/example）
[root@ansible ~]# cp /etc/elasticsearch/elasticsearch.yml /root/example/elk1.yml
```

{% endnocopy %}

将 `/root/example/elk1.yml` 调整为如下：

{% nocopy %}

```yaml
# 原文 #cluster.name: my-application
cluster.name: ELK                    # 集群名称，需在所有节点保持一致
# 原文 #node.name: node-1
node.name: node1                     # 节点名称，建议与主机名一致
# 原文 #network.host: 192.168.0.1
network.host: 172.128.11.161         # 本机绑定 IP（不要填 0.0.0.0）
# 原文 #http.port 9200
http.port: 9200                      # HTTP API 端口
# 原文 #discovery.zen.ping.unicast.hosts: ["host1", "host2"]
discovery.zen.ping.unicast.hosts: ["node1", "node2", "node3"]  # 单播发现列表
```

{% endnocopy %}

{% nocopy %}

```bash
# 生成 node2 配置（在 /root/example）
[root@ansible ~]# cd /root/example
[root@ansible ~/example]# cp elk1.yml elk2.yml
[root@ansible ~/example]# sed -i 's/node.name: node1/node.name: node2/g' elk2.yml
[root@ansible ~/example]# sed -i 's/172.128.11.161/172.128.11.162/g' elk2.yml
```

{% endnocopy %}

核对`/root/example/elk2.yml` 修改后应为：

```yaml
node.name: node2
network.host: 172.128.11.162
```

{% nocopy %}

```bash
# 生成 node3 配置
[root@ansible ~/example]# cp elk1.yml elk3.yml
[root@ansible ~/example]# sed -i 's/node.name: node1/node.name: node3/g' elk3.yml
[root@ansible ~/example]# sed -i 's/172.128.11.161/172.128.11.163/g' elk3.yml
```

{% endnocopy %}

核对`/root/example/elk3.yml` 修改后应为：

{% nocopy %}

```yaml
node.name: node3
network.host: 172.128.11.163
```

{% endnocopy %}

#### 生成Kibana配置文件

{% nocopy %}

```bash
# 在 ansible 节点安装并生成 Kibana 配置
[root@ansible ~]# rpm -ivh /root/kibana-6.0.0-x86_64.rpm
[root@ansible ~]# cp /etc/kibana/kibana.yml /root/example/
[root@ansible ~]# cd /root/example
```

{% endnocopy %}

修改 `/root/example/kibana.yml` ：

```yaml
# 原文 #server.port: 5601
server.port: 5601                         # Kibana Web 控制台端口
# 原文 #server.host: "localhost"
server.host: "172.128.11.161"            # 绑定的访问 IP（与部署节点一致）
# 原文 #elasticsearch.url: "http://localhost:9200"
elasticsearch.url: "http://172.128.11.161:9200"  # 关联的 Elasticsearch 地址
```

#### 生成Logstash配置文件

{% nocopy %}

```bash
# 在 ansible 节点安装并生成 Logstash 配置
[root@ansible ~]# rpm -ivh /root/logstash-6.0.0.rpm
[root@ansible ~]# cp /etc/logstash/logstash.yml /root/example/
[root@ansible ~]# cd /root/example
```

{% endnocopy %}

修改 `/root/example/logstash.yml`：

```yaml
# 原文 # http.host: "127.0.0.1"
http.host: "172.128.11.162"     # Logstash HTTP 监听地址（管理接口）
```

在 `/root/example/syslog.conf` 写入：

> 这段可复制

```ruby
input {
  file {
    path => "/var/log/messages"   # 采集系统日志
    type => "systemlog"            # 打上类型标签，便于后续分流
    start_position => "beginning"  # 第一次启动从头读取
    stat_interval => "3"           # 每 3 秒检查文件变化
  }
}
output {
  if [type] == "systemlog" {
    elasticsearch {
      hosts => ["172.128.11.161:9200"]  # 指向 node1 的 ES
      index => "system-log-%{+YYYY.MM.dd}" # 按日期滚动索引
    }
  }
}
```

#### 编写Ansible剧本

{% nocopy %}

```bash
# 在example目录下编写剧本文件cscc_install.yaml
[root@ansible ~]# cd example
[root@ansible ~/example]# vi cscc_install.yaml
```

{% endnocopy %}

> 这段可复制

```yaml
# cscc_install.yaml
- hosts: all
  remote_user: root
  tasks:
    - name: 清理原有Yum源
      shell: rm -rf /etc/yum.repos.d/*
    - name: 配置FTP源
      copy: src=ftp.repo dest=/etc/yum.repos.d/
    - name: 安装Java
      shell: yum -y install java-1.8.0-*   # ES 6.x 依赖 Java 8
    - name: 安装Elasticsearch
      shell: rpm -ivh /root/elasticsearch-6.0.0.rpm  # 先在 ansible 节点解包以生成模板
- hosts: node1
  remote_user: root
  tasks:
    - name: 配置Elasticsearch
      copy: src=elk1.yml dest=/etc/elasticsearch/elasticsearch.yml  # 推送 master 配置
    - name: 重载系统服务
      shell: systemctl daemon-reload
    - name: 启动Elasticsearch
      shell: systemctl start elasticsearch && systemctl enable elasticsearch
    - name: 安装Kibana
      shell: rpm -ivh /root/kibana-6.0.0-x86_64.rpm
    - name: 配置Kibana
      template: src=kibana.yml dest=/etc/kibana/kibana.yml  # 关联到本机 ES
    - name: 启动Kibana
      shell: systemctl start kibana && systemctl enable kibana
- hosts: node2
  remote_user: root
  tasks:
    - name: 配置Elasticsearch
      copy: src=elk2.yml dest=/etc/elasticsearch/elasticsearch.yml
    - name: 重载系统服务
      shell: systemctl daemon-reload
    - name: 启动Elasticsearch
      shell: systemctl start elasticsearch && systemctl enable elasticsearch
    - name: 安装Logstash
      shell: rpm -ivh /root/logstash-6.0.0.rpm
    - name: 配置Logstash
      copy: src=logstash.yml dest=/etc/logstash/logstash.yml   # 设置管理接口监听地址
    - name: 配置日志收集
      copy: src=syslog.conf dest=/etc/logstash/conf.d/syslog.conf  # 采集 /var/log/messages
- hosts: node3
  remote_user: root
  tasks:
    - name: 配置Elasticsearch
      copy: src=elk3.yml dest=/etc/elasticsearch/elasticsearch.yml
    - name: 重载系统服务
      shell: systemctl daemon-reload
    - name: 启动Elasticsearch
      shell: systemctl start elasticsearch && systemctl enable elasticsearch
```

#### 执行剧本并验证

{% nocopy %}

```bash
# 在 ansible 节点执行剧本
[root@ansible ~]# cd /root/example
[root@ansible ~/example]# ansible-playbook cscc_install.yaml
```

{% endnocopy %}

**⚠️注意：**

- 首次执行可能因网络或依赖问题失败，可尝试分阶段执行剧本。
- 若节点服务启动失败，检查日志：`journalctl -u elasticsearch`。

**验证关键点：**

- 集群健康：

{% nocopy %}

```bash
curl http://172.128.11.161:9200/_cluster/health?pretty
```

{% endnocopy %}

状态为 `green`/`yellow` 表示集群正常（单副本可能为 yellow）。

- 访问 Kibana：

浏览器打开 <http://172.128.11.161:5601> 能看到登录/首页即为成功。

- Logstash 采集：

{% nocopy %}

```bash
tail -f /var/log/elasticsearch/*.log
```

{% endnocopy %}

观察到新索引按天生成（如 `system-log-YYYY.MM.dd`）。

---

## 常见问题排查（Troubleshooting）

1. **Ansible连接失败**  
   - 检查免密登录配置：`ssh node1` 是否无需密码。
   - 确认所有节点防火墙和Selinux已关闭。

2. **Elasticsearch启动失败**  
   - 检查Java是否安装：`java -version`。
   - 查看日志：`tail -f /var/log/elasticsearch/elk.log`。

- 端口冲突：`ss -tunlp | grep -E "9200|9300"`。
- 虚拟内存不足（vm.max_map_count）：按需执行 `sysctl -w vm.max_map_count=262144` 并写入 `/etc/sysctl.conf` 持久化。

1. **Kibana无法访问**  
   - 确认node1的5601端口开放：`netstat -tunlp | grep 5601`。
   - 检查Kibana配置中Elasticsearch地址是否正确。

- 浏览器缓存或代理导致异常，尝试隐身模式或更换浏览器。

1. **Logstash日志收集失败**  
   - 确认`/var/log/messages`文件存在且可读。
   - 测试Logstash配置：`/usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/syslog.conf --config.test_and_exit`。

- 查看运行日志：`journalctl -u logstash -f`，关注插件加载与 ES 连接报错。

---

**附加建议**

- 生产建议将 master 与 data 角色分离，master 至少 3 台以保证选主高可用。
- 为 ES 配置合理的 JVM 内存（如 `-Xms -Xmx`），并避免与系统总内存竞争。
- 禁止在生产环境关闭安全机制（SELinux/防火墙）；本实验为教学环境，便于快速体验。
