#!/bin/bash

# 在文件开头添加
export PARALLEL_HOME="/tmp/.parallel"
mkdir -p "$PARALLEL_HOME"

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
DEFAULT_IPLIST="iplist.txt"
IPLIST_FILE=""
MAX_PARALLEL=10
SSH_TIMEOUT=10
DEFAULT_USER="root"
TEMP_DIR="/tmp/server_manager"
DEFAULT_SSH_PASSWORD="" # 默认SSH密码，可以通过环境变量设置：export DEFAULT_SSH_PASSWORD="your_password"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT"

# 导出所有函数，使其在parallel中可用
export -f info warn error debug get_md5 remote_exec push_file pull_file get_server_list

# 设置SSH密码环境变量
read_password() {
    if [ -z "$SSHPASS" ]; then
        read -s -p "请输入SSH密码: " SSHPASS
        echo
        export SSHPASS
    fi
}

# 初始化parallel
init_parallel() {
    # 如果bibtex文件不存在，创建它
    if [ ! -f "$PARALLEL_HOME/will-cite" ]; then
        parallel --bibtex < /dev/null
    fi
}

# 打印带颜色的信息
info() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
debug() { echo -e "${BLUE}[DEBUG] $1${NC}"; }

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 [选项] <命令> [参数]

命令:
    push <本地文件> <远程路径>    上传文件到远程服务器
    pull <远程文件> <本地路径>    从远程服务器下载文件
    exec <命令>                   在远程服务器执行命令
    list                         显示服务器列表

选项:
    -h, --hosts <文件路径>       指定服务器列表文件（默认: ./iplist.txt）
    -s, --server <昵称>          指定单个服务器执行
    -p, --parallel <数量>        设置并行执行数量（默认: 10）
    -t, --timeout <秒数>         设置SSH超时时间（默认: 10）
    -u, --user <用户名>          覆盖配置文件中的用户名
    --help                       显示此帮助信息

示例:
    $0 push local.txt /tmp/                    # 使用默认iplist文件
    $0 -h other.txt push local.txt /tmp/       # 使用指定的服务器列表文件
    $0 -s web1 -h test.txt exec "df -h"       # 指定服务器列表和单台服务器
    $0 -h /path/to/prod.txt pull /var/log/syslog ./logs/  # 使用绝对路径的列表文件

iplist.txt 格式:
    昵称 IP地址 端口 用户名 备注
    例如: web1 192.168.1.100 22 admin 主站服务器
EOF
}

# 检查依赖
check_dependencies() {
    local deps=("sshpass" "parallel" "md5sum")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "缺少依赖: $dep"
            exit 1
        fi
    done
}

# 加载服务器列表
load_servers() {
    # 如果没有指定IPLIST_FILE，使用默认值
    if [ -z "$IPLIST_FILE" ]; then
        IPLIST_FILE="$DEFAULT_IPLIST"
    fi

    if [ ! -f "$IPLIST_FILE" ]; then
        error "服务器列表文件不存在: $IPLIST_FILE"
        exit 1
    fi

    info "使用服务器列表文件: $IPLIST_FILE"
}

# 获取服务器列表
get_server_list() {
    while IFS=' ' read -r nickname ip port username comment; do
        # 跳过注释和空行
        [[ "$nickname" =~ ^#.*$ || -z "$nickname" ]] && continue
        echo "$nickname,$ip,$port,$username,$comment"
    done < "$IPLIST_FILE"
}

# 获取文件MD5
get_md5() {
    md5sum "$1" | cut -d' ' -f1
}

# 检查SSH认证
check_ssh_auth() {
    local ip=$1
    local port=$2
    local user=$3
    
    # 尝试使用SSH密钥认证
    ssh $SSH_OPTS -p "$port" "$user@$ip" "exit" &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    fi
    
    # 如果密钥认证失败且设置了默认密码，尝试密码认证
    if [ -n "$DEFAULT_SSH_PASSWORD" ]; then
        SSHPASS="$DEFAULT_SSH_PASSWORD" sshpass -e ssh $SSH_OPTS -p "$port" "$user@$ip" "exit" &>/dev/null
        if [ $? -eq 0 ]; then
            export SSHPASS="$DEFAULT_SSH_PASSWORD"
            return 0
        fi
    fi
    
    return 1
}

# 远程执行命令
remote_exec() {
    local server=$1
    local cmd=$2
    local ip port user
    
    # 从服务器信息中提取IP、端口和用户名
    IFS=',' read -r _ ip port user _ <<< "$server"
    [ -z "$user" ] && user="$DEFAULT_USER"
    
    # 检查SSH认证
    if ! check_ssh_auth "$ip" "$port" "$user"; then
        error "无法连接到服务器 $ip: 认证失败"
        return 1
    fi
    
    info "正在执行命令: $cmd 在服务器 $ip"
    if [ -n "$SSHPASS" ]; then
        SSHPASS="$SSHPASS" sshpass -e ssh $SSH_OPTS -p "$port" "$user@$ip" "$cmd"
    else
        ssh $SSH_OPTS -p "$port" "$user@$ip" "$cmd"
    fi
}

# 执行命令的主函数
exec_command() {
    local cmd=$1
    local server_filter=$2
    local parallel_mode=$3
    
    if [ "$parallel_mode" = "true" ]; then
        # 并行执行
        if [ -n "$server_filter" ]; then
            get_server_list | grep "$server_filter" | parallel -j "$MAX_PARALLEL" remote_exec {} "$cmd"
        else
            get_server_list | parallel -j "$MAX_PARALLEL" remote_exec {} "$cmd"
        fi
    else
        # 串行执行
        get_server_list | while IFS= read -r server; do
            if [ -n "$server_filter" ] && ! echo "$server" | grep -q "$server_filter"; then
                continue
            fi
            remote_exec "$server" "$cmd"
        done
    fi
}

# 推送文件到远程服务器
push_file() {
    local server=$1
    local src=$2
    local dst=$3
    local ip port user
    
    # 从服务器信息中提取IP、端口和用户名
    IFS=',' read -r nickname ip port user _ <<< "$server"
    [ -z "$user" ] && user="$DEFAULT_USER"
    
    # 检查源文件是否存在
    if [ ! -f "$src" ]; then
        error "源文件不存在: $src"
        return 1
    fi
    
    # 检查SSH认证
    if ! check_ssh_auth "$ip" "$port" "$user"; then
        error "无法连接到服务器 $ip: 认证失败"
        return 1
    fi
    
    info "正在推送文件 $src 到 $ip:$dst"
    
    # 计算本地文件MD5
    local md5_local=$(get_md5 "$src")
    
    # 推送文件
    if [ -n "$SSHPASS" ]; then
        SSHPASS="$SSHPASS" sshpass -e scp $SSH_OPTS -P "$port" "$src" "$user@$ip:$dst"
    else
        scp $SSH_OPTS -P "$port" "$src" "$user@$ip:$dst"
    fi
    
    # 验证MD5
    local md5_remote=$(remote_exec "$server" "md5sum $dst" | cut -d' ' -f1)
    if [ "$md5_local" = "$md5_remote" ]; then
        info "文件验证成功: $nickname - $src"
    else
        error "文件验证失败: $nickname - $src"
        return 1
    fi
}

# 从远程服务器拉取文件
pull_file() {
    local server=$1
    local src=$2
    local dst=$3
    local ip port user
    
    # 从服务器信息中提取IP、端口和用户名
    IFS=',' read -r nickname ip port user _ <<< "$server"
    [ -z "$user" ] && user="$DEFAULT_USER"
    
    # 检查SSH认证
    if ! check_ssh_auth "$ip" "$port" "$user"; then
        error "无法连接到服务器 $ip: 认证失败"
        return 1
    fi
    
    info "正在从 $ip 拉取文件 $src 到 $dst"
    
    # 获取远程文件MD5
    local md5_remote=$(remote_exec "$server" "md5sum $src" | cut -d' ' -f1)
    
    # 拉取文件
    if [ -n "$SSHPASS" ]; then
        SSHPASS="$SSHPASS" sshpass -e scp $SSH_OPTS -P "$port" "$user@$ip:$src" "$dst"
    else
        scp $SSH_OPTS -P "$port" "$user@$ip:$src" "$dst"
    fi
    
    # 验证MD5
    local md5_local=$(get_md5 "$dst")
    if [ "$md5_local" = "$md5_remote" ]; then
        info "文件验证成功: $nickname - $src"
    else
        error "文件验证失败: $nickname - $src"
        return 1
    fi
}

# 并行执行命令
parallel_exec() {
    local cmd=$1
    local server_filter=$2
    local arg1=$3
    local arg2=$4
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 创建任务列表
    get_server_list | while IFS=',' read -r nickname ip port username comment; do
        # 如果指定了服务器，只处理匹配的服务器
        if [ -n "$server_filter" ] && [ "$nickname" != "$server_filter" ]; then
            continue
        fi
        
        # 如果通过命令行指定了用户名，使用命令行指定的用户名
        local final_username=${DEFAULT_USER:-$username}
        echo "$nickname,$ip,$port,$final_username,$comment" >> "$TEMP_DIR/tasks"
    done
    
    # 并行执行
    if [ -f "$TEMP_DIR/tasks" ]; then
        case "$cmd" in
            "push")
                cat "$TEMP_DIR/tasks" | parallel -j "$MAX_PARALLEL" push_file {} "$arg1" "$arg2"
                ;;
            "pull")
                cat "$TEMP_DIR/tasks" | parallel -j "$MAX_PARALLEL" pull_file {} "$arg1" "$arg2"
                ;;
            "exec")
                cat "$TEMP_DIR/tasks" | parallel -j "$MAX_PARALLEL" remote_exec {} "$arg1"
                ;;
        esac
    fi
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
}

# 显示服务器列表
list_servers() {
    echo -e "${GREEN}服务器列表:${NC}"
    echo -e "${YELLOW}昵称\tIP地址\t\t端口\t用户名\t备注${NC}"
    echo "--------------------------------------------------------"
    while IFS=' ' read -r nickname ip port username comment; do
        # 跳过注释和空行
        [[ "$nickname" =~ ^#.*$ || -z "$nickname" ]] && continue
        echo -e "$nickname\t$ip\t$port\t$username\t$comment"
    done < "$IPLIST_FILE"
}

# 主函数
main() {
    # 初始化parallel
    init_parallel

    # 检查依赖
    check_dependencies
    
    # 解析参数
    local server=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            -h|--hosts)
                IPLIST_FILE="$2"
                shift 2
                ;;
            -s|--server)
                server="$2"
                shift 2
                ;;
            -p|--parallel)
                MAX_PARALLEL="$2"
                shift 2
                ;;
            -t|--timeout)
                SSH_TIMEOUT="$2"
                shift 2
                ;;
            -u|--user)
                DEFAULT_USER="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done
    
    # 检查命令
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi
    
    # 加载服务器列表
    load_servers
    
    # 执行命令
    case "$1" in
        list)
            list_servers
            ;;
        push)
            if [ $# -ne 3 ]; then
                error "用法: $0 push <本地文件> <远程路径>"
                exit 1
            fi
            parallel_exec "push" "$server" "$2" "$3"
            ;;
        pull)
            if [ $# -ne 3 ]; then
                error "用法: $0 pull <远程文件> <本地路径>"
                exit 1
            fi
            parallel_exec "pull" "$server" "$2" "$3"
            ;;
        exec)
            if [ $# -ne 2 ]; then
                error "用法: $0 exec <命令>"
                exit 1
            fi
            parallel_exec "exec" "$server" "$2"
            ;;
        *)
            error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 
