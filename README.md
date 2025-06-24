# MongoDB 副本集集群

这是一个生产就绪的MongoDB 4.4副本集配置，专为5GB内存、100GB存储的服务器环境设计。

## 📋 项目特性

- ✅ **3节点副本集** - 1主 + 2副本，确保高可用性
- ✅ **自动备份** - 支持压缩、1Panel集成、自动清理
- ✅ **健康监控** - 实时监控副本集状态和系统资源
- ✅ **安全配置** - 启用认证、角色权限控制
- ✅ **性能优化** - 针对有限资源进行优化配置
- ✅ **容器化部署** - 使用Docker Compose一键部署
- ✅ **环境变量配置** - 通过.env文件管理所有配置

## 🏗️ 项目结构

```
mongodb-cluster/
├── docker-compose.yml          # 主配置文件
├── env.template               # 环境变量配置模板
├── deploy.sh                  # Git仓库一键部署脚本 ⭐
├── .gitignore                 # Git忽略文件配置
├── README.md                  # 项目说明
├── 1PANEL_INTEGRATION.md      # 1Panel集成详细指南
├── QUICK_START.md             # 5分钟快速上手指南
├── TIMEZONE_CONFIG.md         # 时区配置说明
├── scripts/                   # 脚本目录
│   ├── init-replica-set.sh    # 副本集初始化
│   ├── backup.sh             # 自动备份脚本
│   ├── health-check.sh       # 健康检查脚本
│   └── 1panel-setup.sh       # 1Panel一键部署脚本
│   ├── init-replica-set-v3.sh  # 副本集初始化 (当前版本)
│   ├── backup.sh               # 自动/手动备份核心脚本
│   ├── manual-backup.sh        # 手动触发备份包装脚本
│   ├── health-check.sh         # 健康检查脚本
│   └── 1panel-setup.sh         # 1Panel一键部署脚本
├── config/                   # 配置文件
│   └── mongod.conf           # MongoDB配置
├── data/                     # 数据存储目录
│   └── .gitkeep              # 目录占位符
├── logs/                     # 日志目录
│   └── .gitkeep              # 目录占位符
└── backups/                  # 备份存储目录
    └── .gitkeep              # 目录占位符
```

## 🚀 快速开始

### 方式一：Git 仓库一键部署（推荐⭐）

直接从Git仓库克隆并部署，**无需手动创建配置文件**：

```bash
# 克隆仓库
git clone <repository-url>
cd mongodb-cluster

# 一键部署（自动生成安全密码）
./deploy.sh

# 可选参数：
./deploy.sh --help          # 查看帮助
./deploy.sh --env-only      # 仅创建配置文件
./deploy.sh --no-init       # 不初始化副本集
```

**特点**：
- ✅ 自动生成强密码
- ✅ 自动创建目录结构  
- ✅ 自动检查依赖和端口
- ✅ 自动初始化副本集
- ✅ 完整的错误处理

### 方式二：1Panel 集成部署

如果您使用1Panel面板，可以使用专用脚本：

```bash
# 使用1Panel一键部署
./scripts/1panel-setup.sh

# 或者手动部署，参考详细文档
# 请查看：1PANEL_INTEGRATION.md
```

### 方式三：手动部署

需要详细的手动部署步骤？请参考 **[快速开始指南](QUICK_START.md)**，包含完整的5步部署流程。

## 📊 资源配置

针对5GB内存、100GB存储优化的配置：

| 组件 | 内存限制 | CPU限制 | 存储分配 |
|------|----------|---------|----------|
| **主节点** | 1.2GB | 1.0核心 | 动态分配 |
| **副本节点1** | 1.0GB | 0.8核心 | 动态分配 |
| **副本节点2** | 1.0GB | 0.8核心 | 动态分配 |
| **监控服务** | 100MB | 0.1核心 | 5GB |

## 🔐 连接字符串

### 管理员连接
```bash
mongodb://admin:your_password@localhost:27017/admin?replicaSet=rs0
```

### 应用连接
```bash
mongodb://appuser:app_password@localhost:27017/myapp?replicaSet=rs0
```

### 只读连接
```bash
mongodb://readonly:readonly_password@localhost:27017/myapp?replicaSet=rs0
```

## 📦 备份管理

### 备份策略（无常驻容器）
本项目已改用 **单脚本备份** 方案，删掉了 `mongo-backup` 容器。

1. **自动备份**  
    在 1Panel 「计划任务」中新建 Cron（如每天 02:00）：
```bash
    cd /root/mongodb-cluster && ./scripts/backup.sh
    ```
    - `.env` 中的 `BACKUP_SCHEDULE` 保留给其它环境，可忽略。
    - `scripts/backup.sh` 会：
      1) 自动选择 secondary 进行 `mongodump`  
      2) 根据 `.env` 的 `BACKUP_COMPRESS` 决定是否生成 `.tar.gz`  
      3) 按 `BACKUP_RETENTION_DAYS` 清理旧文件  
      4) 可选推送到 S3/OSS/COS/MinIO（参见 `BUCKET_BACKUP.md`）。

2. **手动备份**  
    随时 SSH 执行：
```bash
    ./scripts/manual-backup.sh   # 或直接 ./scripts/backup.sh
    ```
    生成的备份位于 `./backups/YYYYMMDD_HHMMSS(.tar.gz)`。

3. **查看备份日志**  
    计划任务的 Stdout/Stderr 在 1Panel 前端可直接查看；
    手动执行则输出到终端。

## 📊 监控和日志

### 健康检查
```bash
# 手动健康检查
./scripts/health-check.sh

# 查看健康日志
docker exec mongo-monitor tail -f /logs/health.log

# 查看告警日志
docker exec mongo-monitor tail -f /logs/alerts.log
```

### 日志查看
```bash
# 查看MongoDB日志
docker exec mongo-primary tail -f /var/log/mongodb/mongod.log

# 查看容器日志
docker-compose logs -f mongo-primary
```

## 🛠️ 高级管理命令

### 基础操作
基础的容器管理、连接和备份命令请参考 **[快速开始指南](QUICK_START.md#基础操作)**。

### 副本集高级管理
```bash
# 查看副本集详细配置
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
printjson(rs.conf());
"

# 添加新的副本节点
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
rs.add('new-secondary:27017');
"

# 设置副本优先级
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
cfg = rs.conf();
cfg.members[1].priority = 0.5;
rs.reconfig(cfg);
"

# 强制选举新主节点
docker exec mongo-secondary1 mongo -u admin -p password --authenticationDatabase admin --eval "
rs.stepDown(60);
"
```

### 用户和权限管理
```bash
# 创建具有特定权限的用户
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
use myapp;
db.createUser({
  user: 'analytics',
  pwd: 'analytics_password',
  roles: [
    { role: 'read', db: 'myapp' },
    { role: 'readWrite', db: 'analytics' }
  ]
});
"

# 创建数据库级管理员
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
use myapp;
db.createUser({
  user: 'dbadmin',
  pwd: 'dbadmin_password', 
  roles: ['dbOwner']
});
"

# 查看用户权限
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
use myapp;
db.runCommand({usersInfo: 'username', showPrivileges: true});
"
```

### 性能分析和优化
```bash
# 启用详细的性能分析
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
use myapp;
db.setProfilingLevel(2, {slowms: 50});
"

# 查看慢查询
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
use myapp;
db.system.profile.find().limit(5).sort({ts: -1}).pretty();
"

# 分析查询计划
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
use myapp;
db.collection.find({field: 'value'}).explain('executionStats');
"

# 查看连接统计
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
db.serverStatus().connections;
"
```

## 🔧 故障排除

### 基础问题
常见的部署和连接问题解决方案请参考 **[快速开始指南](QUICK_START.md#常见问题)**。

### 高级故障排除

#### 副本集脑裂问题
```bash
# 检查副本集成员状态
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
rs.status().members.forEach(function(member) {
  print(member.name + ': ' + member.stateStr);
});
"

# 强制重新配置副本集
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
rs.reconfig(rs.conf(), {force: true});
"
```

#### 性能调优
```bash
# 检查慢查询
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin --eval "
db.setProfilingLevel(2, {slowms: 100});
"

# 查看索引使用情况
docker exec mongo-primary mongo -u admin -p password --authenticationDatabase admin myapp --eval "
db.collection.getIndexes();
"
```

#### 存储桶备份问题
详细的存储桶故障排除请参考 **[存储桶备份指南](BUCKET_BACKUP.md#故障排除)**。

#### 1Panel集成问题
1Panel相关问题请参考 **[1Panel集成指南](1PANEL_INTEGRATION.md#故障排除)** 和 **[计划任务指南](1PANEL_CRON.md#故障排除)**。

## 🔒 安全建议

### 生产环境安全清单
- ✅ 修改所有默认密码
- ✅ 启用防火墙，限制MongoDB端口访问
- ✅ 使用强密码和复杂用户名
- ✅ 定期更新密码
- ✅ 启用SSL/TLS (如需要)
- ✅ 配置IP白名单
- ✅ 定期备份和测试恢复
- ✅ 监控异常访问

### 密码要求
- 最少12位字符
- 包含大小写字母、数字、特殊字符
- 不使用字典词汇
- 定期更换（建议3-6个月）

## 📈 扩展和优化

### 垂直扩展
```bash
# 增加内存限制 (编辑 .env 文件)
PRIMARY_MEMORY_LIMIT=2.0G
MONGO_CACHE_SIZE_GB_PRIMARY=1.5

# 重启服务
docker-compose down
docker-compose up -d
```

### 水平扩展
要添加更多副本节点，需要修改 `docker-compose.yml` 并重新配置副本集。

### 性能调优
- 根据工作负载调整oplog大小
- 优化索引策略
- 调整WiredTiger缓存大小
- 监控慢查询并优化

## 📚 相关文档

- 🎯 **[Git仓库部署](GIT_DEPLOY.md)** - Git仓库一键部署详细指南
- 📦 **[存储桶备份](BUCKET_BACKUP.md)** - 对象存储备份配置指南
- ⏰ **[1Panel计划任务](1PANEL_CRON.md)** - 1Panel计划任务集成指南
- 📋 **[1Panel集成指南](1PANEL_INTEGRATION.md)** - 详细的1Panel部署和集成说明
- 🚀 **[快速开始](QUICK_START.md)** - 5分钟快速上手指南  
- 🌍 **[时区配置](TIMEZONE_CONFIG.md)** - 时区设置和管理说明

## 📞 支持

如有问题，请检查：
1. 📖 本README文档
2. 📋 相关专题文档（见上方链接）
3. 📋 项目Issues
4. 📚 [MongoDB官方文档](https://docs.mongodb.com/)
5. 🐳 [Docker Compose文档](https://docs.docker.com/compose/)
6. 🎛️ [1Panel官方文档](https://1panel.cn/docs/)

## 📄 许可证

本项目遵循 MIT 许可证。

---

**⚠️ 重要提醒：部署到生产环境前，请务必修改所有默认密码和安全配置！** 