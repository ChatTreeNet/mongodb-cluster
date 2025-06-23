# 存储桶备份配置指南

本指南详细说明如何配置MongoDB集群的存储桶备份功能，支持Git部署方式与1Panel存储桶的完美集成。

## 🎯 支持的存储桶类型

- ✅ **AWS S3** - Amazon Simple Storage Service
- ✅ **阿里云 OSS** - Object Storage Service  
- ✅ **腾讯云 COS** - Cloud Object Storage
- ✅ **MinIO** - 自建对象存储服务

## 🚀 快速配置

### 1. 编辑环境配置

编辑 `.env` 文件（Git部署时会自动生成）：

```bash
# 启用存储桶备份
ENABLE_BUCKET_BACKUP=true

# 选择存储桶类型
BUCKET_TYPE=s3    # s3/oss/cos/minio

# 存储桶基本配置
BUCKET_NAME=mongodb-backups
BUCKET_REGION=us-east-1
BUCKET_PATH_PREFIX=mongodb-cluster
```

### 2. 配置访问凭证

```bash
# 访问密钥
BUCKET_ACCESS_KEY=your_access_key
BUCKET_SECRET_KEY=your_secret_key

# 自定义端点（可选）
BUCKET_ENDPOINT=https://s3.amazonaws.com
```

## 📋 详细配置指南

### AWS S3 配置

```bash
# S3 配置示例
ENABLE_BUCKET_BACKUP=true
BUCKET_TYPE=s3
BUCKET_NAME=my-mongodb-backups
BUCKET_REGION=us-west-2
BUCKET_ACCESS_KEY=YOUR_AWS_ACCESS_KEY_ID
BUCKET_SECRET_KEY=YOUR_AWS_SECRET_ACCESS_KEY
BUCKET_PATH_PREFIX=production/mongodb
BUCKET_USE_SSL=true
```

**所需工具**: AWS CLI
```bash
# 安装 AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### 阿里云 OSS 配置

```bash
# OSS 配置示例
ENABLE_BUCKET_BACKUP=true
BUCKET_TYPE=oss
BUCKET_NAME=my-mongodb-backups
BUCKET_REGION=oss-cn-beijing
BUCKET_ACCESS_KEY=LTAI5tREDACTEDACCESSKEY
BUCKET_SECRET_KEY=REDACTEDSECRETKEY12345678
BUCKET_PATH_PREFIX=production/mongodb
```

**所需工具**: ossutil
```bash
# 安装 ossutil
wget https://gosspublic.alicdn.com/ossutil/1.7.14/ossutil64
chmod +x ossutil64
sudo mv ossutil64 /usr/local/bin/ossutil
```

### 腾讯云 COS 配置

```bash
# COS 配置示例  
ENABLE_BUCKET_BACKUP=true
BUCKET_TYPE=cos
BUCKET_NAME=my-mongodb-backups-1234567890
BUCKET_REGION=ap-beijing
BUCKET_ACCESS_KEY=YOUR_TENCENT_CLOUD_ACCESS_KEY_ID
BUCKET_SECRET_KEY=YOUR_TENCENT_CLOUD_SECRET_ACCESS_KEY
BUCKET_PATH_PREFIX=production/mongodb
```

**所需工具**: coscli
```bash
# 安装 coscli
wget https://github.com/tencentyun/coscli/releases/download/v0.13.0-beta/coscli-linux
chmod +x coscli-linux
sudo mv coscli-linux /usr/local/bin/coscli
```

### MinIO 配置

```bash
# MinIO 配置示例
ENABLE_BUCKET_BACKUP=true
BUCKET_TYPE=minio
BUCKET_NAME=mongodb-backups
BUCKET_ENDPOINT=https://minio.example.com:9000
BUCKET_ACCESS_KEY=YOUR_MINIO_ACCESS_KEY
BUCKET_SECRET_KEY=YOUR_MINIO_SECRET_KEY
BUCKET_PATH_PREFIX=production/mongodb
BUCKET_USE_SSL=true
```

**所需工具**: MinIO Client
```bash
# 安装 MinIO Client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
```

## 🔧 高级配置选项

### SSL/TLS 配置

```bash
# 启用 SSL
BUCKET_USE_SSL=true

# 强制路径样式（某些S3兼容服务需要）
BUCKET_FORCE_PATH_STYLE=false
```

### 路径配置

```bash
# 自定义备份路径前缀
BUCKET_PATH_PREFIX=environments/production/mongodb

# 最终存储路径示例:
# s3://my-bucket/environments/production/mongodb/20240115_143022.tar.gz
```

## 🛠️ 1Panel 集成

### 方式一：通过1Panel界面配置

1. **登录1Panel面板**
2. **进入「应用商店」→「已安装」**
3. **找到MongoDB容器应用**
4. **编辑环境变量**，添加存储桶配置
5. **重启应用**

### 方式二：直接编辑配置文件

```bash
# 编辑 .env 文件
vi /opt/1panel/apps/mongodb-cluster/.env

# 添加存储桶配置
ENABLE_BUCKET_BACKUP=true
BUCKET_TYPE=s3
# ... 其他配置

# 重启服务
cd /opt/1panel/apps/mongodb-cluster
docker-compose restart
```

### 方式三：使用1Panel API

```bash
# 通过1Panel API更新环境变量
curl -X POST "http://localhost:8080/api/v1/apps/mongodb/env" \
  -H "Authorization: Bearer your_api_token" \
  -H "Content-Type: application/json" \
  -d '{
    "ENABLE_BUCKET_BACKUP": "true",
    "BUCKET_TYPE": "s3",
    "BUCKET_NAME": "mongodb-backups"
  }'
```

## 📊 备份策略建议

### 存储桶命名规范

```bash
# 推荐命名格式
BUCKET_NAME=company-mongodb-backups-env
BUCKET_PATH_PREFIX=cluster-name/YYYY/MM

# 示例
BUCKET_NAME=acme-mongodb-backups-prod
BUCKET_PATH_PREFIX=main-cluster/2024/01
```

### 多环境管理

```bash
# 生产环境
BUCKET_PATH_PREFIX=production/mongodb
# 测试环境  
BUCKET_PATH_PREFIX=staging/mongodb
# 开发环境
BUCKET_PATH_PREFIX=development/mongodb
```

### 备份保留策略

结合本地备份和云存储：

```bash
# 本地保留7天
BACKUP_RETENTION_DAYS=7

# 云存储配置生命周期策略（在存储桶控制台配置）:
# - 标准存储: 30天
# - 归档存储: 1年  
# - 冷归档: 永久
```

## 🔍 验证配置

### 手动测试备份

```bash
# 测试备份脚本
cd /path/to/mongodb-cluster
./scripts/backup.sh

# 检查日志
tail -f backups/backup.log

# 验证存储桶
aws s3 ls s3://your-bucket/mongodb-cluster/
```

### 检查存储桶权限

```bash
# S3 权限检查
aws s3api head-bucket --bucket your-bucket-name

# OSS 权限检查  
ossutil ls oss://your-bucket-name

# COS 权限检查
coscli ls cos://your-bucket-name
```

## ⚡ 自动化部署配置

### Git 部署时自动配置

修改 `deploy.sh` 脚本，添加存储桶配置提示：

```bash
# 在 create_env_file 函数中添加
read -p "是否启用存储桶备份? [y/N]: " enable_bucket
if [[ "$enable_bucket" =~ ^[Yy]$ ]]; then
    sed -i "s/ENABLE_BUCKET_BACKUP=false/ENABLE_BUCKET_BACKUP=true/g" .env
    
    echo "请选择存储桶类型:"
    echo "1) AWS S3"
    echo "2) 阿里云 OSS"  
    echo "3) 腾讯云 COS"
    echo "4) MinIO"
    read -p "请输入选项 [1-4]: " bucket_choice
    
    case $bucket_choice in
        1) sed -i "s/BUCKET_TYPE=s3/BUCKET_TYPE=s3/g" .env ;;
        2) sed -i "s/BUCKET_TYPE=s3/BUCKET_TYPE=oss/g" .env ;;
        3) sed -i "s/BUCKET_TYPE=s3/BUCKET_TYPE=cos/g" .env ;;
        4) sed -i "s/BUCKET_TYPE=s3/BUCKET_TYPE=minio/g" .env ;;
    esac
fi
```

## 📱 监控和告警

### 备份状态监控

```bash
# 检查最近备份状态
grep "backup_id" backups/backup_summary.json | tail -5

# 监控存储桶大小
aws s3 ls s3://your-bucket/mongodb-cluster/ --summarize --human-readable
```

### 失败告警

备份脚本支持 Webhook 通知：

```bash
# 配置告警 Webhook
ALERT_WEBHOOK=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# 或者邮件通知
ALERT_EMAIL=admin@example.com
```

## 🔒 安全最佳实践

### 1. 访问密钥管理

- ✅ 使用最小权限原则
- ✅ 定期轮换访问密钥
- ✅ 使用 IAM 角色（云服务器）
- ✅ 加密存储配置

### 2. 网络安全

```bash
# VPC 端点（AWS）
BUCKET_ENDPOINT=https://vpce-xxx.s3.us-west-2.vpce.amazonaws.com

# 私有端点（阿里云）
BUCKET_ENDPOINT=https://oss-cn-beijing-internal.aliyuncs.com
```

### 3. 数据加密

- ✅ 传输加密：HTTPS
- ✅ 存储加密：服务端加密
- ✅ 备份文件加密：GPG

```bash
# 启用备份文件加密（需要配置 GPG）
BACKUP_ENCRYPT=true
GPG_RECIPIENT=admin@example.com
```

## 🚨 故障排除

### 常见问题

1. **权限被拒绝**
   ```bash
   # 检查 IAM 策略
   aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::123456789012:user/username --action-names s3:PutObject --resource-arns arn:aws:s3:::bucket-name/*
   ```

2. **网络连接超时**
   ```bash
   # 测试网络连接
   curl -I https://s3.amazonaws.com
   telnet s3.amazonaws.com 443
   ```

3. **存储桶不存在**
   ```bash
   # 创建存储桶
   aws s3 mb s3://your-bucket-name --region us-west-2
   ```

4. **工具未安装**
   ```bash
   # 检查工具安装
   which aws ossutil coscli mc
   ```

### 调试模式

```bash
# 启用详细日志
DEBUG_MODE=true

# 手动运行备份（详细输出）
bash -x ./scripts/backup.sh
```

## 📞 技术支持

如需帮助，请查看：

- 📖 **[主要文档](README.md)** - 完整项目文档
- 🎯 **[Git部署指南](GIT_DEPLOY.md)** - Git仓库部署方式
- 🎛️ **[1Panel集成](1PANEL_INTEGRATION.md)** - 1Panel详细集成
- 📊 **云服务商文档** - 各存储服务官方文档

---

**💡 提示**: 存储桶备份特别适合生产环境，能够提供异地容灾和长期存储能力。建议结合本地备份和云存储，形成多层备份策略。 