# 1Panel 计划任务集成指南

本指南详细说明如何使用1Panel的计划任务功能来管理MongoDB集群的自动备份，实现通过Web界面方便地启用/禁用和监控备份任务。

## 🎯 集成优势

### ✅ **Web界面管理**
- 🖥️ 通过1Panel界面创建、编辑、删除备份任务
- 🔄 一键启用/禁用备份功能
- 📊 查看任务执行历史和状态
- 📝 实时查看执行日志

### ✅ **统一管理**
- 📋 与其他系统任务统一管理
- 🔔 集成1Panel的通知系统
- 📈 任务执行统计和报告
- 🔒 基于1Panel的权限控制

## 🚀 快速配置

### 1. 脚本准备

确保MongoDB集群已通过Git方式部署：

```bash
# 如果还未部署，先进行Git部署
git clone <repository-url>
cd mongodb-cluster
./deploy.sh

# 给计划任务脚本执行权限
chmod +x scripts/1panel-cron-backup.sh
```

### 2. 在1Panel中创建计划任务

#### 方式一：通过1Panel界面创建

1. **登录1Panel管理面板**
2. **进入「计划任务」页面**
3. **点击「创建任务」**
4. **填写任务信息**：

```
任务名称: MongoDB自动备份
任务类型: Shell脚本
执行周期: 自定义 (Cron表达式)
Cron表达式: 0 2 * * *  (每天凌晨2点执行)
脚本内容: /path/to/mongodb-cluster/scripts/1panel-cron-backup.sh
```

#### 方式二：通过API创建

```bash
# 使用1Panel API创建计划任务
curl -X POST "http://localhost:8080/api/v1/cron" \
  -H "Authorization: Bearer your_api_token" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "MongoDB自动备份",
    "type": "shell", 
    "spec": "0 2 * * *",
    "command": "/path/to/mongodb-cluster/scripts/1panel-cron-backup.sh",
    "status": "enable"
  }'
```

## 📋 详细配置步骤

### 1. 获取正确的脚本路径

```bash
# 查找MongoDB集群部署路径
find / -name "mongodb-cluster" -type d 2>/dev/null

# 示例输出
/opt/1panel/apps/mongodb-cluster
/home/user/mongodb-cluster

# 完整脚本路径示例
/opt/1panel/apps/mongodb-cluster/scripts/1panel-cron-backup.sh
```

### 2. 1Panel计划任务配置详解

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| **任务名称** | 显示在任务列表中的名称 | `MongoDB集群备份` |
| **任务类型** | 执行类型 | `Shell脚本` |
| **执行周期** | 备份频率 | `自定义` |
| **Cron表达式** | 具体执行时间 | `0 2 * * *` |
| **脚本路径** | 1Panel专用脚本 | `完整绝对路径` |
| **超时时间** | 备份超时限制 | `3600秒` |
| **重试次数** | 失败后重试 | `2次` |
| **状态** | 是否启用 | `启用` |

### 3. Cron表达式示例

```bash
# 每天凌晨2点
0 2 * * *

# 每12小时一次
0 */12 * * *

# 每周日凌晨3点
0 3 * * 0

# 每月1号凌晨1点
0 1 1 * *

# 工作日每天晚上11点
0 23 * * 1-5
```

## 🔧 高级配置选项

### 1. 环境变量配置

在1Panel界面的脚本内容中，可以设置环境变量：

```bash
#!/bin/bash
# 设置项目路径
export PROJECT_PATH="/opt/1panel/apps/mongodb-cluster"

# 设置特殊配置
export BACKUP_RETENTION_DAYS=7
export ENABLE_BUCKET_BACKUP=true

# 执行备份脚本
cd "$PROJECT_PATH"
./scripts/1panel-cron-backup.sh
```

### 2. 条件执行

```bash
#!/bin/bash
# 仅在工作时间外执行备份
current_hour=$(date +%H)
if [ $current_hour -lt 8 ] || [ $current_hour -gt 18 ]; then
    /path/to/mongodb-cluster/scripts/1panel-cron-backup.sh
else
    echo "跳过备份：当前为工作时间"
fi
```

### 3. 多环境支持

```bash
#!/bin/bash
# 根据环境变量选择不同配置
ENVIRONMENT=${ENVIRONMENT:-production}

case $ENVIRONMENT in
    "production")
        PROJECT_PATH="/opt/mongodb-prod"
        ;;
    "staging") 
        PROJECT_PATH="/opt/mongodb-staging"
        ;;
    *)
        PROJECT_PATH="/opt/mongodb-dev"
        ;;
esac

cd "$PROJECT_PATH"
./scripts/1panel-cron-backup.sh
```

## 📊 监控和管理

### 1. 任务执行监控

在1Panel界面中可以：

- 📈 **查看执行历史** - 最近执行记录和状态
- 📝 **实时日志** - 任务执行过程的详细日志
- 📊 **执行统计** - 成功率、平均执行时间等
- 🔔 **失败告警** - 任务失败时的通知设置

### 2. 日志管理

#### 1Panel系统日志
```bash
# 查看1Panel计划任务日志
tail -f /opt/1panel/data/logs/cron.log

# 查看特定任务日志
grep "MongoDB" /opt/1panel/data/logs/cron.log
```

#### 备份专用日志
```bash
# 查看1Panel专用备份日志
tail -f /path/to/mongodb-cluster/logs/cron-backup.log

# 查看备份执行历史
grep "备份任务" /path/to/mongodb-cluster/logs/cron-backup.log
```

### 3. 状态检查命令

```bash
# 检查环境和配置
/path/to/mongodb-cluster/scripts/1panel-cron-backup.sh --check

# 查看备份状态
/path/to/mongodb-cluster/scripts/1panel-cron-backup.sh --status

# 测试运行（不执行实际备份）
/path/to/mongodb-cluster/scripts/1panel-cron-backup.sh --test
```

## 🔄 任务管理操作

### 1. 启用/禁用任务

#### 通过1Panel界面
1. 进入「计划任务」页面
2. 找到MongoDB备份任务
3. 点击状态切换按钮

#### 通过API
```bash
# 启用任务
curl -X PUT "http://localhost:8080/api/v1/cron/{task_id}/enable" \
  -H "Authorization: Bearer your_token"

# 禁用任务
curl -X PUT "http://localhost:8080/api/v1/cron/{task_id}/disable" \
  -H "Authorization: Bearer your_token"
```

### 2. 手动执行任务

#### 通过1Panel界面
1. 在任务列表中点击「立即执行」
2. 查看执行结果和日志

#### 通过命令行
```bash
# 直接执行备份脚本
/path/to/mongodb-cluster/scripts/1panel-cron-backup.sh

# 强制执行（忽略环境检查）
/path/to/mongodb-cluster/scripts/1panel-cron-backup.sh --force
```

### 3. 修改任务配置

```bash
# 通过API更新任务
curl -X PUT "http://localhost:8080/api/v1/cron/{task_id}" \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json" \
  -d '{
    "spec": "0 1 * * *",  # 修改为每天凌晨1点
    "command": "/new/path/to/backup/script.sh"
  }'
```

## 🔔 通知配置

### 1. 1Panel内置通知

在1Panel的通知设置中配置：

- 📧 **邮件通知** - 任务执行结果邮件
- 💬 **微信通知** - 企业微信或微信推送
- 📱 **Webhook** - 自定义HTTP通知
- 📞 **短信通知** - SMS告警

### 2. 自定义通知

在环境配置中添加：

```bash
# Webhook通知
ALERT_WEBHOOK=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# 邮件通知
ALERT_EMAIL=admin@example.com

# 企业微信
WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY
```

## 🚨 故障排除

### 1. 常见问题

#### 任务无法执行
```bash
# 检查脚本权限
ls -la /path/to/mongodb-cluster/scripts/1panel-cron-backup.sh

# 给予执行权限
chmod +x /path/to/mongodb-cluster/scripts/1panel-cron-backup.sh
```

#### 环境变量问题
```bash
# 在1Panel脚本中显式设置PATH
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

# 设置Docker命令路径
export PATH=$PATH:/usr/local/bin
```

#### 权限不足
```bash
# 确保1Panel运行用户有Docker权限
sudo usermod -aG docker 1panel

# 重启1Panel服务
sudo systemctl restart 1panel
```

### 2. 调试模式

```bash
# 启用详细日志
DEBUG_MODE=true /path/to/mongodb-cluster/scripts/1panel-cron-backup.sh

# 手动测试
bash -x /path/to/mongodb-cluster/scripts/1panel-cron-backup.sh --test
```

### 3. 日志分析

```bash
# 分析失败原因
grep "错误\|失败\|ERROR" /path/to/mongodb-cluster/logs/cron-backup.log

# 查看最近执行情况
tail -50 /path/to/mongodb-cluster/logs/cron-backup.log
```

## 📈 最佳实践

### 1. 备份策略建议

```bash
# 生产环境：每天备份
Cron: 0 2 * * *  

# 开发环境：每周备份
Cron: 0 2 * * 0

# 测试环境：手动备份
状态: 禁用（需要时手动执行）
```

### 2. 资源管理

- 🕒 **避开高峰** - 选择业务低峰时间执行
- 💾 **磁盘空间** - 监控备份目录磁盘使用率
- 🔄 **并发控制** - 避免多个备份任务同时运行
- ⏱️ **超时设置** - 合理设置任务超时时间

### 3. 安全考虑

- 🔐 **脚本权限** - 最小权限原则
- 📝 **日志安全** - 避免在日志中记录敏感信息
- 🔒 **访问控制** - 限制脚本文件访问权限
- 🛡️ **网络安全** - 存储桶访问使用VPC端点

## 📞 技术支持

### 相关文档
- 📖 **[主要文档](README.md)** - MongoDB集群完整文档
- 🎯 **[Git部署指南](GIT_DEPLOY.md)** - Git仓库部署方式
- 📦 **[存储桶备份](BUCKET_BACKUP.md)** - 对象存储配置
- 🎛️ **[1Panel集成](1PANEL_INTEGRATION.md)** - 1Panel详细集成

### 获取帮助
- 💡 **查看脚本帮助**: `./scripts/1panel-cron-backup.sh --help`
- 📋 **检查配置**: `./scripts/1panel-cron-backup.sh --check`
- 📊 **查看状态**: `./scripts/1panel-cron-backup.sh --status`

---

**✨ 提示**: 使用1Panel计划任务管理MongoDB备份，可以获得Web界面的便利性和专业的任务调度能力，特别适合生产环境的运维管理。 