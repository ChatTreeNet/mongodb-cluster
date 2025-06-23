#!/bin/bash
# MongoDB 副本集快速测试脚本

echo "🧪 开始测试 MongoDB 副本集初始化..."

# 检查环境
if [ ! -f ".env" ]; then
    echo "❌ .env 文件不存在，请先运行 deploy.sh 或创建 .env 文件"
    exit 1
fi

# 加载环境变量
source .env

echo "📋 使用配置:"
echo "  - 副本集: $REPLICA_SET_NAME"
echo "  - 管理员用户: $MONGO_ROOT_USER"

# 停止现有服务
echo "🛑 停止现有服务..."
docker-compose down

# 运行新的初始化脚本
echo "🚀 运行初始化脚本..."
./scripts/init-replica-set-v2.sh

# 验证结果
echo "🔍 验证副本集状态..."
docker exec -it mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "
print('📊 副本集状态:');
rs.status().members.forEach(function(member) {
    print('  - ' + member.name + ': ' + member.stateStr + ' (健康: ' + member.health + ')');
});

print('👥 用户列表:');
db.runCommand({usersInfo: 1}).users.forEach(function(user) {
    print('  - ' + user.user + '@' + user.db + ': ' + user.roles.map(r => r.role).join(', '));
});
"

echo "✅ 测试完成！" 