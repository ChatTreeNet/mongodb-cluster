#!/bin/bash
# scripts/test-connectivity.sh
# -------------------------------------------
# MongoDB 集群连通性综合测试脚本
# 1. 依赖: docker / mongo
# 2. 支持无认证 & 认证两种模式
# 3. 输出彩色结果，方便 CI 或人工巡检
# -------------------------------------------

set -e

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

log_info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}  $1"; }
log_ok()      { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}    $1"; }
log_warn()    { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}  $1"; }
log_error()   { echo -e "${COLOR_RED}[FAIL]${COLOR_RESET}  $1"; }

# --------------------------------------------------
# 加载环境变量
# --------------------------------------------------
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
else
  log_error ".env 文件不存在，无法加载连接参数"
  exit 1
fi

REPLICA_SET=${REPLICA_SET_NAME:-rs0}
ROOT_USER=${MONGO_ROOT_USER:-admin}
ROOT_PWD=${MONGO_ROOT_PASSWORD:-password}

PRIMARY_PORT=${MONGO_PRIMARY_PORT:-27017}
S1_PORT=${MONGO_SECONDARY1_PORT:-27018}
S2_PORT=${MONGO_SECONDARY2_PORT:-27019}
BIND_IP=${MONGO_BIND_IP:-127.0.0.1}

HOST_PRIMARY="${BIND_IP}:${PRIMARY_PORT}"
HOST_SECONDARY1="${BIND_IP}:${S1_PORT}"
HOST_SECONDARY2="${BIND_IP}:${S2_PORT}"

printf "\n=============== MongoDB 集群连通性测试 ===============\n"
log_info "副本集名称: $REPLICA_SET"
log_info "主节点端口: $HOST_PRIMARY"
log_info "副本节点端口: $HOST_SECONDARY1, $HOST_SECONDARY2"

# --------------------------------------------------
# 函数: 测试单节点的 ping
# --------------------------------------------------
function ping_node() {
  local host=$1
  local name=$2
  local auth_flag=$3   # 1=带认证 0=不带认证

  if [[ $auth_flag -eq 1 ]]; then
    mongo "mongodb://${ROOT_USER}:${ROOT_PWD}@${host}/admin?retryWrites=false" --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1
  else
    mongo --host "$host" --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1
  fi

  if [[ $? -eq 0 ]]; then
    log_ok "${name} (${host}) ping 成功${auth_flag:+ (认证模式)}"
  else
    log_error "${name} (${host}) ping 失败${auth_flag:+ (认证模式)}"
  fi
}

# --------------------------------------------------
# (1) 无认证模式 ping —— 用于初始化阶段
# --------------------------------------------------
printf "\n(1) 无认证模式 ping\n"
ping_node "$HOST_PRIMARY"   "Primary"    0
ping_node "$HOST_SECONDARY1" "Secondary1" 0
ping_node "$HOST_SECONDARY2" "Secondary2" 0

# --------------------------------------------------
# (2) 认证模式 ping —— 初始化后
# --------------------------------------------------
printf "\n(2) 认证模式 ping\n"
ping_node "$HOST_PRIMARY"   "Primary"    1
ping_node "$HOST_SECONDARY1" "Secondary1" 1
ping_node "$HOST_SECONDARY2" "Secondary2" 1

# --------------------------------------------------
# (3) rs.status() 简要检测
# --------------------------------------------------
printf "\n(3) 副本集状态\n"
OUTPUT=$(mongo "mongodb://${ROOT_USER}:${ROOT_PWD}@${HOST_PRIMARY}/admin?replicaSet=${REPLICA_SET}&retryWrites=false" --quiet --eval "try{var s=rs.status();printjson({set:s.set,primary:s.members.filter(m=>m.state===1)[0].name,health:s.members.map(m=>({name:m.name,health:m.health,state:m.stateStr}))});}catch(e){printjson({error:e.message});}") || true

if echo "$OUTPUT" | grep -q '"error"'; then
  log_error "rs.status 查询失败: $OUTPUT"
else
  log_ok "rs.status 正常: $OUTPUT"
fi

printf "\n=============== 测试结束 ===============\n" 