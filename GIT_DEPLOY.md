# Git 仓库一键部署指南

## 🎯 适用场景

- 希望直接从Git仓库部署MongoDB集群
- 不想手动创建配置文件
- 需要快速搭建开发/测试环境
- 希望自动生成安全密码

## 🚀 一键部署

### 基础部署

```bash
# 1. 克隆仓库
git clone <your-repository-url>
cd mongodb-cluster

# 2. 运行部署脚本
./deploy.sh
```

### 高级选项

```bash
# 查看帮助信息
./deploy.sh --help

# 仅创建环境配置文件（不启动服务）
./deploy.sh --env-only

# 启动服务但不初始化副本集
./deploy.sh --no-init
```

## 📋 部署流程

脚本会自动执行以下步骤：

1. **依赖检查** - 验证Docker和Docker Compose
2. **密码生成** - 自动生成强密码
3. **配置创建** - 从模板创建.env文件
4. **目录创建** - 创建数据/日志/备份目录
5. **端口检查** - 确保27017-27019端口可用
6. **服务启动** - 启动MongoDB集群
7. **副本集初始化** - 配置副本集
8. **健康检查** - 验证部署结果

## 🔐 生成的密码

部署脚本会自动生成三组密码：

- **管理员密码** (24位) - 用于数据库管理
- **应用密码** (20位) - 用于应用连接
- **只读密码** (16位) - 用于只读访问

> ⚠️ **重要**：密码会在部署过程中显示一次，请妥善保存！

## 📁 文件说明

部署完成后会创建以下文件：

```
mongodb-cluster/
├── .env                    # 环境配置文件（包含密码）
├── data/                   # MongoDB数据目录
├── logs/                   # 日志目录
└── backups/                # 备份目录
```

## 🔧 自定义配置

如果需要自定义配置，可以：

1. **修改资源限制**：编辑 `env.template` 中的资源配置
2. **修改端口**：更改 `MONGO_*_PORT` 变量
3. **调整备份设置**：修改 `BACKUP_*` 相关配置

然后重新运行：
```bash
./deploy.sh --env-only  # 重新生成配置
```

## 🌐 连接信息

部署完成后，可以使用以下连接字符串：

```bash
# 管理员连接
mongodb://admin:<管理员密码>@localhost:27017/admin?replicaSet=rs0

# 应用连接
mongodb://appuser:<应用密码>@localhost:27017/myapp?replicaSet=rs0

# 只读连接
mongodb://readonly:<只读密码>@localhost:27017/myapp?replicaSet=rs0
```

## 🛠️ 管理命令

```bash
# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 健康检查
./scripts/health-check.sh
```

## 🔄 重新部署

如果需要重新部署：

```bash
# 停止并清理现有服务
docker-compose down -v

# 重新部署
./deploy.sh
```

## ❗ 故障排除

### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口占用
   netstat -tlnp | grep :27017
   
   # 修改端口（编辑 env.template）
   MONGO_PRIMARY_PORT=27027
   ```

2. **权限不足**
   ```bash
   # 给脚本执行权限
   chmod +x deploy.sh
   
   # 给其他脚本权限
   chmod +x scripts/*.sh
   ```

3. **Docker未启动**
   ```bash
   # 启动Docker服务
   sudo systemctl start docker
   ```

4. **内存不足**
   ```bash
   # 调整内存限制（编辑 .env 文件）
   PRIMARY_MEMORY_LIMIT=800M
   SECONDARY1_MEMORY_LIMIT=600M
   ```

### 获取帮助

- 📖 查看完整文档：[README.md](README.md)
- 🎛️ 1Panel集成：[1PANEL_INTEGRATION.md](1PANEL_INTEGRATION.md)
- 🕐 时区配置：[TIMEZONE_CONFIG.md](TIMEZONE_CONFIG.md)

## 🔒 安全建议

1. **立即更改默认密码**（如果使用默认模板）
2. **限制网络访问**（配置防火墙）
3. **定期备份数据**
4. **监控系统资源**
5. **及时更新镜像版本**

---

**💡 提示**：Git部署方式特别适合开发和测试环境，生产环境建议进行额外的安全配置。 