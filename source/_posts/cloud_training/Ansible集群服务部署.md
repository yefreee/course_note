---
title: Ansible集群服务部署
date: 
tags:
---

## 实验简介与理论基础

本案例通过Ansible在三个节点上部署ELK集群日志分析系统，分别部署Kibana、Logstash和Elasticsearch服务。本实验指导书将详细讲解部署步骤，并标注新手容易出错的地方。

---

## 实验环境准备

### 节点规划

节点规划如下：

| IP             | 主机名   | 节点                 |
|----------------|----------|----------------------|
| 172.128.11.162 | ansible  | Ansible节点          |
| 172.128.11.217 | node1    | Elasticsearch/Kibana |
| 172.128.11.170 | node2    | Elasticsearch/Logstash|
| 172.128.11.248 | node3    | Elasticsearch        |

### 基础准备

- 使用CentOS 7.9镜像创建四台云主机，配置为1VCPU/2GB内存/20GB硬盘。
- 所有节点需保持网络互通，且时间同步。

---
**⚠️ 注意：** 本章除特别说明外，所有命令均在 172.128.11.162（ansible）节点执行。

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

### ELK 部署步骤

#### 配置主机映射

**操作节点：ansible**

```bash
# 添加主机名映射
[root@ansible ~]#  vi /etc/hosts
```

```bash
172.128.11.162 ansible
172.128.11.217 node1
172.128.11.170 node2
172.128.11.248 node3
```

```bash
# 配置免密登录（所有节点密码为000000）
[root@ansible ~]# ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
[root@ansible ~]# ssh-copy-id root@172.128.11.217
[root@ansible ~]# ssh-copy-id root@172.128.11.170
[root@ansible ~]# ssh-copy-id root@172.128.11.248

# 复制hosts文件到其他节点（从 ansible 节点 /root）
[root@ansible ~]# scp /etc/hosts root@172.128.11.217:/etc/
[root@ansible ~]# scp /etc/hosts root@172.128.11.170:/etc/
[root@ansible ~]# scp /etc/hosts root@172.128.11.248:/etc/

# 关闭防火墙和 Selinux（在各节点上执行）
[root@ansible ~]# systemctl stop firewalld
[root@ansible ~]# setenforce 0
```

**⚠️注意：**

- 免密登录需确认所有节点密码一致。
- 若Selinux未关闭，可能导致服务启动失败。

#### 软件包上传及Yum源配置

**操作节点：ansible**

```bash
# 在 ansible 节点 /root
[root@ansible ~]# ls /root
# 应包含：elasticsearch-6.0.0.rpm、kibana-6.0.0-x86_64.rpm、logstash-6.0.0.rpm、ansible.tar.gz

# 分发软件包（从 ansible 推送到各节点）
[root@ansible ~]# scp elasticsearch-6.0.0.rpm root@172.128.11.217:/root/
[root@ansible ~]# scp elasticsearch-6.0.0.rpm root@172.128.11.170:/root/
[root@ansible ~]# scp elasticsearch-6.0.0.rpm root@172.128.11.248:/root/
[root@ansible ~]# scp kibana-6.0.0-x86_64.rpm root@172.128.11.217:/root/
[root@ansible ~]# scp logstash-6.0.0.rpm root@172.128.11.170:/root/

# 配置本地 Yum 源（在 ansible 节点 /root）
[root@ansible ~]# tar -zxvf ansible.tar.gz -C /opt/
[root@ansible ~]# mv /etc/yum.repos.d/* /media/  # 备份原有源
```

Create `/etc/yum.repos.d/local.repo` with the following content:

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

**⚠️注意：**

- 若`/etc/yum.repos.d/`目录下有其他源文件，需先备份或移除，避免冲突。

#### 配置Ansible主机清单

```bash
# 在 ansible 节点创建示例目录并进入
[root@ansible ~]# mkdir -p /root/example
[root@ansible ~]# cd /root/example
[root@ansible ~/example]# 
```

将 `/etc/ansible/hosts` 更新为：

```ini
[node1]
172.128.11.217

[node2]
172.128.11.170

[node3]
172.128.11.248
```

#### 配置 FTP 服务用于 Java 安装

```bash
# 在 ansible 节点以 root 执行
[root@ansible ~]# mkdir -p /opt/centos
[root@ansible ~]# mount /root/CentOS-7-x86_64-DVD-2009.iso /opt/centos/

# 更新 Yum 源配置
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
[root@ansible ~]# sed -i 's#^#anon_root=/opt#g' /etc/vsftpd/vsftpd.conf
[root@ansible ~]# systemctl restart vsftpd

# 创建 FTP 源配置文件（在 /root）
```

Create `ftp.repo` in `/root` with the following content:

```ini
[centos]
name=centos
baseurl=ftp://172.128.11.162/centos/
gpgcheck=0
enabled=1
```

**⚠️注意：**

- 确保防火墙关闭，否则节点可能无法访问FTP服务。

#### 生成Elasticsearch配置文件

**操作节点：ansible**

```bash
# 在 ansible 节点生成 Elasticsearch 配置
[root@ansible ~]# rpm -ivh /root/elasticsearch-6.0.0.rpm

# 生成 node1 配置（拷贝到 /root/example）
[root@ansible ~]# cp /etc/elasticsearch/elasticsearch.yml /root/example/elk1.yml
```

Update `/root/example/elk1.yml` with the following content:

```yaml
cluster.name: ELK
node.name: node1
node.master: true
node.data: false
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 172.128.11.217
http.port: 9200
discovery.zen.ping.unicast.hosts: ["node1", "node2", "node3"]
```

```bash
# 生成 node2 配置（在 /root/example）
[root@ansible ~]# cd /root/example
[root@ansible ~/example]# cp elk1.yml elk2.yml
[root@ansible ~/example]# sed -i 's/node.name: node1/node.name: node2/g' elk2.yml
[root@ansible ~/example]# sed -i 's/node.master: true/node.master: false/g' elk2.yml
[root@ansible ~/example]# sed -i 's/node.data: false/node.data: true/g' elk2.yml
[root@ansible ~/example]# sed -i 's/172.128.11.217/172.128.11.170/g' elk2.yml
```

The content of `/root/example/elk2.yml` after modifications:

```yaml
cluster.name: ELK
node.name: node2
node.master: false
node.data: true
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 172.128.11.170
http.port: 9200
discovery.zen.ping.unicast.hosts: ["node1", "node2", "node3"]
```

```bash
# 生成 node3 配置
[root@ansible ~/example]# cp elk1.yml elk3.yml
[root@ansible ~/example]# sed -i 's/node.name: node1/node.name: node3/g' elk3.yml
[root@ansible ~/example]# sed -i 's/node.master: true/node.master: false/g' elk3.yml
[root@ansible ~/example]# sed -i 's/node.data: false/node.data: true/g' elk3.yml
[root@ansible ~/example]# sed -i 's/172.128.11.217/172.128.11.248/g' elk3.yml
```

The content of `/root/example/elk3.yml` after modifications:

```yaml
cluster.name: ELK
node.name: node3
node.master: false
node.data: true
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 172.128.11.248
http.port: 9200
discovery.zen.ping.unicast.hosts: ["node1", "node2", "node3"]
```

#### 生成Kibana配置文件

```bash
# 在 ansible 节点安装并生成 Kibana 配置
[root@ansible ~]# rpm -ivh /root/kibana-6.0.0-x86_64.rpm
[root@ansible ~]# cp /etc/kibana/kibana.yml /root/example/
[root@ansible ~]# cd /root/example
```

Create `/root/example/kibana.yml` with the following content:

```yaml
server.port: 5601
server.host: "172.128.11.217"
elasticsearch.url: "http://172.128.11.217:9200"
```

#### 生成Logstash配置文件

```bash
# 在 ansible 节点安装并生成 Logstash 配置
[root@ansible ~]# rpm -ivh /root/logstash-6.0.0.rpm
[root@ansible ~]# cp /etc/logstash/logstash.yml /root/example/
[root@ansible ~]# cd /root/example
```

Create `/root/example/logstash.yml` with the following content:

```yaml
http.host: "172.128.11.170"
```

Create `/root/example/syslog.conf` with the following content:

```ruby
input {
  file {
    path => "/var/log/messages"
    type => "systemlog"
    start_position => "beginning"
    stat_interval => "3"
  }
}
output {
  if [type] == "systemlog" {
    elasticsearch {
      hosts => ["172.128.11.217:9200"]
      index => "system-log-%{+YYYY.MM.dd}"
    }
  }
}
```

#### 编写Ansible剧本

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
      shell: yum -y install java-1.8.0-*
    - name: 安装Elasticsearch
      shell: rpm -ivh /root/elasticsearch-6.0.0.rpm

- hosts: node1
  remote_user: root
  tasks:
    - name: 配置Elasticsearch
      copy: src=elk1.yml dest=/etc/elasticsearch/elasticsearch.yml
    - name: 重载系统服务
      shell: systemctl daemon-reload
    - name: 启动Elasticsearch
      shell: systemctl start elasticsearch && systemctl enable elasticsearch
    - name: 安装Kibana
      shell: rpm -ivh /root/kibana-6.0.0-x86_64.rpm
    - name: 配置Kibana
      template: src=kibana.yml dest=/etc/kibana/kibana.yml
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
      copy: src=logstash.yml dest=/etc/logstash/logstash.yml
    - name: 配置日志收集
      copy: src=syslog.conf dest=/etc/logstash/conf.d/syslog.conf

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

```bash
# 在 ansible 节点执行剧本
[root@ansible ~]# cd /root/example
[root@ansible ~/example]# ansible-playbook cscc_install.yaml
```

**⚠️注意：**

- 首次执行可能因网络或依赖问题失败，可尝试分阶段执行剧本。
- 若节点服务启动失败，检查日志：`journalctl -u elasticsearch`。

**访问Kibana界面：**  
浏览器打开 <http://172.128.11.217:5601/，若出现Kibana界面则部署成功。>

---

## 常见问题及解决方法

1. **Ansible连接失败**  
   - 检查免密登录配置：`ssh node1` 是否无需密码。
   - 确认所有节点防火墙和Selinux已关闭。

2. **Elasticsearch启动失败**  
   - 检查Java是否安装：`java -version`。
   - 查看日志：`tail -f /var/log/elasticsearch/elk.log`。

3. **Kibana无法访问**  
   - 确认node1的5601端口开放：`netstat -tunlp | grep 5601`。
   - 检查Kibana配置中Elasticsearch地址是否正确。

4. **Logstash日志收集失败**  
   - 确认`/var/log/messages`文件存在且可读。
   - 测试Logstash配置：`/usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/syslog.conf --config.test_and_exit`。
