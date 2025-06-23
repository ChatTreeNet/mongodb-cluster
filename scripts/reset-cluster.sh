#!/bin/bash
# MongoDB 集群重置脚本
# 用法: ./reset-cluster.sh [--force]

set -e

echo "🔄 MongoDB 集群重置脚本"

# 检查是否强制执行
FORCE_RESET=false
if [ "$1" = "--force" ]; then
    FORCE_RESET=true
fi

# 如果不是强制执行，询问用户确认
if [ "$FORCE_RESET" = false ]; then
    echo ""
    echo "⚠️  警告：此操作将："
    echo "   - 停止所有MongoDB容器"
    echo "   - 删除所有MongoDB数据卷"
    echo "   - 清除所有数据库数据"
    echo "   - 重新初始化整个集群"
    echo ""
    read -p "是否确认执行重置？[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ 操作已取消"
        exit 1
    fi
fi

echo "🛑 停止所有MongoDB服务..."
docker-compose down -v 2>/dev/null || true
docker-compose -f docker-compose.init.yml down -v 2>/dev/null || true

echo "🗑️  删除所有MongoDB数据卷..."
docker volume rm -f mongodb-cluster_mongo_primary_data 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_primary_config 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_secondary1_data 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_secondary1_config 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_secondary2_data 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_secondary2_config 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_logs 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_logs_s1 2>/dev/null || true
docker volume rm -f mongodb-cluster_mongo_logs_s2 2>/dev/null || true

echo "🧹 清理容器和网络..."
docker container rm -f mongo-primary mongo-secondary1 mongo-secondary2 mongo-backup mongo-monitor 2>/dev/null || true
docker network rm mongodb-cluster_mongo-cluster 2>/dev/null || true

echo "🚀 重新初始化集群..."
# 确保环境变量被加载
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

if [ -f "scripts/init-replica-set-v3.sh" ]; then
    ./scripts/init-replica-set-v3.sh
else
    echo "❌ 初始化脚本不存在"
    exit 1
fi

echo "✅ 集群重置完成！" 