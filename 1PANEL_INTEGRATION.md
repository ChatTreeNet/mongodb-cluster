# 1Panel 集成和备份管理指南

## 📋 概述

本文档详细介绍如何将MongoDB集群与1Panel面板集成，实现可视化管理和自动备份。

## 🚀 1Panel 安装

### 系统要求
- Ubuntu 20.04+ / CentOS 7+ / Debian 10+
- 最少 1GB 内存
- Docker 和 Docker Compose

### 一键安装脚本
```bash
# 下载并安装1Panel
curl -sSL https://resource.1panel.hk/quick_start.sh -o quick_start.sh && bash quick_start.sh

# 或者使用国内源
curl -sSL https://resource.1panel.cn/quick_start.sh -o quick_start.sh && bash quick_start.sh
```

### 手动安装
```bash
# 创建安装目录
mkdir -p /opt/1panel && cd /opt/1panel

# 下载安装包
wget https://github.com/1Panel-dev/1Panel/releases/latest/download/1panel-v1.x.x-linux-amd64.tar.gz

# 解压并安装
tar -zxf 1panel-*.tar.gz
cd 1panel-*
bash install.sh
```

### 初始配置
```bash
# 查看1Panel状态
systemctl status 1panel

# 获取初始用户信息
1pctl user-info

# 重置密码 (如需要)
1pctl reset-password
```

## 🐳 在1Panel中管理MongoDB容器

### 1. 导入现有项目

1. **访问1Panel面板**
   ```
   https://your-server-ip:10086
   ```

2. **进入容器管理**
   - 左侧菜单 → 容器 → 容器
   - 点击 "创建容器组"

3. **导入Docker Compose项目**
   ```bash
   # 在1Panel项目目录创建MongoDB项目
   mkdir -p /opt/1panel/apps/mongodb-cluster
   
   # 复制项目文件
   cp -r /path/to/mongodb-cluster/* /opt/1panel/apps/mongodb-cluster/
   ```

4. **在1Panel中添加项目**
   - 容器 → 编排 → 创建编排
   - 项目名称: `mongodb-cluster`
   - 工作目录: `/opt/1panel/apps/mongodb-cluster`
   - 编排文件: `docker-compose.yml`

### 2. 环境变量管理

在1Panel中配置环境变量：

1. **进入编排详情**
   - 容器 → 编排 → mongodb-cluster → 编辑

2. **配置环境变量**
   ```bash
   # 基础配置
   MONGO_ROOT_USER=admin
   MONGO_ROOT_PASSWORD=your_secure_password_2024
   MONGO_APP_USER=appuser
   MONGO_APP_PASSWORD=app_secure_password_2024
   
   # 备份配置
   BACKUP_SCHEDULE=0 9 * * *
   BACKUP_RETENTION_DAYS=30
   BACKUP_COMPRESS=true
   
   # 1Panel集成
   ONEPANEL_BACKUP_ENABLED=true
   ONEPANEL_BACKUP_PATH=/opt/1panel/backup/mongodb
   
   # 资源配置
   PRIMARY_MEMORY_LIMIT=1.2G
   SECONDARY_MEMORY_LIMIT=1.0G
   
   # 时区配置
   TZ=UTC
   ```

## 💾 1Panel 备份配置

### 1. 备份存储设置

#### 创建备份存储桶
1. **进入备份设置**
   - 系统设置 → 备份账号 → 添加

2. **配置存储类型**

   **本地存储：**
   ```bash
   类型: 本地目录
   路径: /opt/1panel/backup/mongodb
   ```

   **对象存储 (推荐)：**
   ```bash
   # 阿里云OSS
   类型: 阿里云OSS
   访问密钥: your-access-key
   访问秘钥: your-secret-key
   区域: oss-cn-hangzhou
   存储桶: your-backup-bucket
   
   # 腾讯云COS
   类型: 腾讯云COS
   秘钥ID: your-secret-id
   秘钥Key: your-secret-key
   区域: ap-guangzhou
   存储桶: your-backup-bucket
   
   # AWS S3
   类型: AWS S3
   访问密钥: your-access-key
   访问秘钥: your-secret-key
   区域: us-west-2
   存储桶: your-backup-bucket
   ```

#### 创建备份目录
```bash
# 创建1Panel备份目录
mkdir -p /opt/1panel/backup/mongodb
chown -R 1panel:1panel /opt/1panel/backup/mongodb
chmod 755 /opt/1panel/backup/mongodb

# 确保Docker容器可以访问
docker exec mongo-backup mkdir -p /backup/1panel
```

### 2. 自动备份任务

#### 在1Panel中创建计划任务
1. **进入计划任务**
   - 系统设置 → 计划任务 → 添加

2. **配置备份任务**
   ```bash
   任务名称: MongoDB自动备份
   任务类型: Shell脚本
   执行周期: 自定义 (0 9 * * *)
   执行脚本: 
   #!/bin/bash
   # 执行MongoDB备份
   docker exec mongo-backup /scripts/backup.sh
   
   # 同步到1Panel备份系统
   if [ -d "/opt/1panel/backup/mongodb" ]; then
       find /path/to/mongodb-cluster/backups -name "*.tar.gz" -newer /opt/1panel/backup/mongodb/.last_sync 2>/dev/null | while read file; do
           cp "$file" /opt/1panel/backup/mongodb/
           echo "$(date): Synced $(basename $file)" >> /opt/1panel/backup/mongodb/sync.log
       done
       touch /opt/1panel/backup/mongodb/.last_sync
   fi
   ```

#### 手动触发备份脚本
```bash
#!/bin/bash
# 文件: /opt/1panel/scripts/mongodb-backup.sh

# 设置变量
PROJECT_DIR="/opt/1panel/apps/mongodb-cluster"
BACKUP_DIR="/opt/1panel/backup/mongodb"
LOG_FILE="/opt/1panel/backup/mongodb/backup.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🚀 开始1Panel MongoDB备份任务"

# 执行容器内备份
cd "$PROJECT_DIR"
if docker-compose exec -T mongo-backup /scripts/backup.sh; then
    log "✅ 容器内备份完成"
else
    log "❌ 容器内备份失败"
    exit 1
fi

# 同步到1Panel备份目录
if [ -d "$PROJECT_DIR/backups" ]; then
    # 查找最新的备份文件
    LATEST_BACKUP=$(find "$PROJECT_DIR/backups" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [ -n "$LATEST_BACKUP" ]; then
        # 复制到1Panel备份目录
        cp "$LATEST_BACKUP" "$BACKUP_DIR/"
        log "✅ 备份文件已同步到1Panel: $(basename "$LATEST_BACKUP")"
        
        # 上传到云存储 (如果配置了)
        if command -v 1pctl >/dev/null 2>&1; then
            1pctl backup upload "$BACKUP_DIR/$(basename "$LATEST_BACKUP")" --type mongodb
            log "☁️ 备份已上传到云存储"
        fi
    else
        log "⚠️ 未找到最新备份文件"
    fi
else
    log "❌ 备份目录不存在: $PROJECT_DIR/backups"
    exit 1
fi

log "🎉 1Panel MongoDB备份任务完成"
```

### 3. 备份监控和告警

#### 配置备份监控脚本
```bash
#!/bin/bash
# 文件: /opt/1panel/scripts/backup-monitor.sh

BACKUP_DIR="/opt/1panel/backup/mongodb"
ALERT_EMAIL="admin@yourdomain.com"
MAX_AGE_HOURS=25

# 检查最新备份
LATEST_BACKUP=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -nr | head -1)

if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_TIME=$(echo "$LATEST_BACKUP" | cut -d' ' -f1)
    BACKUP_FILE=$(echo "$LATEST_BACKUP" | cut -d' ' -f2-)
    CURRENT_TIME=$(date +%s)
    AGE_HOURS=$(( (CURRENT_TIME - ${BACKUP_TIME%.*}) / 3600 ))
    
    if [ $AGE_HOURS -gt $MAX_AGE_HOURS ]; then
        # 发送告警
        echo "⚠️ MongoDB备份过期警告: 最新备份已经 $AGE_HOURS 小时前" | \
        curl -X POST "your-webhook-url" \
             -H "Content-Type: application/json" \
             -d "{\"text\":\"MongoDB备份告警: 最新备份文件 $(basename "$BACKUP_FILE") 已经 $AGE_HOURS 小时前，可能存在备份失败问题。\"}"
    fi
else
    # 没有找到备份文件
    echo "❌ 未找到任何备份文件" | \
    curl -X POST "your-webhook-url" \
         -H "Content-Type: application/json" \
         -d "{\"text\":\"MongoDB备份严重告警: 在 $BACKUP_DIR 中未找到任何备份文件！\"}"
fi
```

## 📊 1Panel 监控面板

### 1. 容器监控

在1Panel中监控MongoDB容器：

1. **进入容器监控**
   - 容器 → 容器 → mongodb-cluster

2. **查看关键指标**
   - CPU使用率
   - 内存使用率
   - 网络IO
   - 磁盘IO
   - 容器日志

### 2. 自定义监控面板

创建MongoDB专用监控面板：

```bash
# 创建监控脚本
cat > /opt/1panel/scripts/mongodb-metrics.sh << 'EOF'
#!/bin/bash

# MongoDB连接信息
MONGO_USER="admin"
MONGO_PASS="your_password"
PROJECT_DIR="/opt/1panel/apps/mongodb-cluster"

cd "$PROJECT_DIR"

# 获取副本集状态
REPLICA_STATUS=$(docker-compose exec -T mongo-primary mongo -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin --quiet --eval "
try {
    var status = rs.status();
    var primary = status.members.find(m => m.state === 1);
    var secondaries = status.members.filter(m => m.state === 2).length;
    var healthy = status.members.filter(m => m.health === 1).length;
    
    print('PRIMARY:' + (primary ? primary.name : 'NONE'));
    print('SECONDARIES:' + secondaries);
    print('HEALTHY_NODES:' + healthy + '/' + status.members.length);
} catch(e) {
    print('ERROR:' + e.message);
}
")

# 获取连接数
CONNECTIONS=$(docker-compose exec -T mongo-primary mongo -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin --quiet --eval "
var status = db.serverStatus();
print('CURRENT:' + status.connections.current);
print('AVAILABLE:' + status.connections.available);
")

# 输出监控数据
echo "=== MongoDB 集群状态 ==="
echo "$REPLICA_STATUS"
echo "=== 连接信息 ==="
echo "$CONNECTIONS"
echo "=== 备份状态 ==="
LATEST_BACKUP=$(find backups/ -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_TIME=$(echo "$LATEST_BACKUP" | cut -d' ' -f1)
    BACKUP_FILE=$(echo "$LATEST_BACKUP" | cut -d' ' -f2-)
    AGE_HOURS=$(( ($(date +%s) - ${BACKUP_TIME%.*}) / 3600 ))
    echo "LATEST_BACKUP:$(basename "$BACKUP_FILE") (${AGE_HOURS}h ago)"
else
    echo "LATEST_BACKUP:NONE"
fi
EOF

chmod +x /opt/1panel/scripts/mongodb-metrics.sh
```

### 3. 添加到1Panel监控

在1Panel中添加自定义监控：

1. **创建监控任务**
   - 系统设置 → 计划任务 → 添加
   - 任务名称: MongoDB状态监控
   - 执行周期: 每5分钟
   - 执行脚本: `/opt/1panel/scripts/mongodb-metrics.sh`

## 🔧 备份恢复操作

### 1. 通过1Panel恢复

#### 查看可用备份
```bash
# 列出所有备份
ls -la /opt/1panel/backup/mongodb/

# 查看备份详情
tar -tzf /opt/1panel/backup/mongodb/20241223_090000.tar.gz | head -20
```

#### 恢复步骤
```bash
# 1. 停止MongoDB服务
cd /opt/1panel/apps/mongodb-cluster
docker-compose down

# 2. 清理现有数据 (谨慎操作!)
docker volume rm mongodb-cluster_mongo_primary_data
docker volume rm mongodb-cluster_mongo_secondary1_data
docker volume rm mongodb-cluster_mongo_secondary2_data

# 3. 重新启动容器
docker-compose up -d

# 4. 等待容器启动
sleep 30

# 5. 恢复数据
BACKUP_FILE="/opt/1panel/backup/mongodb/20241223_090000.tar.gz"
TEMP_DIR="/tmp/mongo-restore"

# 解压备份文件
mkdir -p "$TEMP_DIR"
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# 执行恢复
docker-compose exec -T mongo-primary mongorestore \
    --host mongo-primary:27017 \
    --username admin \
    --password your_password \
    --authenticationDatabase admin \
    --gzip \
    --dir "$TEMP_DIR/$(basename "$BACKUP_FILE" .tar.gz)"

# 6. 清理临时文件
rm -rf "$TEMP_DIR"

# 7. 重新初始化副本集
./scripts/init-replica-set.sh
```

### 2. 1Panel GUI 恢复

在1Panel面板中进行可视化恢复：

1. **进入备份管理**
   - 系统设置 → 备份账号 → MongoDB备份

2. **选择恢复文件**
   - 选择要恢复的备份文件
   - 点击 "恢复" 按钮

3. **配置恢复选项**
   - 目标路径: `/opt/1panel/apps/mongodb-cluster/restore`
   - 恢复模式: 完整恢复
   - 确认恢复操作

## 📱 1Panel 移动端管理

### 安装1Panel移动应用
- iOS: App Store 搜索 "1Panel"
- Android: Google Play 或1Panel官网下载

### 移动端功能
- 📊 实时监控容器状态
- 🔄 远程重启服务
- 📋 查看日志
- 📦 管理备份
- 🚨 接收告警通知

## ⚠️ 故障排除

### 1Panel无法访问MongoDB容器
```bash
# 检查容器网络
docker network ls
docker network inspect 1panel-network

# 检查容器状态
cd /opt/1panel/apps/mongodb-cluster
docker-compose ps
```

### 备份同步失败
```bash
# 检查目录权限
ls -la /opt/1panel/backup/mongodb/
chown -R 1panel:1panel /opt/1panel/backup/mongodb/

# 检查磁盘空间
df -h /opt/1panel/backup/

# 检查备份脚本日志
tail -f /opt/1panel/backup/mongodb/backup.log
```

### 监控数据异常
```bash
# 重启1Panel服务
systemctl restart 1panel

# 检查监控脚本
/opt/1panel/scripts/mongodb-metrics.sh

# 清理监控缓存
rm -rf /opt/1panel/data/cache/monitor/*
```

## 📋 最佳实践

### 1. 安全配置
- 修改1Panel默认端口
- 启用HTTPS访问
- 配置防火墙规则
- 定期更新密码

### 2. 备份策略
- 配置多个备份存储
- 定期测试恢复流程
- 监控备份完整性
- 保留多个版本备份

### 3. 性能优化
- 定期清理旧日志
- 监控资源使用
- 调整备份时间窗口
- 使用SSD存储备份

---

**💡 提示**: 1Panel提供了强大的可视化管理功能，配合MongoDB集群可以大大简化运维工作！ 