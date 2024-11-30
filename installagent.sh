#!/bin/bash

#set -x
# 检查是否传入了必要的参数
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <client_secret> <server> <tls>"
    echo "Example: $0 qUZT4RaKc4r7ZPlQ6gTtv46z7o2 g1.xxxx:443 true"
    exit 1
fi

# 定义基础路径
NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
sudo mkdir -p $NZ_AGENT_PATH

# 从命令行参数获取 client_secret, server 和 tls
CLIENT_SECRET=$1
SERVER=$2
TLS=$3

# 检查输入的必填项是否为空
if [[ -z "$CLIENT_SECRET" || -z "$SERVER" || -z "$TLS" ]]; then
  echo "client_secret, server 和 tls 都是必填项，请重新运行脚本并填写完整信息！"
  exit 1
fi

# 生成 uuid
UUID=$(uuidgen)

# 定义下载监控端的 URL
echo "正在下载监控端..."

# 获取 Nezha 最新版本号
_version=$(curl -m 10 -sL "https://api.github.com/repos/nezhahq/agent/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
if [ -z "$_version" ]; then
    _version=$(curl -m 10 -sL "https://gitee.com/api/v5/repos/naibahq/agent/releases/latest" | awk -F '"' '{for(i=1;i<=NF;i++){if($i=="tag_name"){print $(i+2)}}}')
fi
if [ -z "$_version" ]; then
    _version=$(curl -m 10 -sL "https://fastly.jsdelivr.net/gh/nezhahq/agent/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/naiba\/nezha@/v/g')
fi
if [ -z "$_version" ]; then
    _version=$(curl -m 10 -sL "https://gcore.jsdelivr.net/gh/nezhahq/agent/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/naiba\/nezha@/v/g')
fi

# 检查是否成功获取版本号
if [ -z "$_version" ]; then
    echo "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/nezhahq/agent/releases/latest"
    exit 1
else
    echo "当前最新版本为: ${_version}"
fi

# 构建下载 URL
if uname -m | grep -q 'x86_64'; then
    os_arch="amd64"
elif uname -m | grep -q 'i386\|i686'; then
    os_arch="386"
elif uname -m | grep -q 'aarch64\|armv8b\|armv8l'; then
    os_arch="arm64"
elif uname -m | grep -q 'arm'; then
    os_arch="arm"
elif uname -m | grep -q 's390x'; then
    os_arch="s390x"
elif uname -m | grep -q 'riscv64'; then
    os_arch="riscv64"
fi

# 检测是否在中国大陆
geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://dash.cloudflare.com/cdn-cgi/trace https://developers.cloudflare.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    set -- "$api_list"
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s "$url")"
        endpoint="$(echo "$text" | sed -n 's/.*h=\([^ ]*\).*/\1/p')"
        if echo "$text" | grep -qw 'CN'; then
            CN=true
            break
        elif echo "$url" | grep -q "$endpoint"; then
            break
        fi
    done
}
if [ -z "$CN" ]; then
    geo_check
fi
if [ -z "$CN" ]; then
    GITHUB_URL="github.com"
else
    GITHUB_URL="gitee.com"
fi
if [ -z "$CN" ]; then
    NZ_AGENT_URL="https://${GITHUB_URL}/nezhahq/agent/releases/download/${_version}/nezha-agent_linux_${os_arch}.zip"
else
    NZ_AGENT_URL="https://${GITHUB_URL}/naibahq/agent/releases/download/${_version}/nezha-agent_linux_${os_arch}.zip"
fi


# 下载文件到 /tmp 目录
echo "正在下载文件到 /tmp/nezha-agent.zip"
curl -L -o /tmp/nezha-agent.zip "$NZ_AGENT_URL"

# 检查文件是否下载成功
if [ $? -ne 0 ]; then
    echo "下载失败，请检查网络或下载链接是否正确"
    exit 1
fi

# 解压文件到 /tmp/nezha-agent
echo "正在解压文件到 /tmp/nezha-agent"
sudo unzip -o /tmp/nezha-agent.zip -d /tmp/nezha-agent
if [ $? -ne 0 ]; then
    echo "解压失败，请检查文件或权限"
    exit 1
fi

# 将解压后的文件移动到指定路径
echo "将解压后的文件移动到 ${NZ_AGENT_PATH}/nezha-agentv1"
sudo mv -f /tmp/nezha-agent/* ${NZ_AGENT_PATH}/nezha-agentv1
sudo rm -rf /tmp/nezha-agent
rm -f /tmp/nezha-agent.zip
echo "文件已解压并移动到 ${NZ_AGENT_PATH}/nezha-agentv1"

if [ -f "${NZ_AGENT_PATH}/config.yml" ]; then

    # 重启服务
    echo "重启服务..."
    sudo systemctl restart nezhav1
    echo "服务已重启！"

else
    # 如果文件不存在，执行安装过程

    echo "监控端安装完成，路径: ${NZ_AGENT_PATH}/nezha-agentv1"

    # 判断 config.yml 是否存在
    if [ ! -f "${NZ_AGENT_PATH}/config.yml" ]; then
        # 如果 config.yml 不存在，生成配置文件
        echo "config.yml 文件不存在，正在生成 config.yml 配置文件..."
        cat <<EOF | sudo tee ${NZ_AGENT_PATH}/config.yml > /dev/null
client_secret: "$CLIENT_SECRET"
server: "$SERVER"
tls: $TLS
uuid: $UUID
EOF

        echo "config.yml 配置文件已生成。"
    else
        echo "config.yml 文件已存在，跳过生成。"
    fi

    # 判断 systemd 服务文件是否存在
    SERVICE_FILE="/etc/systemd/system/nezhav1.service"
    if [ ! -f "$SERVICE_FILE" ]; then
        # 如果服务文件不存在，生成 systemd 服务文件
        echo "systemd 服务文件不存在，正在创建服务文件 ${SERVICE_FILE}"

        cat <<EOF | sudo tee $SERVICE_FILE > /dev/null
[Unit]
Description=哪吒探针监控端V1
ConditionFileIsExecutable=/opt/nezha/agent/nezha-agentv1

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/opt/nezha/agent/nezha-agentv1 -c /opt/nezha/agent/config.yml
WorkingDirectory=/root
Restart=always
RestartSec=120
EnvironmentFile=-/etc/sysconfig/nezha-agent

[Install]
WantedBy=multi-user.target
EOF

        # 重新加载 systemd 配置
        echo "重新加载 systemd 配置..."
        sudo systemctl daemon-reload
    else
        echo "systemd 服务文件已存在，跳过创建。"
    fi

    # 启动并设置服务开机自启
    echo "启动并设置 nezhav1 服务开机自启..."
    sudo systemctl enable --now nezhav1

    # 检查服务状态
    sudo systemctl status nezhav1
    echo "安装完成！哪吒探针监控端V1已成功启动并设置为开机自启。"
fi
