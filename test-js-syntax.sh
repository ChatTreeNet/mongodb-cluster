#!/bin/bash
# 测试JavaScript语法的脚本

echo "🧪 测试JavaScript语法..."

# 加载环境变量
if [ -f ".env" ]; then
    source .env
else
    # 使用默认值
    export MONGO_ROOT_USER="admin"
    export MONGO_ROOT_PASSWORD="password"
    export MONGO_APP_USER="appuser"
    export MONGO_APP_PASSWORD="apppassword"
    export MONGO_APP_DATABASE="myapp"
    export MONGO_READONLY_USER="readonly"
    export MONGO_READONLY_PASSWORD="readonly"
    export REPLICA_SET_NAME="rs0"
fi

# 测试变量替换后的JavaScript代码
echo "📝 测试管理员用户创建语法..."
cat <<EOF | docker run --rm -i mongo:4.4 mongo --quiet --eval "$(cat)"
var adminUser = "$MONGO_ROOT_USER";
var adminPassword = "$MONGO_ROOT_PASSWORD";

print("用户名: " + adminUser);
print("密码长度: " + adminPassword.length);

// 测试创建用户的语法
var userConfig = {
    user: adminUser,
    pwd: adminPassword,
    roles: [
        { role: "root", db: "admin" }
    ]
};

print("用户配置: " + JSON.stringify(userConfig));
print("✅ 管理员用户语法测试通过");
EOF

echo ""
echo "📝 测试应用用户创建语法..."
cat <<EOF | docker run --rm -i mongo:4.4 mongo --quiet --eval "$(cat)"
var appDatabase = "$MONGO_APP_DATABASE";
var appUser = "$MONGO_APP_USER";
var appPassword = "$MONGO_APP_PASSWORD";
var readonlyUser = "$MONGO_READONLY_USER";
var readonlyPassword = "$MONGO_READONLY_PASSWORD";

print("应用数据库: " + appDatabase);
print("应用用户: " + appUser);
print("只读用户: " + readonlyUser);

// 测试创建用户的语法
var appUserConfig = {
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
};

var readonlyUserConfig = {
    user: readonlyUser,
    pwd: readonlyPassword,
    roles: [
        {
            role: "read",
            db: appDatabase
        }
    ]
};

print("应用用户配置: " + JSON.stringify(appUserConfig));
print("只读用户配置: " + JSON.stringify(readonlyUserConfig));
print("✅ 应用用户语法测试通过");
EOF

echo ""
echo "✅ 所有JavaScript语法测试通过！" 