#!/bin/bash
# MongoDB 副本集初始化脚本 V3 - 使用专门的配置文件
# 用法: ./init-replica-set-v3.sh

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

echo "📋 配置信息:"
echo "  - 副本集名称: $REPLICA_SET_NAME"
echo "  - 管理员用户: $MONGO_ROOT_USER"

# 清理函数
cleanup() {
    local exit_code=$?
    echo "🧹 清理中..."
    
    if [ $exit_code -ne 0 ]; then
        echo "❌ 脚本执行失败"
        echo "💡 您可以手动运行: docker-compose down && docker-compose up -d"
    fi
    
    exit $exit_code
}

trap cleanup EXIT

# 阶段1：使用初始化配置启动集群
echo "🔧 阶段1: 启动无认证模式的MongoDB集群..."

# 停止现有服务
docker-compose down >/dev/null 2>&1 || true

# 使用初始化配置启动
docker-compose -f docker-compose.init.yml up -d

# 等待服务启动
echo "⏳ 等待MongoDB实例启动..."
sleep 15

# 检查所有实例
for container in mongo-primary mongo-secondary1 mongo-secondary2; do
    echo "   检查 $container..."
    while ! docker exec $container mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
        echo "   $container 未就绪，等待5秒..."
        sleep 5
    done
done

echo "✅ 所有MongoDB实例已启动"

# 阶段2：初始化副本集和创建管理员用户
echo "🔧 阶段2: 初始化副本集..."
docker exec -i mongo-primary mongo <<EOF

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
} else if (result.code === 23) {
    print("⚠️  副本集已经初始化，跳过初始化步骤");
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
        // 副本集还未完全初始化，或者已经在运行
        if (e.message && e.message.includes("not running with --replSet")) {
            print("⚠️  检测到副本集可能已经在运行");
            break;
        }
    }
    
    attempts++;
    print("   第 " + attempts + "/" + maxAttempts + " 次检查...");
    sleep(2000);
}

if (attempts >= maxAttempts) {
    print("⚠️  副本集状态检查超时，继续执行...");
}

// 创建管理员用户
print("👤 创建管理员用户...");
var adminUser = "$MONGO_ROOT_USER";
var adminPassword = "$MONGO_ROOT_PASSWORD";

try {
    use admin;
    db.createUser({
        user: adminUser,
        pwd: adminPassword,
        roles: [
            { role: "root", db: "admin" }
        ]
    });
    print("✅ 管理员用户创建成功");
} catch (e) {
    if (e.code === 51003) {
        print("⚠️  管理员用户已存在");
    } else {
        print("❌ 创建管理员用户失败:", e.message);
        // 不要退出，继续执行
    }
}

print("🎉 副本集和管理员用户初始化完成！");
EOF

# 阶段3：切换到生产配置（启用认证）
echo "🔧 阶段3: 启用认证模式..."

# 停止初始化模式的服务
docker-compose -f docker-compose.init.yml down

# 启动生产模式的服务
docker-compose up -d

# 等待认证模式服务启动
echo "⏳ 等待认证模式服务启动..."
sleep 20

# 等待主节点认证模式启动
while ! docker exec mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
    echo "   等待认证模式主节点启动..."
    sleep 5
done

echo "✅ 认证模式已启用"

# 阶段4：创建应用用户
echo "👤 阶段4: 创建应用用户和数据库..."
docker exec -i mongo-primary mongo -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin <<EOF

// 定义变量
var appDatabase = "$MONGO_APP_DATABASE";
var appUser = "$MONGO_APP_USER";
var appPassword = "$MONGO_APP_PASSWORD";
var readonlyUser = "$MONGO_READONLY_USER";
var readonlyPassword = "$MONGO_READONLY_PASSWORD";

// 切换到应用数据库
use(appDatabase);

print("📝 创建应用用户: " + appUser);

// 创建应用用户
try {
    db.createUser({
        user: appUser,
        pwd: appPassword,
        roles: [
            {
                role: "readWrite",
                db: appDatabase
            },
            {
                role: "dbOwner",
                db: appDatabase
            }
        ]
    });
    print("✅ 应用用户创建成功");
} catch (e) {
    if (e.code === 51003) {
        print("⚠️  用户 " + appUser + " 已存在");
    } else {
        print("❌ 创建应用用户失败:", e.message);
    }
}

print("📖 创建只读用户: " + readonlyUser);

// 创建只读用户
try {
    db.createUser({
        user: readonlyUser,
        pwd: readonlyPassword,
        roles: [
            {
                role: "read",
                db: appDatabase
            }
        ]
    });
    print("✅ 只读用户创建成功");
} catch (e) {
    if (e.code === 51003) {
        print("⚠️  用户 " + readonlyUser + " 已存在");
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
    appName: appDatabase,
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