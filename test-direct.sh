#!/bin/bash
# 直接测试JavaScript语法

echo "🧪 直接测试JavaScript语法错误..."

# 测试直接在运行的容器中执行
if docker exec mongo-primary mongo --version >/dev/null 2>&1; then
    echo "✅ 容器运行正常"
    
    echo "📝 测试基础JavaScript语法..."
    docker exec mongo-primary mongo --eval "
    var adminUser = 'admin';
    var adminPassword = 'test_password';
    print('用户名: ' + adminUser);
    print('密码: ' + adminPassword);
    print('✅ 基础语法测试通过');
    "
    
    echo ""
    echo "📝 测试有问题的语法..."
    # 尝试重现错误
    docker exec mongo-primary mongo --eval "
    var adminUser = \"admin\";
    var adminPassword = \"your_super_secure_password_2024\";
    print('✅ 带引号语法测试通过');
    "
    
    echo ""
    echo "📝 测试完整的用户创建语法..."
    docker exec mongo-primary mongo --eval "
    var adminUser = 'testuser';
    var adminPassword = 'testpass';
    
    use admin;
    
    var userConfig = {
        user: adminUser,
        pwd: adminPassword,
        roles: [
            { role: 'root', db: 'admin' }
        ]
    };
    
    print('用户配置: ' + JSON.stringify(userConfig));
    print('✅ 完整语法测试通过');
    "
    
else
    echo "❌ 容器未运行"
fi 