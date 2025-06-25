#!/usr/bin/env bash
# ================================================================
# insert-sample-user.sh
# ------------------------------------------------
# 向 MongoDB 集群（主节点）插入一条示例用户记录。
# 依赖 .env 中的 MONGO_ROOT_USER / MONGO_ROOT_PASSWORD、
# MONGO_PRIMARY_CONTAINER、MONGO_APP_DATABASE 等变量。
# ------------------------------------------------
# 用法：
#   ./scripts/insert-sample-user.sh            # 默认插入
#   DRY_RUN=1 ./scripts/insert-sample-user.sh  # 仅打印将要执行的 mongo JS
# ================================================================
set -euo pipefail

# shell 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载环境变量（若存在）
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/.env"
fi

# ----------------------- 可配置项 -----------------------
ROOT_USER="${MONGO_ROOT_USER:-admin}"
ROOT_PWD="${MONGO_ROOT_PASSWORD:-password}"
PRIMARY_CONTAINER="${MONGO_PRIMARY_CONTAINER:-mongo-primary}"
APP_DB="${MONGO_APP_DATABASE:-myapp}"
COLLECTION="users"

# ------------------ 要插入的文档内容 -------------------
read -r -d '' MONGO_JS <<'EOF'
var doc = {
  __v: 0,
  agreementVersion: 1,
  authToken: "",
  avcode: "",
  createdAt: ISODate("2021-08-18T12:10:16.341Z"),
  hashed_password: "",
  icon: "https://6368-chathistory-2g27eaau722404af-1301839800.tcb.qcloud.la/development/5f183ff3f8b6590019917101/65369e39bed26b0741435b1f.jpeg?sign=399cbb8e841630c1a8ecbd71540f8e72&t=1698078265",
  name: "大佑",
  removeRequested: false,
  resetPassToken: "fDlB8M14",
  role: "admin",
  salt: "983582396765",
  sex: 1,
  uid: "goforu",
  updatedAt: ISODate("2025-04-14T08:07:34.181Z"),
  vipExpiresAt: ISODate("2026-04-19T11:43:41.102Z"),
  vipTried: true,
  invitedTime: ISODate("2023-04-27T05:42:14.576Z"),
  level: 3,
  phone: "+8617378811132"
};
db.getSiblingDB("${APP_DB}").getCollection("${COLLECTION}").insertOne(doc);
printjson({ inserted: doc.uid });
EOF

# ---------------- 执行或预览 ---------------------------
if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "--- Mongo Shell JS to be executed ---"
  echo "$MONGO_JS"
  exit 0
fi

echo "[INFO] Inserting sample user into ${APP_DB}.${COLLECTION} ..."

# 使用 docker exec 调用 mongo shell
set +e
output=$(docker exec -i "$PRIMARY_CONTAINER" \
  mongo -u "$ROOT_USER" -p "$ROOT_PWD" --authenticationDatabase admin --quiet <<EOF
$MONGO_JS
EOF
)
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "[ERROR] mongo shell exited with status $status" >&2
  echo "$output" >&2
  exit $status
fi

# 成功输出
echo "$output"

echo "[OK] Document inserted successfully." 