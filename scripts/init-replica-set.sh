#!/bin/bash
# MongoDB 副本集初始化脚本
# 用法: ./init-replica-set.sh

set -e

echo "🚀 开始初始化 MongoDB 副本集..."

# 从环境变量或默认值获取配置
MONGO_ROOT_USER=${MONGO_ROOT_USER:-admin}
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD:-password}
MONGO_APP_USER=${MONGO_APP_USER:-appuser}
MONGO_APP_PASSWORD=${MONGO_APP_PASSWORD:-apppassword}
MONGO_APP_DATABASE=${MONGO_APP_DATABASE:-myapp}
MONGO_READONLY_USER=${MONGO_READONLY_USER:-readonly}
MONGO_READONLY_PASSWORD=${MONGO_READONLY_PASSWORD:-readonly}
REPLICA_SET_NAME=${REPLICA_SET_NAME:-rs0}

# 验证必需的环境变量
if [ -z "$MONGO_ROOT_PASSWORD" ] || [ "$MONGO_ROOT_PASSWORD" = "password" ]; then
    echo "⚠️  警告: 使用默认密码不安全，请在.env文件中设置强密码"
fi

echo "📋 配置信息:"
echo "  - 副本集名称: $REPLICA_SET_NAME"
echo "  - 管理员用户: $MONGO_ROOT_USER"
echo "  - 应用数据库: $MONGO_APP_DATABASE"
echo "  - 应用用户: $MONGO_APP_USER"
echo "  - 只读用户: $MONGO_READONLY_USER"

# 等待所有MongoDB实例启动
echo "⏳ 等待 MongoDB 实例启动..."
echo "   检查主节点..."
while ! docker exec mongo-primary mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
    echo "   主节点未就绪，等待5秒..."
    sleep 5
done

echo "   检查副本节点1..."
while ! docker exec mongo-secondary1 mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
    echo "   副本节点1未就绪，等待5秒..."
    sleep 5
done

echo "   检查副本节点2..."
while ! docker exec mongo-secondary2 mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
    echo "   副本节点2未就绪，等待5秒..."
    sleep 5
done

echo "✅ 所有MongoDB实例已启动"

# 连接到主节点并初始化副本集
echo "🔧 初始化副本集..."
docker exec -i mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin <<EOF

print("🚀 开始初始化副本集 $REPLICA_SET_NAME");

// 初始化副本集
var config = {
  _id: "$REPLICA_SET_NAME",
  members: [
    {
      _id: 0,
      host: "mongo-primary:27017",
      priority: 2
    },
    {
      _id: 1, 
      host: "mongo-secondary1:27017",
      priority: 1
    },
    {
      _id: 2,
      host: "mongo-secondary2:27017", 
      priority: 1
    }
  ]
};

var result = rs.initiate(config);
print("📊 副本集初始化结果:", JSON.stringify(result));

if (result.ok === 1) {
    print("✅ 副本集初始化成功");
} else {
    print("❌ 副本集初始化失败:", result.errmsg);
    quit(1);
}

// 等待副本集初始化完成
print("⏳ 等待副本集选举完成...");
var attempts = 0;
var maxAttempts = 30;

while (attempts < maxAttempts) {
    try {
        var status = rs.status();
        var primary = status.members.find(function(member) {
            return member.state === 1;
        });
        
        if (primary) {
            print("✅ 主节点选举完成: " + primary.name);
            break;
        }
    } catch (e) {
        // 副本集还未完全初始化
    }
    
    attempts++;
    print("   第 " + attempts + "/" + maxAttempts + " 次检查...");
    sleep(2000);
}

if (attempts >= maxAttempts) {
    print("❌ 副本集选举超时");
    quit(1);
}

// 显示副本集状态
print("📊 副本集状态:");
var status = rs.status();
status.members.forEach(function(member) {
    print("  - " + member.name + ": " + member.stateStr + " (健康: " + member.health + ")");
});

print("🎉 副本集初始化完成！");
EOF

# 等待一段时间确保副本集稳定
echo "⏳ 等待副本集稳定..."
sleep 10

# 创建应用数据库和用户
echo "👤 创建应用用户和数据库..."
docker exec -i mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin <<EOF

// 切换到应用数据库
use $MONGO_APP_DATABASE;

print("📝 创建应用用户: $MONGO_APP_USER");

// 创建应用用户
try {
    db.createUser({
        user: "$MONGO_APP_USER",
        pwd: "$MONGO_APP_PASSWORD",
        roles: [
            {
                role: "readWrite",
                db: "$MONGO_APP_DATABASE"
            },
            {
                role: "dbOwner",
                db: "$MONGO_APP_DATABASE"
            }
        ]
    });
    print("✅ 应用用户创建成功");
} catch (e) {
    if (e.code === 51003) {
        print("⚠️  用户 $MONGO_APP_USER 已存在");
    } else {
        print("❌ 创建应用用户失败:", e.message);
    }
}

print("📖 创建只读用户: $MONGO_READONLY_USER");

// 创建只读用户
try {
    db.createUser({
        user: "$MONGO_READONLY_USER",
        pwd: "$MONGO_READONLY_PASSWORD",
        roles: [
            {
                role: "read",
                db: "$MONGO_APP_DATABASE"
            }
        ]
    });
    print("✅ 只读用户创建成功");
} catch (e) {
    if (e.code === 51003) {
        print("⚠️  用户 $MONGO_READONLY_USER 已存在");
    } else {
        print("❌ 创建只读用户失败:", e.message);
    }
}

// 创建示例集合和数据
print("📚 创建示例集合...");
db.users.insertOne({
    name: "示例用户",
    email: "example@domain.com",
    createdAt: new Date(),
    status: "active"
});

db.settings.insertOne({
    appName: "$MONGO_APP_DATABASE",
    version: "1.0.0",
    initializedAt: new Date(),
    replicaSet: "$REPLICA_SET_NAME"
});

print("✅ 示例数据创建完成");

// 创建索引
print("🔍 创建索引...");
db.users.createIndex({ email: 1 }, { unique: true });
db.users.createIndex({ status: 1 });
db.users.createIndex({ createdAt: 1 });

print("✅ 索引创建完成");

print("🎉 数据库和用户设置完成！");
EOF

echo ""
echo "🎊 MongoDB 副本集初始化成功完成！"
echo ""
echo "📋 连接信息:"
echo "  管理员连接:"
echo "    mongo 'mongodb://$MONGO_ROOT_USER:$MONGO_ROOT_PASSWORD@localhost:27017/admin?replicaSet=$REPLICA_SET_NAME'"
echo ""
echo "  应用连接:"
echo "    mongo 'mongodb://$MONGO_APP_USER:$MONGO_APP_PASSWORD@localhost:27017/$MONGO_APP_DATABASE?replicaSet=$REPLICA_SET_NAME'"
echo ""
echo "  只读连接:"
echo "    mongo 'mongodb://$MONGO_READONLY_USER:$MONGO_READONLY_PASSWORD@localhost:27017/$MONGO_APP_DATABASE?replicaSet=$REPLICA_SET_NAME'"
echo ""
echo "📊 验证副本集状态:"
echo "    docker exec -it mongo-primary mongo -u $MONGO_ROOT_USER -p $MONGO_ROOT_PASSWORD --authenticationDatabase admin --eval 'rs.status()'"
echo ""
echo "✅ 初始化完成！" 