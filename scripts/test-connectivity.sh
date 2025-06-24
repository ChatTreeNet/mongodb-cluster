#!/bin/bash
# scripts/test-connectivity.sh
# -------------------------------------------
# MongoDB 集群连通性综合测试脚本
# 1. 依赖: docker / mongo
# 2. 支持无认证 & 认证两种模式
# 3. 输出彩色结果，方便 CI 或人工巡检
# -------------------------------------------

set -e

if [[ -f .env ]]; then
  # 把 .env 里的键值对 export 到当前环境
  set -a
  source .env
  set +a
else
  log_error ".env 文件不存在，无法加载连接参数"
  exit 1
fi

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
REPLICA_SET=${REPLICA_SET_NAME:-rs0}
ROOT_USER=${MONGO_ROOT_USER:-admin}
ROOT_PWD=${MONGO_ROOT_PASSWORD:-password}

# 新增：应用用户信息
APP_USER=${MONGO_APP_USER:-appuser}
APP_PWD=${MONGO_APP_PASSWORD:-apppassword}
APP_DB=${MONGO_APP_DATABASE:-myapp}

PRIMARY_PORT=${MONGO_PRIMARY_PORT:-27017}
S1_PORT=${MONGO_SECONDARY1_PORT:-27018}
S2_PORT=${MONGO_SECONDARY2_PORT:-27019}
BIND_IP=${MONGO_BIND_IP:-127.0.0.1}

# 检测本机是否安装 mongo 客户端
if command -v mongo >/dev/null 2>&1; then
  MONGO_BIN="mongo"
  HOST_PRIMARY="${BIND_IP}:${PRIMARY_PORT}"
  HOST_SECONDARY1="${BIND_IP}:${S1_PORT}"
  HOST_SECONDARY2="${BIND_IP}:${S2_PORT}"
else
  log_warn "未检测到本机 mongo 客户端，改用 docker exec mongo-primary mongo"
  MONGO_BIN="docker exec mongo-primary mongo"
  HOST_PRIMARY="mongo-primary:27017"
  HOST_SECONDARY1="mongo-secondary1:27017"
  HOST_SECONDARY2="mongo-secondary2:27017"
fi

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
    if $MONGO_BIN --host "$host" -u "$ROOT_USER" -p "$ROOT_PWD" --authenticationDatabase admin --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
      log_ok "${name} (${host}) ping 成功 (认证模式)"
    else
      log_error "${name} (${host}) ping 失败 (认证模式)"
    fi
  else
    if $MONGO_BIN --host "$host" --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
      log_ok "${name} (${host}) ping 成功"
    else
      log_error "${name} (${host}) ping 失败"
    fi
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
# (2) 认证模式 ping —— 初始化后 (管理员)
# --------------------------------------------------
printf "\n(2) 认证模式 ping (admin)\n"
ping_node "$HOST_PRIMARY"   "Primary"    1
ping_node "$HOST_SECONDARY1" "Secondary1" 1
ping_node "$HOST_SECONDARY2" "Secondary2" 1

# --------------------------------------------------
# (3) 应用用户 ping & 权限验证
# --------------------------------------------------
printf "\n(3) 应用用户 ($APP_USER) 认证 & 读写测试\n"

# 连接并写入/读取简单文档来验证读写权限
TEST_OUT=$($MONGO_BIN --host "$HOST_PRIMARY" -u "$APP_USER" -p "$APP_PWD" --authenticationDatabase "$APP_DB" --quiet --eval "\
try{db=db.getSiblingDB('$APP_DB');db.test_conn.insertOne({ok:true,t:new Date()});var doc=db.test_conn.findOne({ok:true});printjson({inserted:!!doc});}catch(e){printjson({error:e.message});}\
" || true)

if echo "$TEST_OUT" | grep -q '"inserted"' ; then
  log_ok "appuser 读写测试通过"
else
  log_error "appuser 认证/权限失败: $TEST_OUT"
fi

# --------------------------------------------------
# (4) rs.status() 简要检测
# --------------------------------------------------
printf "\n(4) 副本集状态\n"
OUTPUT=$($MONGO_BIN --host "$HOST_PRIMARY" -u "$ROOT_USER" -p "$ROOT_PWD" --authenticationDatabase admin --quiet --eval "try{var s=rs.status();printjson({set:s.set,primary:s.members.filter(function(m){return m.state===1;})[0].name,health:s.members.map(function(m){return {name:m.name,health:m.health,state:m.stateStr};})});}catch(e){printjson({error:e.message});}") || true

if echo "$OUTPUT" | grep -q '"error"'; then
  log_error "rs.status 查询失败: $OUTPUT"
else
  log_ok "rs.status 正常: $OUTPUT"
fi

printf "\n=============== 测试结束 ===============\n" 