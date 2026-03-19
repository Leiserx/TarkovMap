#!/bin/bash

###########################################
# 塔科夫地图工具 WebSocket 服务器部署脚本
# 支持 Ubuntu/Debian/CentOS/RHEL
###########################################

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统版本"
        exit 1
    fi
    print_info "检测到操作系统: $OS $VERSION"
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "请使用 root 权限运行此脚本 (sudo ./deploy.sh)"
        exit 1
    fi
}

# 安装 Node.js
install_nodejs() {
    print_info "检查 Node.js 安装状态..."
    
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v)
        print_info "Node.js 已安装: $NODE_VERSION"
        return
    fi
    
    print_info "正在安装 Node.js..."
    
    case $OS in
        ubuntu|debian)
            curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
            apt-get install -y nodejs
            ;;
        centos|rhel|fedora)
            curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
            yum install -y nodejs
            ;;
        *)
            print_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    print_info "Node.js 安装完成: $(node -v)"
}

# 创建服务用户
create_service_user() {
    print_info "创建服务用户..."
    
    if id "tkf-server" &>/dev/null; then
        print_info "用户 tkf-server 已存在"
    else
        useradd -r -s /bin/false tkf-server
        print_info "用户 tkf-server 创建成功"
    fi
}

# 设置部署目录
setup_deployment() {
    DEPLOY_DIR="/opt/tkf-websocket-server"
    
    print_info "设置部署目录: $DEPLOY_DIR"
    
    # 创建目录
    mkdir -p $DEPLOY_DIR
    
    # 复制文件
    print_info "复制服务器文件..."
    cp -r $(dirname "$0")/* $DEPLOY_DIR/
    
    # 安装依赖
    print_info "安装 npm 依赖..."
    cd $DEPLOY_DIR
    npm install --production
    
    # 设置权限
    chown -R tkf-server:tkf-server $DEPLOY_DIR
    chmod 755 $DEPLOY_DIR
    
    print_info "部署文件设置完成"
}

# 配置环境变量
configure_environment() {
    print_info "配置环境变量..."
    
    # 读取用户输入或使用默认值
    read -p "请输入 WebSocket 服务器端口 [默认: 8080]: " PORT
    PORT=${PORT:-8080}
    
    # 创建环境配置文件
    cat > /opt/tkf-websocket-server/.env << EOF
# WebSocket 服务器配置
PORT=$PORT
NODE_ENV=production
EOF
    
    chmod 600 /opt/tkf-websocket-server/.env
    chown tkf-server:tkf-server /opt/tkf-websocket-server/.env
    
    print_info "环境配置完成 (端口: $PORT)"
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        # Ubuntu/Debian UFW
        ufw allow $PORT/tcp
        print_info "UFW 防火墙规则已添加"
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL firewalld
        firewall-cmd --permanent --add-port=$PORT/tcp
        firewall-cmd --reload
        print_info "firewalld 防火墙规则已添加"
    else
        print_warning "未检测到防火墙，请手动开放端口 $PORT"
    fi
}

# 创建 systemd 服务
create_systemd_service() {
    print_info "创建 systemd 服务..."
    
    cat > /etc/systemd/system/tkf-websocket.service << 'EOF'
[Unit]
Description=Tarkov Map Tool WebSocket Server
Documentation=https://github.com/your-repo
After=network.target

[Service]
Type=simple
User=tkf-server
WorkingDirectory=/opt/tkf-websocket-server
EnvironmentFile=/opt/tkf-websocket-server/.env
ExecStart=/usr/bin/node /opt/tkf-websocket-server/websocket-server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tkf-websocket

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/tkf-websocket-server

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd 配置
    systemctl daemon-reload
    
    print_info "systemd 服务创建完成"
}

# 启动服务
start_service() {
    print_info "启动 WebSocket 服务..."
    
    # 启用开机自启
    systemctl enable tkf-websocket.service
    
    # 启动服务
    systemctl start tkf-websocket.service
    
    # 等待服务启动
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet tkf-websocket.service; then
        print_info "服务启动成功！"
        systemctl status tkf-websocket.service --no-pager
    else
        print_error "服务启动失败！"
        journalctl -u tkf-websocket.service -n 50 --no-pager
        exit 1
    fi
}

# 显示部署信息
show_deployment_info() {
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo "=========================================="
    echo "  🎉 部署完成！"
    echo "=========================================="
    echo ""
    echo "服务器地址: $SERVER_IP"
    echo "服务器端口: $PORT"
    echo ""
    echo "客户端连接配置:"
    echo "  - 服务器地址: $SERVER_IP"
    echo "  - 端口: $PORT"
    echo ""
    echo "常用命令:"
    echo "  - 查看服务状态: sudo systemctl status tkf-websocket"
    echo "  - 查看日志:     sudo journalctl -u tkf-websocket -f"
    echo "  - 重启服务:     sudo systemctl restart tkf-websocket"
    echo "  - 停止服务:     sudo systemctl stop tkf-websocket"
    echo "  - 卸载服务:     sudo bash /opt/tkf-websocket-server/uninstall.sh"
    echo ""
    echo "=========================================="
}

# 创建卸载脚本
create_uninstall_script() {
    print_info "创建卸载脚本..."
    
    cat > /opt/tkf-websocket-server/uninstall.sh << 'EOF'
#!/bin/bash

echo "正在卸载 WebSocket 服务器..."

# 停止并禁用服务
systemctl stop tkf-websocket.service
systemctl disable tkf-websocket.service

# 删除服务文件
rm -f /etc/systemd/system/tkf-websocket.service
systemctl daemon-reload

# 删除部署目录
rm -rf /opt/tkf-websocket-server

# 删除用户（可选）
read -p "是否删除服务用户 tkf-server? [y/N]: " DELETE_USER
if [[ "$DELETE_USER" =~ ^[Yy]$ ]]; then
    userdel tkf-server
    echo "用户已删除"
fi

echo "卸载完成！"
EOF
    
    chmod +x /opt/tkf-websocket-server/uninstall.sh
}

# 主函数
main() {
    echo ""
    echo "=========================================="
    echo "  塔科夫地图工具 WebSocket 服务器"
    echo "  一键部署脚本"
    echo "=========================================="
    echo ""
    
    check_root
    detect_os
    install_nodejs
    create_service_user
    setup_deployment
    configure_environment
    configure_firewall
    create_systemd_service
    create_uninstall_script
    start_service
    show_deployment_info
    
    print_info "部署完成！"
}

# 运行主函数
main

