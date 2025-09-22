#!/bin/bash

# IP列表（改为自己的服务器地址）
IPLIST="
10.0.0.6
10.0.0.7
10.0.0.8
10.0.0.9
"

# 安装依赖
rpm -q sshpass &> /dev/null || yum install sshpass -y &> /dev/null
[ -f /root/.ssh/id_rsa ] || ssh-keygen -f /root/.ssh/id_rsa -P ''

# 配置密码（改为自己的服务器密码）
export SSHPASS=waluna

# 配置互信
for IP in $IPLIST;do
    sshpass -e ssh-copy-id -o StrictHostKeyChecking=no $IP
done

# 拷贝密钥
for HOST in $IPLIST;do
     scp -o StrictHostKeyChecking=no /root/.ssh/id_rsa $HOST:/root/.ssh/
done