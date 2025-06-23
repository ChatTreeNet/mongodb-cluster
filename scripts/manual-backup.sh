#!/bin/bash
# 手动触发一次备份。脚本只是包装，实际逻辑在 scripts/backup.sh

CDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CDIR" || exit 1

./scripts/backup.sh 