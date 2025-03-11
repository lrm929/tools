# Server Manager
![image](https://github.com/user-attachments/assets/e2b88438-3c00-4c57-98ed-0bceb8f82f6d)


一个用于批量管理服务器的 Shell 脚本工具，支持批量执行命令、文件上传下载等功能。

## 特性

- 支持批量执行命令
- 支持文件上传/下载
- 支持服务器名称通配符匹配
- 支持并发执行（默认20并发）
- 自动处理非root用户权限（自动添加sudo）
- 文件上传后自动修改所有者
- 支持SSH密钥认证
- 彩色输出显示执行结果
- 动态分隔线适应输出内容

## 安装

1. 克隆仓库：
```bash
git clone https://github.com/lrm929/tools.git
cd server-manager
```

2. 添加执行权限：
```bash
chmod +x server_manager.sh
```

3. 创建服务器列表文件：
```bash
# 创建默认的iplist文件
touch iplist
```

## 配置

### 服务器列表文件格式

服务器列表文件（默认为 `iplist`）的格式如下：
```
服务器名称 IP地址 备注
```

示例：
```
web1 192.168.1.100 web_server_1
web2 192.168.1.101 web_server_2
db1  192.168.1.102 database_1
```

### SSH 配置

- 脚本使用SSH密钥认证，请确保已经配置好SSH密钥
- 默认SSH超时时间为10秒
- 默认禁用了SSH主机密钥检查，适合内网环境使用

## 使用方法

### 基本命令格式

```bash
./server_manager.sh [选项] <命令> [参数] [并发数]
```

### 命令列表

1. 执行命令：
```bash
# 在所有匹配的服务器上执行命令
./server_manager.sh -x "web*" "date"

# 指定10个并发执行
./server_manager.sh -x "web*" "uptime" 10
```

2. 上传文件：
```bash
# 上传文件到指定服务器
./server_manager.sh -s "web*" push local.txt /tmp/

# 指定5个并发上传
./server_manager.sh -s "web*" push local.txt /tmp/ 5
```

3. 下载文件：
```bash
# 从服务器下载文件
./server_manager.sh -s "web*" pull /tmp/remote.txt ./

# 指定3个并发下载
./server_manager.sh -s "web*" pull /tmp/remote.txt ./ 3
```

4. 显示服务器列表：
```bash
./server_manager.sh list
```

### 选项说明

- `-h <文件路径>`: 指定服务器列表文件（默认: ./iplist）
- `-t <秒数>`: 设置SSH超时时间（默认: 10）
- `-y`: 显示匹配服务器并确认后执行
- `--help`: 显示帮助信息

### 服务器匹配规则

- `*`: 匹配任意字符
  - 例：`web*` 匹配所有以web开头的服务器
- `_`: 单独使用时，匹配包含下划线的服务器
  - 例：`_` 匹配所有包含下划线的服务器
- `_xxx` 或 `xxx_`: 精确匹配前缀或后缀
  - 例：`web_` 匹配所有以web_开头的服务器

### 权限处理

- 非root用户执行时会自动添加sudo（除基本命令外）
- 文件上传后会自动修改所有者为当前用户
- 基本命令（如：ls, date, pwd等）不会添加sudo

## 依赖

- OpenSSH Client (`ssh`, `scp`)

### 安装依赖

CentOS/RHEL:
```bash
sudo yum install -y openssh-clients
```

Ubuntu/Debian:
```bash
sudo apt-get install -y openssh-client
```

## 注意事项

1. 确保已经配置好SSH密钥认证
2. 确保目标服务器的用户有相应的sudo权限（如果需要）
3. 大量并发操作时注意控制并发数量
4. 建议在内网环境使用，因为禁用了SSH主机密钥检查

## 许可证

[MIT License](LICENSE)

## 贡献

欢迎提交 Issue 和 Pull Request！
