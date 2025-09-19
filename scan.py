import socket
import threading
import requests
import logging
import datetime

# 定义要扫描的端口列表
ports = [22, 16333, 26333, 3389, 3306, 2433, 16888]

# 定义企业微信Webhook链接

# 配置日志记录
logging.basicConfig(filename='scan.log', level=logging.INFO,
                    format='%(asctime)s [%(levelname)s] %(message)s')

# 发送企业微信通知的函数
def send_notification(nickname, ip, port):
    #url = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=cc5f4534-f2c9-4d6b-8a7d"  # 这里就是群机器人的Webhook地址 换成自己的地址
    headers = {"Content-Type": "application/json"} # http数据头，类型为json
    data = {
        "msgtype": "text",
        "text": {
            "content": f"IP地址：{ip}，端口：{port} 开放",
            "content": f'[{datetime.datetime.now()}] {nickname}, IP地址：{ip}，端口：{port} 处于开放状态',
            "mentioned_list": "test",
        }
    }
    response = requests.post(url, headers=headers, json=data) # 利用requests库发送post请求
    if response.status_code != 200:
        logging.error(f'发送通知失败：{response.text}')

# 扫描端口的函数
def scan_port(nickname, ip, port):
    try:
        # 创建TCP套接字
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)

        # 连接到IP地址和端口
        result = sock.connect_ex((ip, port))
        if result == 0:
            logging.info(f'[{datetime.datetime.now()}] {nickname}, IP地址: {ip} 的端口: {port} 处于开放状态')
            # 发送企业微信通知
            send_notification(nickname, ip, port)
        sock.close()
    except Exception as e:
        logging.error(f'扫描端口异常：{e}')

# 读取IP地址列表文件
with open('ip.txt', 'r') as file:
    lines = file.read().splitlines()

# 解析IP地址和昵称
ip_list = []
for line in lines:
    parts = line.split()
    if len(parts) == 2:
        ip_list.append((parts[0], parts[1]))

# 并发扫描IP地址和端口
for ip, nickname in ip_list:
    logging.info(f'[{datetime.datetime.now()}] 正在扫描 {nickname} (IP地址：{ip})')
    for port in ports:
        # 创建并发线程进行扫描
        threading.Thread(target=scan_port, args=(nickname, ip, port)).start()
