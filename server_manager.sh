#!/bin/bash
# **********************************************************
# * Author        : andy  
# * Usage         : andy 
# * Create time   : 2025-03-11 17:55
# * Filename      : server_manager.sh
# * Description   : andy
# **********************************************************

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
DEFAULT_IPLIST="iplist"
IPLIST_FILE=""
SSH_TIMEOUT=10
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$SSH_TIMEOUT -o LogLevel=ERROR"
NO_CONFIRM=0

# 打印带颜色的信息
info() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
debug() { echo -e "${BLUE}[DEBUG] $1${NC}"; }

# 打印分隔线
print_separator() {
    local content="$1"
    local min_length=60  # 最小分隔线长度
    local content_length=${#content}
    local separator_length=$((content_length + 4))  # 内容长度加上左右边距
    
    # 如果分隔线长度小于最小长度，使用最小长度
    if [ $separator_length -lt $min_length ]; then
        separator_length=$min_length
    fi
    
    printf "%${separator_length}s\n" | tr " " "-"
}

# 确认执行
confirm() {
    local msg=$1
    if [ "$NO_CONFIRM" -eq 1 ]; then
        return 0
    fi
    
    echo -e "${YELLOW}$msg${NC}"
    read -p "是否继续? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# 检查SSH认证
check_ssh_auth() {
    local ip=$1
    local user=$2
    
    # 尝试使用SSH密钥认证
    ssh $SSH_OPTS "$user@$ip" "exit" &>/dev/null
    return $?
}

# 获取服务器列表
get_server_list() {
    while IFS=' ' read -r name ip comment; do
        # 跳过注释和空行
        [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
        echo "$name,$ip,$comment"
    done < "$IPLIST_FILE"
}

# 处理命令
process_command() {
    local cmd=$1
    local user=$2
    
    # 如果不是root用户，自动添加sudo
    if [ "$user" != "root" ]; then
        # 检查命令是否需要sudo（排除一些不需要sudo的命令）
        local no_sudo_cmds=("ls" "pwd" "whoami" "date" "uptime" "df" "du" "free" "ps" "netstat" "ifconfig" "ip" "cat" "less" "more" "tail" "head" "grep" "find" "echo")
        local need_sudo=1
        
        # 检查命令是否已经包含sudo
        if [[ "$cmd" == sudo* ]]; then
            need_sudo=0
        else
            # 检查是否是基本命令
            for basic_cmd in "${no_sudo_cmds[@]}"; do
                if [[ "$cmd" == "$basic_cmd"* ]]; then
                    need_sudo=0
                    break
                fi
            done
        fi
        
        # 如果需要sudo且命令不以sudo开头，则添加sudo
        if [ $need_sudo -eq 1 ] && [[ "$cmd" != sudo* ]]; then
            cmd="sudo $cmd"
        fi
    fi
    
    echo "$cmd"
}

# 远程执行命令
remote_exec() {
    local server=$1
    local cmd=$2
    local user=$3
    local ip name
    
    # 从服务器信息中提取IP和名称
    IFS=',' read -r name ip _ <<< "$server"
    
    # 检查SSH认证
    if ! check_ssh_auth "$ip" "$user"; then
        error "无法连接到服务器 $ip: 认证失败"
        return 1
    fi
    
    # 处理命令
    local processed_cmd=$(process_command "$cmd" "$user")
    
    # 执行命令并捕获输出
    local output
    if output=$(ssh $SSH_OPTS "$user@$ip" "$processed_cmd" 2>&1); then
        local result="${GREEN}[成功]${NC} $name ($ip): $output"
        echo -e "$result"
        return 0
    else
        local result="${RED}[失败]${NC} $name ($ip): $output"
        echo -e "$result"
        return 1
    fi
}

# 推送文件到远程服务器
push_file() {
    local server=$1
    local src=$2
    local dst=$3
    local user=$4
    local ip name
    
    # 从服务器信息中提取IP和名称
    IFS=',' read -r name ip _ <<< "$server"
    
    # 检查源文件是否存在
    if [ ! -f "$src" ]; then
        error "源文件不存在: $src"
        return 1
    fi
    
    # 检查SSH认证
    if ! check_ssh_auth "$ip" "$user"; then
        error "无法连接到服务器 $ip: 认证失败"
        return 1
    fi
    
    info "正在推送文件 $src 到 $ip:$dst"
    if scp $SSH_OPTS "$src" "$user@$ip:$dst"; then
        # 如果不是root用户，自动修改文件权限
        if [ "$user" != "root" ]; then
            ssh $SSH_OPTS "$user@$ip" "sudo chown $user:$user $dst" &>/dev/null
        fi
        info "在服务器 $ip 上推送成功"
        return 0
    else
        error "推送文件到服务器 $ip 失败"
        return 1
    fi
}

# 从远程服务器拉取文件
pull_file() {
    local server=$1
    local src=$2
    local dst=$3
    local user=$4
    local ip name
    
    # 从服务器信息中提取IP和名称
    IFS=',' read -r name ip _ <<< "$server"
    
    # 检查SSH认证
    if ! check_ssh_auth "$ip" "$user"; then
        error "无法连接到服务器 $ip: 认证失败"
        return 1
    fi
    
    info "正在从 $ip 拉取文件 $src 到 $dst"
    if scp $SSH_OPTS "$user@$ip:$src" "$dst"; then
        info "从服务器 $ip 拉取成功"
        return 0
    else
        error "从服务器 $ip 拉取失败"
        return 1
    fi
}

# 验证参数
validate_param() {
    local param_name=$1
    local param_value=$2
    local param_type=$3
    
    case "$param_type" in
        "number")
            if ! [[ "$param_value" =~ ^[0-9]+$ ]]; then
                error "$param_name 必须是数字"
                return 1
            fi
            ;;
        "file")
            if [ ! -f "$param_value" ]; then
                error "文件不存在: $param_value"
                return 1
            fi
            ;;
        "dir")
            if [ ! -d "$param_value" ]; then
                error "目录不存在: $param_value"
                return 1
            fi
            ;;
        "path")
            # 检查路径是否包含非法字符
            if echo "$param_value" | grep -q '[<>:|?*]'; then
                error "路径包含非法字符: $param_value"
                return 1
            fi
            ;;
        "server")
            # 将通配符转换为正则表达式
            local pattern
            # 如果只有一个下划线，表示精确匹配含下划线的服务器
            if [ "$param_value" = "_" ]; then
                pattern="[^[:space:]]*_[^[:space:]]*"
            else
                # 将 * 转换为 .*，将 _ 保持不变
                pattern=$(echo "$param_value" | sed 's/\*/.*/g')
            fi
            if ! grep -q "^$pattern[[:space:]]" "$IPLIST_FILE" 2>/dev/null; then
                error "没有找到匹配的服务器: $param_value"
                return 1
            fi
            ;;
    esac
    return 0
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    local deps=("ssh" "scp")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "缺少以下依赖:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo
        echo "请安装缺失的依赖:"
        echo "  CentOS/RHEL: sudo yum install -y openssh-clients"
        echo "  Ubuntu/Debian: sudo apt-get install -y openssh-client"
        exit 1
    fi
}

# 加载服务器列表
load_servers() {
    # 如果没有指定IPLIST_FILE，使用默认值
    if [ -z "$IPLIST_FILE" ]; then
        IPLIST_FILE="$DEFAULT_IPLIST"
    fi

    if [ ! -f "$IPLIST_FILE" ]; then
        error "服务器列表文件不存在: $IPLIST_FILE"
        echo "请创建服务器列表文件，格式如下："
        echo "服务器名称 IP地址 备注"
        echo "例如："
        echo "test_0556 114.132.237.103 web_test_0556"
        exit 1
    fi

    # 验证文件格式
    local line_num=0
    while IFS= read -r line; do
        ((line_num++))
        # 跳过注释和空行
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        # 检查每行的格式
        if ! [[ "$line" =~ ^[[:alnum:]_-]+[[:space:]]+[0-9.]+[[:space:]]+[[:alnum:]_-]+ ]]; then
            error "服务器列表文件格式错误，第 $line_num 行:"
            echo "$line"
            echo "正确格式: 服务器名称 IP地址 备注"
            exit 1
        fi
    done < "$IPLIST_FILE"

    info "使用服务器列表文件: $IPLIST_FILE"
}

# 显示服务器列表
list_servers() {
    local total=0
    echo -e "${GREEN}服务器列表:${NC}"
    echo -e "${YELLOW}服务器名称\tIP地址\t\t备注${NC}"
    echo "--------------------------------------------------------"
    while IFS=' ' read -r name ip comment; do
        # 跳过注释和空行
        [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
        echo -e "$name\t$ip\t$comment"
        ((total++))
    done < "$IPLIST_FILE"
    echo "--------------------------------------------------------"
    info "共计 $total 台服务器"
}

# 并发执行命令
parallel_exec() {
    local cmd=$1
    local server_filter=$2
    local arg1=$3
    local arg2=$4
    local user=$5
    local parallel_num=$6
    local total_servers=0
    local processed_servers=0
    local success_servers=0
    local failed_servers=0
    local skipped_servers=0
    local temp_file
    local pattern
    local result=0
    
    # 创建临时文件
    temp_file=$(mktemp)
    get_server_list > "$temp_file"
    
    # 将通配符转换为正则表达式
    if [ -n "$server_filter" ]; then
        if [ "$server_filter" = "_" ]; then
            pattern="[^[:space:]]*_[^[:space:]]*"
        else
            pattern=$(echo "$server_filter" | sed 's/\*/.*/g')
        fi
    fi
    
    # 收集匹配的服务器
    local matched_servers=()
    while IFS=',' read -r server; do
        local name=$(echo "$server" | cut -d',' -f1)
        if [ -z "$server_filter" ] || [[ "$name" =~ ^($pattern)$ ]]; then
            ((total_servers++))
            matched_servers+=("$server")
        fi
    done < "$temp_file"
    
    if [ "$total_servers" -eq 0 ]; then
        error "没有找到匹配的服务器"
        rm -f "$temp_file"
        return 1
    fi
    
    # 显示匹配的服务器列表并确认
    echo -e "${YELLOW}匹配到以下服务器:${NC}"
    for server in "${matched_servers[@]}"; do
        local name=$(echo "$server" | cut -d',' -f1)
        echo "  - $name"
    done
    
    if ! confirm "是否在以上 $total_servers 台服务器上执行操作?"; then
        warn "已取消操作"
        rm -f "$temp_file"
        return 0
    fi
    
    # 显示开始执行信息
    info "开始执行，共计 $total_servers 台服务器，并发数量: $parallel_num"
    case "$cmd" in
        "push")
            info "推送文件: $arg1 -> $arg2"
            ;;
        "pull")
            info "拉取文件: $arg1 -> $arg2"
            ;;
        "exec")
            local processed_cmd=$(process_command "$arg1" "$user")
            info "执行命令: $processed_cmd"
            ;;
    esac
    print_separator
    
    # 创建临时目录用于存储结果
    local tmp_dir=$(mktemp -d)
    local pids=()
    local current_server=0
    
    # 并发执行命令
    for server in "${matched_servers[@]}"; do
        ((current_server++))
        
        # 如果当前运行的进程数达到并发限制，等待一个进程完成
        while [ ${#pids[@]} -ge $parallel_num ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 ${pids[$i]} 2>/dev/null; then
                    unset 'pids[$i]'
                fi
            done
            pids=("${pids[@]}")  # 重新索引数组
            [ ${#pids[@]} -ge $parallel_num ] && sleep 0.1
        done
        
        # 在后台执行命令
        {
            local ret=0
            case "$cmd" in
                "push")
                    if push_file "$server" "$arg1" "$arg2" "$user"; then
                        echo "success" > "$tmp_dir/$current_server"
                    else
                        ret=$?
                        if [ $ret -eq 2 ]; then
                            echo "skipped" > "$tmp_dir/$current_server"
                        else
                            echo "failed" > "$tmp_dir/$current_server"
                        fi
                    fi
                    ;;
                "pull")
                    if pull_file "$server" "$arg1" "$arg2" "$user"; then
                        echo "success" > "$tmp_dir/$current_server"
                    else
                        ret=$?
                        if [ $ret -eq 2 ]; then
                            echo "skipped" > "$tmp_dir/$current_server"
                        else
                            echo "failed" > "$tmp_dir/$current_server"
                        fi
                    fi
                    ;;
                "exec")
                    if remote_exec "$server" "$arg1" "$user"; then
                        echo "success" > "$tmp_dir/$current_server"
                    else
                        ret=$?
                        if [ $ret -eq 2 ]; then
                            echo "skipped" > "$tmp_dir/$current_server"
                        else
                            echo "failed" > "$tmp_dir/$current_server"
                        fi
                    fi
                    ;;
            esac
        } &
        pids+=($!)
    done
    
    # 等待所有进程完成
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    # 统计结果
    for i in $(seq 1 $total_servers); do
        if [ -f "$tmp_dir/$i" ]; then
            case $(cat "$tmp_dir/$i") in
                "success")
                    ((success_servers++))
                    ;;
                "failed")
                    ((failed_servers++))
                    result=1
                    ;;
                "skipped")
                    ((skipped_servers++))
                    ;;
            esac
        fi
    done
    
    # 清理临时文件
    rm -rf "$tmp_dir"
    rm -f "$temp_file"
    
    print_separator
    
    # 显示执行统计
    info "执行完成，处理结果:"
    echo "  总计服务器: $total_servers"
    if [ $success_servers -gt 0 ]; then
        info "  成功执行: $success_servers"
    fi
    if [ $failed_servers -gt 0 ]; then
        error "  执行失败: $failed_servers"
    fi
    if [ $skipped_servers -gt 0 ]; then
        warn "  已跳过: $skipped_servers"
    fi
    
    return $result
}

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 [选项] <命令> [参数] [并发数]

命令:
    -x <昵称> <命令>              在指定服务器上执行命令
    -s <昵称> push <本地文件> <远程路径>   上传文件到指定服务器
    -s <昵称> pull <远程文件> <本地路径>   从指定服务器下载文件
    list                          显示服务器列表

选项:
    -h <文件路径>                指定服务器列表文件（默认: ./iplist）
    -t <秒数>                    设置SSH超时时间（默认: 10）
    -y                           显示匹配服务器并确认后执行
    --help                       显示此帮助信息

并发数:
    最后一个参数可以指定并发数量（默认: 20）

注意:
    - 非root用户会自动添加sudo（除基本命令外）
    - 文件上传后会自动修改所有者为当前用户
    - 服务器匹配规则：
      * _ 单独使用时，匹配包含下划线的服务器
      * _xxx 或 xxx_ 精确匹配前缀或后缀
      * * 匹配任意字符

示例:
    $0 -h iplist.txt -x "web1" "date"     # 使用指定列表文件执行命令
    $0 -x "test_*" "uptime" 10           # 在所有匹配的服务器上执行命令，10个并发
    $0 -s "web1" push file.txt /tmp/      # 上传文件到指定服务器
    $0 -s "web1" pull /tmp/file.txt ./    # 从指定服务器下载文件
EOF
}

# 主函数
main() {
    # 检查依赖
    check_dependencies
    
    # 解析参数
    local server=""
    local command=""
    local command_type=""
    local arg1=""
    local arg2=""
    local user="ops"  # 默认用户为root
    local parallel_num=20  # 默认并发数量为20
    local args=("$@")
    local last_arg="${args[${#args[@]}-1]}"
    
    # 如果最后一个参数是数字，则作为并发数量
    if [[ "$last_arg" =~ ^[0-9]+$ ]]; then
        parallel_num=$last_arg
        set -- "${args[@]:0:${#args[@]}-1}"  # 移除最后一个参数
    fi
    
    # 检查第一个参数是否为 -h
    if [ "$1" = "-h" ]; then
        if [ -z "$2" ]; then
            error "缺少参数: 服务器列表文件路径"
            exit 1
        fi
        IPLIST_FILE="$2"
        shift 2
    fi
    
    # 加载服务器列表
    load_servers
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            -t)
                if [ -z "$2" ]; then
                    error "缺少参数: 超时时间"
                    exit 1
                fi
                validate_param "超时时间" "$2" "number" || exit 1
                SSH_TIMEOUT="$2"
                shift 2 || { error "参数解析错误"; exit 1; }
                ;;
            -y)
                NO_CONFIRM=1
                shift
                ;;
            -x)
                if [ -z "$2" ] || [ -z "$3" ]; then
                    error "用法: $0 -x <昵称> <命令> [并发数]"
                    exit 1
                fi
                command_type="exec"
                server="$2"
                command="$3"
                shift 3 || { error "参数解析错误"; exit 1; }
                ;;
            -s)
                if [ -z "$2" ] || [ -z "$3" ]; then
                    error "用法: $0 -s <昵称> <push|pull> [参数...] [并发数]"
                    exit 1
                fi
                server="$2"
                case "$3" in
                    push)
                        if [ -z "$4" ] || [ -z "$5" ]; then
                            error "用法: $0 -s <昵称> push <本地文件> <远程路径> [并发数]"
                            exit 1
                        fi
                        command_type="push"
                        arg1="$4"
                        arg2="$5"
                        shift 5 || { error "参数解析错误"; exit 1; }
                        ;;
                    pull)
                        if [ -z "$4" ] || [ -z "$5" ]; then
                            error "用法: $0 -s <昵称> pull <远程文件> <本地路径> [并发数]"
                            exit 1
                        fi
                        command_type="pull"
                        arg1="$4"
                        arg2="$5"
                        shift 5 || { error "参数解析错误"; exit 1; }
                        ;;
                    *)
                        error "未知操作: $3"
                        show_help
                        exit 1
                        ;;
                esac
                ;;
            list)
                command_type="list"
                shift
                ;;
            *)
                error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 如果指定了服务器，验证其存在性
    if [ -n "$server" ]; then
        validate_param "服务器" "$server" "server" || exit 1
    fi
    
    # 检查当前用户是否为root
    if [ "$(id -u)" != "0" ]; then
        user="$(whoami)"
    fi
    
    # 执行命令
    case "$command_type" in
        list)
            list_servers
            ;;
        push)
            validate_param "本地文件" "$arg1" "file" || exit 1
            validate_param "远程路径" "$arg2" "path" || exit 1
            parallel_exec "push" "$server" "$arg1" "$arg2" "$user" "$parallel_num"
            ;;
        pull)
            validate_param "远程文件" "$arg1" "path" || exit 1
            mkdir -p "$(dirname "$arg2")" || { error "无法创建目录: $(dirname "$arg2")"; exit 1; }
            parallel_exec "pull" "$server" "$arg1" "$arg2" "$user" "$parallel_num"
            ;;
        exec)
            if [ -z "$command" ]; then
                error "命令不能为空"
                exit 1
            fi
            parallel_exec "exec" "$server" "$command" "" "$user" "$parallel_num"
            ;;
        *)
            error "请指定要执行的操作"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数，捕获错误
if ! main "$@"; then
    error "脚本执行失败"
    exit 1
fi 
