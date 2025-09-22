#!/bin/bash
#Date：2018-5-20 13:14:00
#Author Blog:
#	https://www.yangxingzhen.com
#	https://www.i7ti.cn
#Author WeChat：
#	微信公众号：小柒博客
#Author mirrors site:
#	https://mirrors.yangxingzhen.com
#About the Author
#	BY：YangXingZhen
#	Mail：xingzhen.yang@yangxingzhen.com
#	QQ：675583110
#Selete System info

SYS_VERSION=$(cat /etc/redhat-release)
HOSTNAME=$(hostname)
IPADDR=$(ifconfig |awk '/cast/ {print $2}'|sed 's/addr://')
CPU_Model=$(awk -F: '/name/ {print $NF}' /proc/cpuinfo |uniq)
CPU_NUM=$(grep -c 'processor' /proc/cpuinfo)
#DISK_INFO=$(fdisk -l |grep Disk |awk '/dev/ {print "Disk: " $2,$3,$4}'|sed 's/,//')
DISK_INFO=$(df -h |grep "^/dev/"|awk '{print "磁盘容量:",$1,$2}')
DISK_Avail=$(df -h |grep "^/dev/"|awk '{print "磁盘可用容量:",$1,$4}')
MEM_INFO=$(free -m |awk '/Mem/ {print "内存容量:",$2"M"}')
MEM_Avail=$(free -m |awk '/Mem/ {print "内存可用容量:",$7"M"}')
LOAD_INFO=$(uptime |awk '{print "CPU负载: "$(NF-2),$(NF-1),$NF}'|sed 's/\,//g')

echo -e "\033[32m-----------------------------------------------\033[0m"
echo -e "\033[32m系统信息>> \033[0m"				     
echo -e "\033[32m操作系统: ${SYS_VERSION} \033[0m"		     
echo -e "\033[32m主机名: ${HOSTNAME} \033[0m"			     
echo -e "\033[32m内网IP: ${IPADDR} \033[0m"		  	     
echo -e "\033[32mCPU型号:${CPU_Model} \033[0m"			     
echo -e "\033[32mCPU核数: ${CPU_NUM} \033[0m"			     
echo -e "\033[32m${DISK_INFO} \033[0m"				     
echo -e "\033[32m${DISK_Avail} \033[0m"			     
echo -e "\033[32m${MEM_INFO} \033[0m"				     
echo -e "\033[32m${MEM_Avail} \033[0m"				     
echo -e "\033[32m${LOAD_INFO} \033[0m"				     
echo -e "\033[32m-----------------------------------------------\033[0m"
