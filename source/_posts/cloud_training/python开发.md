# OpenStack API 编程基础与实战指南

## 1. 脚本详细分析

这段脚本是一个典型的 OpenStack REST API 交互案例，主要使用了 Python 的 `requests` 库来完成 Keystone（身份认证服务）的用户管理操作。

### 1.1 关键流程拆解

1. **认证 (Authentication)**：
    * 脚本通过 `headers` 中的 `X-Auth-token` 进行身份校验。
    * **技巧**：在 OpenStack 环境中，通常先通过 `source admin-openrc.sh` 加载环境变量，然后使用 `openstack token issue` 获取临时令牌。
2. **资源发现与清理 (Read & Delete)**：
    * 首先 `GET /v3/users` 获取当前所有用户的列表。
    * 通过循环匹配 `name == 'user_demo'`。
    * 获取到 `id` 后，通过 `DELETE /v3/users/{id}` 删除旧用户。这保证了后续创建操作不会因为“用户已存在”而报错，实现了脚本的可重复执行性（幂等性）。
3. **资源创建 (Create)**：
    * 构造符合 API 规范的 JSON 数据包 `{'user': {...}}`。
    * 使用 `POST /v3/users` 发送请求。
4. **数据持久化**：
    * 将 API 返回的响应（包含新用户的 ID、项目归属等敏感/重要信息）保存为本地 `.json` 文件，便于后续自动化流程调用。

---

## 2. OpenStack API 编程核心基础与技巧

### 2.1 理解 RESTful 设计

OpenStack 的每个服务（Nova, Neutron, Cinder 等）都暴露了一套标准接口：

* **URL 结构**：`http://{IP}:{Port}/{Version}/{Resource}`。
* **动作映射**：
  * `GET`: 获取列表或详情。
  * `POST`: 创建新资源。
  * `DELETE`: 销毁资源。
  * `PUT/PATCH`: 更新资源配置。

### 2.2 编程技巧

* **ID 为王**：虽然我们在 CLI 中常用“名称”操作，但 **API 内部几乎全部使用 UUID (ID)**。编写脚本时，第一步往往是“按名称查 ID”。
* **JSON 序列化**：发送 `POST` 请求时，必须使用 `json.dumps(data)` 将字典转为字符串，并确保 `Header` 中包含 `'Content-Type': 'application/json'`。
* **状态码检查**：
  * `201 Created`: 创建成功。
  * `204 No Content`: 删除成功。
  * `401 Unauthorized`: Token 失效，需重新获取。
  * `409 Conflict`: 资源冲突（如重名）。

---

## 3. 离线环境下的快速实现方案

在无法连接外网、没有完整文档的机房环境下，可以通过以下“黑科技”快速写出脚本：

### 3.1 终极武器：`--debug` 模式

这是最实用的技巧。如果你不知道某个操作的 API URL 或 JSON 格式，直接运行对应的 OpenStack 命令行工具并加上 `--debug`：

```bash
openstack user create --password 1DY@2022 user_demo --debug
```

**观察输出**：

* 你会看到 `curl -g -i -X POST ...` 开头的行。
* 这行会显示完整的 **URL**、**Headers** 以及 **Request Body (JSON 内容)**。
* **直接“照猫画虎”拷贝到 Python 代码里即可。**

### 3.2 利用 Python 的交互式探索

在 Python 终端利用 `dir()` 和 `help()`：

```python
import requests
resp = requests.get('...')
print(dir(resp))          # 查看响应对象有哪些方法
print(resp.json())        # 快速查看数据结构
```

### 3.3 零依赖方案：`urllib`

如果环境中没有安装 `requests` 库（虽然现代 OpenStack 节点通常自带），可以使用标准库 `urllib.request`。
**优点**：无需外部依赖，任何 Python 环境都能跑。
**示例代码片段**：

```python
import urllib.request, json

req = urllib.request.Request(
    url='http://controller:5000/v3/users',
    data=json.dumps(data).encode(),
    headers=headers,
    method='POST'
)
with urllib.request.urlopen(req) as r:
    print(r.read().decode())
```

### 3.4 自动化 Token 获取

不需要每次手动改脚本里的 Token，可以利用 Python 读取加载后的环境变量：

```python
import os
# 先在 Shell 执行 source admin-openrc.sh
token = os.popen("openstack token issue -c id -f value").read().strip()
headers = {'X-Auth-Token': token, 'Content-Type': 'application/json'}
```
