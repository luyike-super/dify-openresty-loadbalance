# Dify OpenResty 负载均衡器项目文档

## 📋 需求背景

### 业务场景

在企业级Dify AI应用部署中，单一实例往往无法满足高并发和高可用性的需求。特别是在以下场景下：

- **多应用场景**：企业需要同时运行多个AI应用（如智能客服、内容生成、数据分析等）
- **高并发需求**：单个应用实例无法处理大量并发请求
- **高可用要求**：需要避免单点故障，确保服务连续性
- **资源优化**：需要根据不同应用的特点进行资源分配和负载分担
- **用户隔离**：不同用户或租户需要访问不同的应用实例

### 技术挑战

1. **智能路由**：需要根据用户Token自动识别应用类型并路由到对应实例
2. **负载均衡**：需要实现高效的负载均衡算法，确保请求均匀分布
3. **故障转移**：当某个实例故障时，需要自动切换到健康实例
4. **性能优化**：需要针对x86_64架构进行性能优化
5. **监控统计**：需要实时监控各实例状态和请求分布

## 🔄 需求流程

### 用户请求流程

```
用户请求 → OpenResty负载均衡器 → Token解析 → 应用识别 → 一致性哈希选择实例 → 后端Dify实例 → 响应返回
```

### 详细流程说明

1. **请求接收**：OpenResty接收来自客户端的HTTP请求
2. **Token提取**：从Authorization头中提取Bearer Token
3. **应用识别**：根据Token匹配对应的应用类型（customer_service、content_generator等）
4. **实例选择**：使用一致性哈希算法选择最优后端实例
5. **健康检查**：验证选中实例的健康状态
6. **请求转发**：将请求代理到选中的后端实例
7. **响应处理**：处理后端响应并返回给客户端
8. **统计记录**：记录请求统计信息用于监控

### 故障处理流程

```
实例故障检测 → 标记实例不可用 → 重新选择健康实例 → 更新Hash环 → 继续服务
```

## 🏗️ 架构实现

### 整体架构

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   客户端应用    │───▶│  OpenResty负载均衡器  │───▶│  Dify实例集群   │
│  (Web/Mobile)   │    │   (一致性哈希算法)    │    │ (多应用多实例)  │
└─────────────────┘    └──────────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │  监控统计API │
                       │ (/status)    │
                       └──────────────┘
```

### 核心组件

#### 1. OpenResty负载均衡器
- **基础镜像**：`openresty/openresty:1.21.4.3-3-alpine-fat`
- **核心功能**：HTTP负载均衡、Lua脚本执行、SSL终端
- **性能优化**：针对x86_64架构优化，支持8192并发连接

#### 2. 一致性哈希算法
- **算法实现**：基于SHA-256的一致性哈希
- **虚拟节点**：每个物理节点对应160个虚拟节点
- **负载均衡**：确保请求均匀分布，支持节点动态添加/删除

#### 3. 应用配置管理
- **配置文件**：`config.lua`集中管理所有应用配置
- **动态重载**：支持通过API热重载配置
- **多应用支持**：支持多个独立的Dify应用实例

#### 4. 健康检查机制
- **主动检查**：定期检查后端实例健康状态
- **被动检查**：根据请求失败情况判断实例状态
- **故障转移**：自动剔除故障实例，恢复后自动加入

### 技术栈

- **Web服务器**：OpenResty (Nginx + LuaJIT)
- **负载均衡算法**：一致性哈希 (Consistent Hashing)
- **配置管理**：Lua配置文件
- **容器化**：Docker + Docker Compose
- **监控**：内置状态API + 日志记录

### 目录结构

```
dify-openresty-loadbalancer/
├── docker-compose.yml          # Docker编排文件
├── openresty/                  # OpenResty配置目录
│   ├── conf/                   # Nginx配置
│   │   ├── nginx.conf         # 主配置文件
│   │   └── conf.d/            # 虚拟主机配置
│   │       └── dify-loadbalancer.conf
│   ├── lua/                   # Lua脚本
│   │   ├── config.lua         # 应用配置
│   │   ├── loadbalancer.lua   # 负载均衡核心逻辑
│   │   └── consistent_hash.lua # 一致性哈希实现
│   ├── logs/                  # 日志目录
│   └── ssl/                   # SSL证书目录
└── scripts/                   # 部署脚本

## 🚀 如何使用

### 环境要求

- **操作系统**：Linux (推荐Ubuntu 20.04+)
- **架构**：x86_64
- **Docker**：20.10+
- **Docker Compose**：2.0+
- **内存**：建议4GB+
- **CPU**：建议4核+

### 快速开始

#### 1. 克隆项目

```bash
git clone <repository-url>
cd dify-openresty-loadbalancer
```

#### 2. 配置应用实例

编辑 `openresty/lua/config.lua` 文件，配置你的Dify应用实例：

```lua
config.applications = {
    -- 智能客服应用
    customer_service = {
        user_tokens = {
            "usertoken--customer-service-v1"
        },
        instances = {
            {
                name = "dify1",
                host = "172.20.62.200",  -- 你的Dify实例IP
                port = 80,
                token = "app-9VSEFXR2qoMRoUHfmzxClGhe",  -- 你的应用Token
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            }
            -- 添加更多实例...
        }
    }
    -- 添加更多应用...
}
```

#### 3. 启动服务

```bash
# 启动负载均衡器
docker-compose up -d

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

#### 4. 验证服务

```bash
# 健康检查
curl http://localhost:82/health

# 查看负载均衡状态
curl http://localhost:82/status
```

### 配置说明

#### 应用配置参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `name` | 实例名称 | `"dify1"` |
| `host` | 实例IP地址 | `"192.168.1.100"` |
| `port` | 实例端口 | `80` |
| `token` | Dify应用Token | `"app-xxx"` |
| `weight` | 权重 | `1` |
| `max_fails` | 最大失败次数 | `3` |
| `fail_timeout` | 失败超时时间(秒) | `30` |

#### 用户Token配置

每个应用需要配置对应的用户Token列表，用于识别请求应该路由到哪个应用：

```lua
user_tokens = {
    "user-token-1",
    "user-token-2"
}
```

### API接口

#### 1. 健康检查

```bash
GET /health
```

响应：
```
healthy
```

#### 2. 负载均衡状态

```bash
GET /status
```

响应：
```json
{
    "status": "running",
    "architecture": "x86_64",
    "algorithm": "consistent_hash",
    "stats": {
        "total_requests": 1000,
        "active_connections": 50
    },
    "timestamp": 1640995200
}
```

#### 3. 配置重载

```bash
GET /reload-config
```

响应：
```json
{
    "status": "success",
    "message": "Configuration reloaded"
}
```

### 客户端使用

#### 请求格式

客户端请求需要包含正确的Authorization头：

```bash
curl -X POST http://localhost:82/v1/chat-messages \
  -H "Authorization: Bearer usertoken--customer-service-v1" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": {},
    "query": "Hello",
    "response_mode": "streaming",
    "conversation_id": "",
    "user": "user-123"
  }'
```

#### 路由逻辑

1. 负载均衡器提取Bearer Token
2. 根据Token匹配对应的应用类型
3. 使用一致性哈希算法选择后端实例
4. 将请求转发到选中的实例

### 监控和日志

#### 日志查看

```bash
# 查看访问日志
docker-compose logs openresty-dify-lb

# 实时查看日志
docker-compose logs -f openresty-dify-lb

# 查看错误日志
docker exec dify-openresty-loadbalancer tail -f /var/log/openresty/error.log
```

#### 性能监控

```bash
# 查看容器资源使用
docker stats dify-openresty-loadbalancer

# 查看网络连接
docker exec dify-openresty-loadbalancer netstat -an | grep :80
```

### 故障排除

#### 常见问题

1. **服务无法启动**
   - 检查端口是否被占用：`netstat -tlnp | grep :82`
   - 检查配置文件语法：`docker-compose config`

2. **请求路由失败**
   - 检查Token配置是否正确
   - 查看错误日志：`docker-compose logs openresty-dify-lb`

3. **后端实例连接失败**
   - 检查后端实例是否正常运行
   - 验证网络连通性：`docker exec dify-openresty-loadbalancer ping <backend-ip>`

#### 配置热重载

修改配置后无需重启服务，可以通过API热重载：

```bash
# 修改配置文件后
curl http://localhost:82/reload-config
```

### 性能优化

#### x86_64架构优化

本项目针对x86_64架构进行了以下优化：

- **并发连接数**：支持8192并发连接
- **CPU亲和性**：自动绑定CPU核心
- **内存优化**：优化共享字典大小
- **网络优化**：启用sendfile、tcp_nopush等

#### 资源配置

在 `docker-compose.yml` 中可以调整资源限制：

```yaml
deploy:
  resources:
    limits:
      cpus: '4.0'    # CPU限制
      memory: 4G     # 内存限制
    reservations:
      cpus: '1.0'    # CPU预留
      memory: 1G     # 内存预留
```

### 扩展功能

#### 添加新应用

1. 在 `config.lua` 中添加新应用配置
2. 配置对应的用户Token
3. 添加后端实例信息
4. 重载配置：`curl http://localhost:82/reload-config`

#### SSL/HTTPS支持

1. 将SSL证书放入 `openresty/ssl/` 目录
2. 修改 `docker-compose.yml` 开放443端口
3. 在nginx配置中添加SSL配置

#### 自定义负载均衡算法

可以在 `consistent_hash.lua` 中实现自定义的负载均衡算法，如：
- 加权轮询
- 最少连接
- IP哈希

---

## 📞 技术支持

如有问题或建议，请通过以下方式联系：

- 项目Issues
- 技术文档
- 社区论坛

---

*本文档持续更新中，最后更新时间：2024年*

# 如果有自定义nginx配置
cp -r nginx /tmp/dify-backup/ 2>/dev/null || true
```

### 1.6 打包备份文件

```bash
# 创建完整备份包
cd /tmp
tar czf dify-migration-$(date +%Y%m%d-%H%M%S).tar.gz dify-backup/

# 显示备份包信息
ls -lh dify-migration-*.tar.gz
```

## 📦 第二步：传输备份到目标服务器

### 2.1 使用SCP传输（推荐）

```bash
# 从源服务器执行
scp /tmp/dify-migration-*.tar.gz username@target-server-ip:/tmp/

# 或者使用rsync（支持断点续传）
rsync -avz --progress /tmp/dify-migration-*.tar.gz username@target-server-ip:/tmp/
```

### 2.2 其他传输方式

```bash
# 如果网络不通，可以使用U盘等物理介质
# 或者通过中转服务器进行传输
```

## 🚀 第三步：目标服务器部署操作

### 3.1 准备目标服务器环境

```bash
# 安装Docker（如未安装）
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 安装Docker Compose（如未安装）
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 重新登录以应用docker组权限
sudo su - $USER
```

### 3.2 解压备份文件

```bash
# 解压备份包
cd /tmp
tar xzf dify-migration-*.tar.gz

# 查看备份内容
ls -la dify-backup/
```

### 3.3 导入Docker镜像

```bash
# 导入镜像
gunzip -c /tmp/dify-backup/dify-images.tar.gz | docker load

# 或者如果没有压缩
# docker load -i /tmp/dify-backup/dify-images.tar

# 验证镜像导入
docker images | grep -E "(dify|postgres|redis|nginx|weaviate)"
```

### 3.4 创建部署目录并恢复配置

```bash
# 创建Dify部署目录
mkdir -p /opt/dify
cd /opt/dify

# 复制配置文件
cp /tmp/dify-backup/docker-compose.yaml .
cp /tmp/dify-backup/.env .

# 如果有nginx配置
cp -r /tmp/dify-backup/nginx . 2>/dev/null || true
```

### 3.5 创建Docker卷并恢复数据

```bash
# 创建数据卷
docker volume create dify_db_data
docker volume create dify_redis_data
docker volume create dify_app_storage

# 恢复数据库数据
docker run --rm -v dify_db_data:/data -v /tmp/dify-backup:/backup alpine tar xzf /backup/dify-database.tar.gz -C /data

# 恢复Redis数据
docker run --rm -v dify_redis_data:/data -v /tmp/dify-backup:/backup alpine tar xzf /backup/dify-redis.tar.gz -C /data

# 恢复存储文件
docker run --rm -v dify_app_storage:/data -v /tmp/dify-backup:/backup alpine tar xzf /backup/dify-storage.tar.gz -C /data
```

### 3.6 修改配置文件（如需要）

```bash
# 编辑.env文件，更新服务器相关配置
nano .env

# 常需要修改的配置项：
# - 服务器IP地址
# - 域名配置
# - 端口配置
# - 外部服务地址等
```

### 3.7 启动Dify服务

```bash
# 启动服务
docker-compose up -d

# 查看启动状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

## ✅ 第四步：验证迁移结果

### 4.1 检查服务状态

```bash
# 检查所有容器是否正常运行
docker-compose ps

# 检查端口是否正常监听
netstat -tulpn | grep -E ":(80|443|5432|6379)"

# 检查容器日志
docker-compose logs api
docker-compose logs web
```

### 4.2 功能测试

```bash
# 测试API健康检查
curl http://localhost/health

# 测试Web界面（在浏览器中访问）
# http://your-server-ip 或 https://your-domain
```

### 4.3 数据完整性验证

- 登录管理后台检查用户数据
- 验证应用配置是否完整
- 检查上传的文件是否正常
- 测试AI对话功能

## 🔧 故障排除

### 常见问题解决

#### 1. 容器启动失败

```bash
# 查看详细错误日志
docker-compose logs [service-name]

# 检查端口冲突
sudo lsof -i :80
sudo lsof -i :443
```

#### 2. 数据库连接失败

```bash
# 检查数据库容器状态
docker-compose exec db psql -U postgres -d dify

# 重置数据库密码（如需要）
docker-compose exec db psql -U postgres -c "ALTER USER postgres PASSWORD 'your_password';"
```

#### 3. Redis连接问题

```bash
# 测试Redis连接
docker-compose exec redis redis-cli ping
```

#### 4. 存储权限问题

```bash
# 修复文件权限
sudo chown -R 1001:1001 /var/lib/docker/volumes/dify_app_storage/_data
```

## 🧹 清理工作

### 源服务器清理（确认迁移成功后）

```bash
# 删除备份文件
rm -rf /tmp/dify-backup
rm /tmp/dify-migration-*.tar.gz

# 如果确认不再使用，可以清理原部署
cd /path/to/old/dify
docker-compose down -v  # 注意：-v 会删除数据卷
```

### 目标服务器清理

```bash
# 删除临时备份文件
rm -rf /tmp/dify-backup
rm /tmp/dify-migration-*.tar.gz
```

## 📝 重要提醒

1. **在执行迁移前，请确保已经完整测试备份流程**
2. **建议在维护时间窗口进行迁移操作**
3. **迁移过程中Dify服务会暂时不可用**
4. **确认新服务器的防火墙和安全组配置正确**
5. **如使用域名，记得更新DNS记录**
6. **建议保留源服务器备份一段时间，以防需要回滚**


迁移完成后，记得更新相关文档和运维流程！
