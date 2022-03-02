#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi：${plain} Chạy tập lệnh dưới quyền Root！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}Phiên bản không tồn tại！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
  arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
  arch="arm64"
else
  arch="amd64"
  echo -e "${red}Không phát hiện được giản đồ, hãy sử dụng lược đồ mặc định: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "Phần mềm này không hỗ trợ hệ thống 32-bit(x86), vui lòng sử dụng hệ thống 64-bit (x86_64)!"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Vui lòng sử dụng CentOS 7 trở lên ！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Vui lòng sử dụng Ubuntu 16 trở lên ！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Vui lòng sử dụng Debian 8 trở lên ！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl tar crontabs socat -y
    else
        apt install wget curl tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/soga.service ]]; then
        return 2
    fi
    temp=$(systemctl status soga | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_acme() {
    curl https://get.acme.sh | sh
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
}

install_soga() {
    cd /usr/local/
    if [[ -e /usr/local/soga/ ]]; then
        rm /usr/local/soga/ -rf
    fi

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/vaxilu/soga/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Không phát hiện được phiên bản soga, có thể đã vượt quá giới hạn API Github, vui lòng thử lại sau hoặc chỉ định phiên bản soga để cài đặt theo cách thủ công ${plain}"
            exit 1
        fi
        echo -e "soga phiên bản mới nhất được phát hiện ：${last_version}, bắt đầu cài đặt "
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz https://github.com/vaxilu/soga/releases/download/${last_version}/soga-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Không thể tải xuống soga, vui lòng đảm bảo máy chủ của bạn có thể tải xuống tệp Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/vaxilu/soga/releases/download/${last_version}/soga-linux-${arch}.tar.gz"
        echo -e "Bắt đầu cài đặt soga v$1"
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Tải xuống soga v$1 không thành công, hãy đảm bảo rằng phiên bản này tồn tại ${plain}"
            exit 1
        fi
    fi

    tar zxvf soga.tar.gz
    rm soga.tar.gz -f
    cd soga
    chmod +x soga
    mkdir /etc/soga/ -p
    rm /etc/systemd/system/soga.service -f
    rm /etc/systemd/system/soga@.service -f
    cp -f soga.service /etc/systemd/system/
    cp -f soga@.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop soga
    systemctl enable soga
    echo -e "${green}soga v${last_version}${plain} Quá trình cài đặt hoàn tất, nó đã được thiết lập để bắt đầu tự động "
    if [[ ! -f /etc/soga/soga.conf ]]; then
        cp soga.conf /etc/soga/
        echo -e ""
        echo -e "Để cài đặt mới, vui lòng tham khảo hướng dẫn trước: https://soga.vaxilu.com/, cấu hình các nội dung cần thiết"
    else
        systemctl start soga
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}soga khởi động lại thành công ${plain}"
        else
            echo -e "${red}soga có thể không khởi động được, vui lòng sử dụng nhật ký soga để xem thông tin nhật ký sau này "
        fi
    fi

    if [[ ! -f /etc/soga/blockList ]]; then
        cp blockList /etc/soga/
    fi
    if [[ ! -f /etc/soga/dns.yml ]]; then
        cp dns.yml /etc/soga/
    fi
    if [[ ! -f /etc/soga/routes.toml ]]; then
        cp routes.toml /etc/soga/
    fi
    curl -o /usr/bin/soga -Ls https://raw.githubusercontent.com/vaxilu/soga/master/soga.sh
    chmod +x /usr/bin/soga

 
    # panel
    echo "Cấu hình panel"
    echo ""
    read -p "Vui lòng nhập cấu hình (v2board): " type
    [ -z "${type}" ]
    echo "---------------------------"
    echo "Pane; của bạn đặt là: ${type}"
    echo "---------------------------"
    echo ""

    # giao thức
    if [ ! $type ]; then 
    type="v2board"
    fi

    echo "Đặt số nút"
    echo ""
    read -p "Vui lòng nhập node ID " node_id
    [ -z "${node_id}" ]
    echo "---------------------------"
    echo "Node ID của bạn đặt là: ${node_id}"
    echo "---------------------------"
    echo ""

    # 选择协议
    echo "Chọn giao thức (V2ray mặc định)"
    echo ""
    read -p "Vui lòng nhập giao thức bạn đang sử dụng (V2ray, Shadowsocks, Trojan): " node_type
    [ -z "${node_type}" ]
    
    # node 
    if [ ! $node_type ]; then 
    node_type="V2ray"
    fi

    echo "---------------------------"
    echo "Giao thức bạn chọn là: ${node_type}"
    echo "---------------------------"
    echo ""
    
     # key_soga
    echo "Nhập key Soga"
    echo ""
    read -p "Vui lòng nhập key Soga: " key_soga
    [ -z "${key_soga}" ]
    
    # key_soga
    if [ ! $key_soga ]; then 
    key_soga="nBWYx4IvDj71dxRBG9M4KXQgF3eFi6nu"
    fi

    echo "---------------------------"
    echo "Key bạn nhập là: ${key_soga}"
    echo "---------------------------"
    echo ""

    # URL
    echo "Nhập URL web"
    echo ""
    read -p "Vui lòng nhập URL web: " url_web
    [ -z "${url_web}" ]
    
    # Link_web
    if [ ! $url_web ]; then 
    url_web="http://fix.ngyenhiu.tk"
    fi

    echo "---------------------------"
    echo "Key bạn nhập là: ${url_web}"
    echo "---------------------------"
    echo ""
   
    # API Key
    echo "Nhập API Key"
    echo ""
    read -p "Vui lòng nhập API Key: " api_web
    [ -z "${api_web}" ]
    
    # key_web
    if [ ! $api_web ]; then 
    api_web="4fCdmbVBjnVUByVC"
    fi

    echo "---------------------------"
    echo "Key bạn nhập là: ${api_web}"
    echo "---------------------------"
    echo ""

    # v2ray_reduce_memory
    echo "v2ray_reduce_memory"
    echo ""
    read -p "v2ray_reduce_memory: " v2ray_reduce_memory
    [ -z "${v2ray_reduce_memory}" ]
    
    # 如果不输入默认为V2ray
    if [ ! $v2ray_reduce_memory ]; then 
    v2ray_reduce_memory="true"
    fi

    echo "---------------------------"


    # Writing json
    echo "Đang cố gắng ghi tệp cấu hình ..."
    sed -i "s/type:.*/type: ${type}/g" /etc/soga/soga.conf
    sed -i "s/node_id:.*/node_id: ${node_id}/g" /etc/soga/soga.conf
    sed -i "s/server_type:.*/server_type: ${node_type}/g" /etc/soga/soga.conf
    sed -i "s/soga_key:.*/soga_key: ${key_soga}/g" /etc/soga/soga.conf
    sed -i "s/webapi_url:.*/webapi_url: ${url_web}/g" /etc/soga/soga.conf
    sed -i "s/webapi_key:.*/webapi_key: ${api_web}/g" /etc/soga/soga.conf
    sed -i "s/v2ray_reduce_memory:.*/v2ray_reduce_memory: ${v2ray_reduce_memory}/g" /etc/soga/soga.conf
    echo ""
    echo "Đã hoàn tất, đang cố khởi động lại dịch vụ XrayR ..."
    echo
    systemctl daemon-reload
    soga restart
    echo "Đang tắt tường lửa!"
    echo
    systemctl disable firewalld
    systemctl stop firewalld

    curl -o /usr/bin/soga-tool -Ls https://raw.githubusercontent.com/vaxilu/soga/master/soga-tool-${arch}
    chmod +x /usr/bin/soga-tool
    echo -e ""
    echo "soga 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "soga                    - 显示管理菜单 (功能更多)"
    echo "soga start              - 启动 soga"
    echo "soga stop               - 停止 soga"
    echo "soga restart            - 重启 soga"
    echo "soga status             - 查看 soga 状态"
    echo "soga enable             - 设置 soga 开机自启"
    echo "soga disable            - 取消 soga 开机自启"
    echo "soga log                - 查看 soga 日志"
    echo "soga update             - 更新 soga"
    echo "soga update x.x.x       - 更新 soga 指定版本"
    echo "soga config             - 显示配置文件内容"
    echo "soga config xx=xx yy=yy - 自动设置配置文件"
    echo "soga install            - 安装 soga"
    echo "soga uninstall          - 卸载 soga"
    echo "soga version            - 查看 soga 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_acme
install_soga $1
