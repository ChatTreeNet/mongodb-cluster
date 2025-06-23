# MongoDB 集群 - 5分钟快速上手

> 🎯 **目标**: 在5分钟内完成MongoDB副本集集群的部署和验证

## ⚡ 超快部署（推荐）

### Git一键部署
```bash
# 1. 克隆并部署（自动生成密码）
git clone <repository-url>
cd mongodb-cluster
./deploy.sh

# 2. 验证部署
./scripts/health-check.sh

# ✅ 完成！集群已就绪
```

**🎉 部署完成！** 密码已自动生成并显示，请保存。

## 🔧 手动部署（5步骤）

如果需要自定义配置：

```bash
# 1. 复制配置模板
cp env.template .env

# 2. 修改密码（必须！）
sed -i 's/CHANGE_THIS_SUPER_SECURE_PASSWORD_2024/你的超强密码/' .env
sed -i 's/CHANGE_THIS_APP_PASSWORD_2024/你的应用密码/' .env

# 3. 启动服务
docker-compose up -d && sleep 30

# 4. 初始化副本集  
./scripts/init-replica-set.sh

# 5. 验证部署
./scripts/health-check.sh
```

## 🌐 立即连接

### 管理员连接
```bash
# 方式1: 通过容器
docker exec -it mongo-primary mongo -u admin -p 你的密码 --authenticationDatabase admin

# 方式2: 外部连接
mongodb://admin:你的密码@localhost:27017/admin?replicaSet=rs0
```

### 应用连接
```bash
mongodb://appuser:应用密码@localhost:27017/myapp?replicaSet=rs0
```

## 📋 基础操作

### 状态检查
```bash
# 检查容器状态
docker-compose ps

# 检查副本集状态  
docker exec mongo-primary mongo -u admin -p 密码 --authenticationDatabase admin --eval "rs.status()"

# 运行健康检查
./scripts/health-check.sh
```

### 备份操作
```bash
# 立即备份
docker exec mongo-backup /scripts/backup.sh

# 查看备份
ls -la backups/
```

## 🚨 常见问题

### 容器启动失败
```bash
# 检查端口占用
netstat -tlnp | grep :27017

# 查看错误日志
docker-compose logs mongo-primary
```

### 副本集初始化失败
```bash
# 等待更长时间再初始化
sleep 60
./scripts/init-replica-set.sh
```

### 内存不足
```bash
# 降低内存限制
sed -i 's/PRIMARY_MEMORY_LIMIT=1.2G/PRIMARY_MEMORY_LIMIT=800M/' .env
docker-compose restart
```

## 🔗 需要更多功能？

- 📖 **[完整文档](README.md)** - 详细配置和管理
- 🎯 **[Git部署](GIT_DEPLOY.md)** - Git仓库部署指南
- 📦 **[存储桶备份](BUCKET_BACKUP.md)** - 云存储备份配置
- ⏰ **[计划任务](1PANEL_CRON.md)** - 1Panel计划任务集成
- 🎛️ **[1Panel集成](1PANEL_INTEGRATION.md)** - 1Panel完整集成

---

**⚡ 恭喜！** 你的MongoDB集群现在已经运行。开始构建你的应用吧！🚀 