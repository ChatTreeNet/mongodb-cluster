#!/bin/bash
# MongoDB 集群状态检查脚本

echo "🔍 MongoDB 集群状态检查"
echo ""

# 检查环境配置
if [ ! -f ".env" ]; then
    echo "❌ .env 文件不存在"
    exit 1
fi

source .env

echo "📋 配置信息:"
echo "  - 副本集名称: $REPLICA_SET_NAME"
echo "  - 管理员用户: $MONGO_ROOT_USER"
echo ""

# 检查Docker容器状态
echo "🐳 Docker 容器状态:"
docker-compose ps
echo ""

# 检查数据卷
echo "💾 Docker 数据卷:"
echo "主节点数据卷:"
docker volume ls | grep mongo_primary || echo "  无主节点数据卷"
echo "副本节点数据卷:"
docker volume ls | grep mongo_secondary || echo "  无副本节点数据卷"
echo ""

# 检查MongoDB连接和副本集状态
echo "🔗 MongoDB 连接测试:"

# 检查主节点
if docker exec mongo-primary mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    echo "✅ 主节点连接正常（无认证）"
    
    # 检查副本集状态
    echo ""
    echo "📊 副本集状态:"
    docker exec mongo-primary mongo --eval "
        try {
            var status = rs.status();
            print('副本集名称: ' + status.set);
            print('成员数量: ' + status.members.length);
            status.members.forEach(function(member) {
                print('  - ' + member.name + ': ' + member.stateStr + ' (健康: ' + member.health + ')');
            });
        } catch (e) {
            print('副本集未初始化或连接失败: ' + e.message);
        }
    " 2>/dev/null
    
elif docker exec mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    echo "✅ 主节点连接正常（认证模式）"
    
    # 检查副本集状态
    echo ""
    echo "📊 副本集状态:"
    docker exec mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "
        try {
            var status = rs.status();
            print('副本集名称: ' + status.set);
            print('成员数量: ' + status.members.length);
            status.members.forEach(function(member) {
                print('  - ' + member.name + ': ' + member.stateStr + ' (健康: ' + member.health + ')');
            });
        } catch (e) {
            print('副本集状态检查失败: ' + e.message);
        }
    " 2>/dev/null
    
    # 检查用户
    echo ""
    echo "👥 用户列表:"
    docker exec mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "
        try {
            db.runCommand({usersInfo: 1}).users.forEach(function(user) {
                print('  - ' + user.user + '@' + user.db + ': ' + user.roles.map(r => r.role).join(', '));
            });
        } catch (e) {
            print('用户列表获取失败: ' + e.message);
        }
    " 2>/dev/null
    
else
    echo "❌ 主节点连接失败"
fi

echo ""
echo "💡 建议操作:"
echo "  - 如果副本集未初始化: ./deploy.sh"
echo "  - 如果需要完全重置: ./deploy.sh --reset"
echo "  - 如果只需要启动服务: ./deploy.sh --no-init"
echo "  - 运行健康检查: ./scripts/health-check.sh" 