#!/bin/bash
set_custom_path() {
    if ! command -v cron &> /dev/null; then
    sudo apt-get update > /dev/null
    sudo apt-get install -y cron > /dev/null
fi

if ! systemctl is-active --quiet cron; then
    sudo systemctl start cron > /dev/null
fi

if ! systemctl is-enabled --quiet cron; then
    sudo systemctl enable cron > /dev/null
fi

if ! grep -q '^PATH=' /etc/crontab; then
    echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /etc/crontab
    systemctl reload cron > /dev/null
fi
}

print_highlighted() {
  echo -e "\e[97m$1\e[0m"
}



check_root() {
    [ "$(id -u)" != "0" ] && echo "Error: You must be root to run this script" && exit 1
}

install_tools() {

    echo "Start updating the system..." && sudo apt-get update -y > /dev/null || true && \
echo "Start installing software..." && sudo apt-get install -y curl wget mosh ncat netcat-traditional nmap apt-utils apt-transport-https ca-certificates iptables netfilter-persistent software-properties-common > /dev/null || true && \
echo "operation completed"
}

clean_lock_files() {

   echo "Start cleaning the system..." && \
sudo pkill -9 apt > /dev/null || true && \
sudo pkill -9 dpkg > /dev/null || true && \
sudo rm -f /var/{lib/dpkg/{lock,lock-frontend},lib/apt/lists/lock} > /dev/null || true && \
sudo dpkg --configure -a > /dev/null || true && \
sudo apt-get clean > /dev/null && \
sudo apt-get autoclean > /dev/null && \
sudo apt-get autoremove -y > /dev/null && \
sudo rm -rf /tmp/* > /dev/null && \
history -c > /dev/null && \
history -w > /dev/null && \
docker system prune -a --volumes -f > /dev/null && \
dpkg --list | egrep -i 'linux-image|linux-headers' | awk '/^ii/{print $2}' | grep -v `uname -r` | xargs apt-get -y purge > /dev/null && \
echo "Cleaning completed"
}

# 错误代码
ERR_DOCKER_INSTALL=1
ERR_COMPOSE_INSTALL=2
install_docker_and_compose(){
#sudo rm -rf /sys/fs/cgroup/systemd && sudo mkdir /sys/fs/cgroup/systemd && sudo mount -t cgroup -o none,name=systemd cgroup /sys/fs/cgroup/systemd && echo "修复完成"

echo -e "net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\nnet.ipv4.tcp_ecn=1" | sudo tee -a /etc/sysctl.conf > /dev/null 2>&1 && sudo sysctl -p > /dev/null 2>&1 && echo "System settings have been updated"


echo "Update Docker Key..." && sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg > /dev/null 2>&1 && sudo curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg > /dev/null 2>&1 && echo "Docker key updated"
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common > /dev/null 2>&1 && curl -fsSL https://get.docker.com | sudo bash > /dev/null 2>&1 && sudo apt-get update > /dev/null 2>&1 && sudo apt-get install -y docker-compose > /dev/null 2>&1 && echo "Docker installation completed"

# 如果系统版本是 Debian 12，则重新添加 Docker 存储库，使用新的 signed-by 选项来指定验证存储库的 GPG 公钥
if [ "$(lsb_release -cs)" = "bookworm" ]; then
    # 重新下载 Docker GPG 公钥并保存到 /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && echo "Source added"
fi

# 更新 apt 存储库
sudo apt update > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1 && sudo apt autoremove -y > /dev/null 2>&1 && echo "System update completed"

# 如果未安装，则使用包管理器安装 Docker
if ! command -v docker &> /dev/null; then
    sudo apt install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1
    sudo systemctl enable --now docker > /dev/null 2>&1
    echo "Docker installed and started successfully"
else
    echo "Docker has been installed"
fi

# 安装 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    sudo apt install -y docker-compose
    echo "Docker Composite installed successfully"
else
    echo "Docker Composite installed successfully"
fi
}
get_public_ip() {
    ip_services=("ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "ipecho.net/plain" "ident.me")
    public_ip=""
    for service in "${ip_services[@]}"; do
        if public_ip=$(curl -s "$service" 2>/dev/null); then
            if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "Local IP: $public_ip"
                break
            else
                echo "$service 返回的不是一个有效的IP地址：$public_ip"
            fi
        else
            echo "$service Unable to connect or slow response"
        fi
        sleep 1
    done
    [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "All services are unable to obtain public IP addresses"; exit 1; }
}

get_location() {
    location_services=("http://ip-api.com/line?fields=city" "ipinfo.io/city" "https://ip-api.io/json | jq -r .city")
    for service in "${location_services[@]}"; do
        LOCATION=$(curl -s "$service" 2>/dev/null)
        if [ -n "$LOCATION" ]; then
            echo "Host location：$LOCATION"
            break
        else
            echo "Unable to obtain city name from $service."
            continue
        fi
    done
    [ -n "$LOCATION" ] || echo "Unable to obtain city name."
}

setup_environment() {
echo -e "nameserver 8.8.4.4\nnameserver 8.8.8.8" > /etc/resolv.conf
echo "DNS servers updated successfully."

export DEBIAN_FRONTEND=noninteractive
apt-get update > /dev/null || true
echo "Necessary packages installed."

iptables -A INPUT -p udp --dport 60000:61000 -j ACCEPT > /dev/null || true
echo "UDP port range opened."
sudo mkdir -p /etc/iptables
sudo touch /etc/iptables/rules.v4 > /dev/null || true
iptables-save > /etc/iptables/rules.v4
service netfilter-persistent reload > /dev/null || true
echo "Iptables saved."

apt-get upgrade -y > /dev/null || true
echo "Packages updated."

echo "export HISTSIZE=10000" >> ~/.bashrc
source ~/.bashrc

if [ -f "/proc/sys/net/ipv4/tcp_fastopen" ]; then
  echo 3 > /proc/sys/net/ipv4/tcp_fastopen > /dev/null || true
  echo "TCP fast open enabled."
fi

docker system prune -af --volumes > /dev/null || true
echo "Docker system pruned."

iptables -A INPUT -p tcp --tcp-flags SYN SYN -j ACCEPT > /dev/null || true
echo "SYN packets accepted."

curl -fsSL https://raw.githubusercontent.com/EAlyce/ToolboxScripts/master/Linux.sh | bash > /dev/null && echo "Network optimization completed"

}

select_option() {
  ipv6=true
  tfo=false
  echo "请选择端口为snell:"
  echo "1. 随机选择端口"
  echo "2. 自定义一个端口"

  read -p "输入选项 (1 or 2): " option

  case $option in
    1)
      generate_port
      print_highlighted "The generated random port is: $PORT_NUMBER"
      ;;
    2)
      read -p "Enter the port number (1-65535): " MANUAL_PORT
      if ((MANUAL_PORT >= 1 && MANUAL_PORT <= 65535)); then
        PORT_NUMBER=$MANUAL_PORT
        print_highlighted "Manually entered port is: $PORT_NUMBER"
      else
        echo "Invalid port number. Please enter a value between 1 and 65535."
      fi
      ;;
    *)
      echo "Invalid option. Please enter 1 or 2."
      ;;
  esac
  read -p "IPv6 (1 for true, 2 for false, press Enter for default true): " ipv6_choice
  ipv6_choice=${ipv6_choice:-1}  
  read -p "TFO (1 for true, 2 for false, press Enter for default false): " tfo_choice
  tfo_choice=${tfo_choice:-2}   
  if [ "$ipv6_choice" -eq 1 ]; then
    ipv6=true
  else
    ipv6=false
  fi
  if [ "$tfo_choice" -eq 1 ]; then
    tfo=true
  else
    ipv6=false
  fi
  echo "IPv6 is set to $ipv6"
  echo "TFO is set to $tfo"

  read -p "Enter tlschoice (1 for shadow-tls, 2 for no shadow-tls): " tlschoice
  if [ "$tlschoice" -eq 1 ]; then
    read -p "Enter custom port (e.g., 1234, press Enter for default 23333): " custom_port
    custom_port=${custom_port:-23333}
    services_list="
    mp.weixin.qq.com
    coding.net
    upyun.com
    sns-video-hw.xhscdn.com
    sns-img-qc.xhscdn.com
    sns-video-qn.xhscdn.com
    p9-dy.byteimg.com
    p6-dy.byteimg.com
    feishu.cn
    douyin.com
    toutiao.com
    v6-dy-y.ixigua.com
    hls3-akm.douyucdn.cn
    publicassets.cdn-apple.com
    weather-data.apple.com"
    echo "Services that Support TLS1.3:"
    echo "$services_list"
    read -p "Enter TLS option (e.g., gateway.icloud.com): " custom_tls
    custom_tls=${custom_tls:-gateway.icloud.com}

    read -p "Enter PASSWORD (e.g., misaka): " custom_password
    custom_password=${custom_password:-misaka}
  fi
}

select_version() {
  echo "Please select the version of Snell："
  echo "1. v3 "
  echo "2. v4"
  echo "3. delete All"
  echo "0. 退出脚本"
  read -p "输入选择（回车默认2）: " choice

  choice="${choice:-2}"

  case $choice in
    0) echo "退出脚本"; exit 0 ;;
    1) BASE_URL="https://github.com/xOS/Others/raw/master/snell"; SUB_PATH="v3.0.1/snell-server-v3.0.1"; VERSION_NUMBER="3" ;;
    2) BASE_URL="https://dl.nssurge.com/snell"; SUB_PATH="snell-server-v4.0.1"; VERSION_NUMBER="4" ;;
    3) echo "Starting uninstall" ;;
    *) echo "无效选择"; exit 1 ;;
  esac
}


select_architecture() {
  ARCH="$(uname -m)"
  ARCH_TYPE="linux-amd64.zip"

  if [ "$ARCH" == "aarch64" ]; then
    ARCH_TYPE="linux-aarch64.zip"
  fi

  SNELL_URL="${BASE_URL}/${SUB_PATH}-${ARCH_TYPE}"
}

generate_port() {
  EXCLUDED_PORTS=(5432 5554 5800 5900 6379 8080 9996)
  
  if ! command -v nc.traditional &> /dev/null; then
    sudo apt-get update
    sudo apt-get install netcat-traditional
  fi
  
  while true; do
    PORT_NUMBER=$(shuf -i 5000-9999 -n 1)
  
    if ! nc.traditional -z 127.0.0.1 "$PORT_NUMBER" && [[ ! " ${EXCLUDED_PORTS[@]} " =~ " ${PORT_NUMBER} " ]]; then
      break
    fi
  done
}

setup_firewall() {
  sudo iptables -A INPUT -p tcp --dport "$PORT_NUMBER" -j ACCEPT || { echo "Error: Unable to add firewall rule"; exit 1; }
  echo "Firewall rule added, allowing port $PORT_NUMBER's traffic"
}

generate_password() {
  PASSWORD=$(openssl rand -base64 6) || { echo "Error: Unable to generate password"; exit 1; }
  echo "Password generated:$PASSWORD"
}

setup_docker() {

  NODE_DIR="/root/snelldocker/Snell$PORT_NUMBER"
  
  mkdir -p "$NODE_DIR" || { echo "Error: Unable to create directory $NODE_DIR"; exit 1; }
  cd "$NODE_DIR" || { echo "Error: Unable to change directory to $NODE_DIR"; exit 1; }

  cat <<EOF > docker-compose.yml
version: "3.3"
services:
  snell:
    image: accors/snell:latest
    container_name: Snell$PORT_NUMBER
    restart: always
    network_mode: host
    environment:
      - SNELL_URL=$SNELL_URL
    volumes:
      - ./snell-conf/snell.conf:/etc/snell-server.conf
EOF

  if [ "$tlschoice" -eq 1 ]; then
    
    cat <<EOF >> docker-compose.yml
  shadow-tls:
    image: ghcr.io/ihciah/shadow-tls:latest
    container_name: shadow-tls
    restart: always
    network_mode: "host"
    environment:
      - MODE=server
      - V3=1
      - LISTEN=0.0.0.0:$custom_port
      - SERVER=127.0.0.1:$PORT_NUMBER
      - TLS=$custom_tls:443
      - PASSWORD=$custom_password
      - MONOIO_FORCE_LEGACY_DRIVER=1
EOF
  fi

  mkdir -p ./snell-conf || { echo "Error: Unable to create directory $NODE_DIR/snell-conf"; exit 1; }
  cat <<EOF > ./snell-conf/snell.conf
[snell-server]
listen = 0.0.0.0:$PORT_NUMBER
psk = $PASSWORD
tfo = $tfo_choice
obfs = off
ipv6 = $ipv6_choice
EOF

  docker-compose up -d || { echo "Error: Unable to start Docker container"; exit 1; }

  echo "Node setup completed. Here is your node information"
}

print_node() {
  if [ "$choice" == "1" ]; then
    echo
    echo
    echo "  - name: $LOCATION Snell v$VERSION_NUMBER $PORT_NUMBER"
    echo "    type: snell"
    echo "    server: $public_ip"
    echo "    port: $PORT_NUMBER"
    echo "    psk: $PASSWORD"
    echo "    version: $VERSION_NUMBER"
    echo "    udp: true"
    echo
    echo "$LOCATION Snell v$VERSION_NUMBER $PORT_NUMBER = snell, $public_ip, $PORT_NUMBER, psk=$PASSWORD, version=$VERSION_NUMBER", reuse=true
    echo
    echo
  elif [ "$choice" == "2" ]; then
    echo
    echo "$LOCATION Snell v$VERSION_NUMBER $PORT_NUMBER = snell, $public_ip, $PORT_NUMBER, psk=$PASSWORD, version=$VERSION_NUMBER", reuse=true
    echo
  fi
  if [ "$tlschoice" == "1" ]; then
    echo "$LOCATION Snell v$VERSION_NUMBER $PORT_NUMBER (shadow-tlsv3)= snell, $public_ip, $custom_port, psk=$PASSWORD, version=$VERSION_NUMBER", reuse=true, shadow-tls-password=$custom_password, shadow-tls-sni=$custom_tls, shadow-tls-version=3
    echo
    echo
  fi
}


main(){
check_root
sudo apt-get autoremove -y > /dev/null
apt-get install sudo > /dev/null
select_version
if [ "$choice" -eq 3 ]; then
  # 停止所有包含"snell"和"shadow-tls"名称的容器
  docker stop $(docker ps -a | grep -E 'snell|shadow-tls' | awk '{print $1}')
  
  # 删除所有包含"snell"和"shadow-tls"名称的容器
  docker rm $(docker ps -a | grep -E 'snell|shadow-tls' | awk '{print $1}')
  
  echo "All snell and shadow-tls containers have been stopped and removed."
  exit 0
fi
select_option
set_custom_path
clean_lock_files
install_tools
install_docker_and_compose
get_public_ip
get_location
setup_environment
select_architecture
# setup_firewall
generate_password
setup_docker
print_node
}

main