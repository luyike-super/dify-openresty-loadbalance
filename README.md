# Dify OpenResty 负载均衡器

一个基于 OpenResty 的高性能 Dify AI 应用负载均衡器，支持多应用、多实例的智能路由和负载均衡。

## 🏗️ 系统架构

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

### 详细架构图

```
Internet 
     ↓ 
 [Nginx Load Balancer] 
     ↓ 
 ┌─────────┬─────────┬─────────┐ 
 │ Dify-1  │ Dify-2  │ Dify-3  │ 
 └─────────┴─────────┴─────────┘ 
     ↓         ↓         ↓ 
 [共享PostgreSQL数据库集群] 
     ↓ 
 [共享Redis集群] 
     ↓ 
 [共享向量数据库]
```

## ✨ 核心特性

- **🎯 智能路由**: 基于 Token 自动识别应用类型并路由到对应实例
- **⚖️ 负载均衡**: 采用一致性哈希算法实现高效负载分布
- **🔄 故障转移**: 自动检测实例健康状态，故障时自动切换
- **📊 实时监控**: 提供详细的统计信息和健康检查接口
- **🚀 高性能**: 针对 x86_64 架构优化，支持高并发处理
- **📁 多格式支持**: 支持 JSON、Form-Data 等多种请求格式
- **🔧 灵活配置**: 支持多应用、多实例的灵活配置

## 🎯 适用场景

- **多应用部署**: 企业需要同时运行多个 AI 应用（智能客服、内容生成、数据分析等）
- **高并发处理**: 单个应用实例无法满足大量并发请求
- **高可用要求**: 需要避免单点故障，确保服务连续性
- **用户隔离**: 不同用户或租户需要访问不同的应用实例
- **资源优化**: 根据不同应用特点进行资源分配和负载分担

## 🚀 快速开始

### 环境要求

- Docker & Docker Compose
- 至少 4GB 内存
- x86_64 架构（推荐）

### 安装部署

1. **克隆项目**
```bash
git clone <repository-url>
cd dify-openresty-loadbalancer
```

2. **配置应用**
```bash
# 复制配置示例
cp examples/config_example.lua openresty/lua/config.lua

# 编辑配置文件
vim openresty/lua/config.lua
```

3. **启动服务**
```bash
docker-compose up -d
```

4. **验证部署**
```bash
# 检查服务状态
curl http://localhost:82/health

# 查看统计信息
curl http://localhost:82/status
```

## ⚙️ 配置说明

### 应用配置结构

```lua
config.applications = {
    -- 应用名称
    customer_service = {
        -- 用户Token列表（用于识别应用类型）
        user_tokens = {
            "usertoken--customer-service-v1"
        },
        -- 后端实例列表
        instances = {
            {
                name = "dify1",
                host = "172.20.62.200",
                port = 80,
                token = "app-9VSEFXR2qoMRoUHfmzxClGhe",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            }
        }
    }
}
```

### 一致性哈希配置

```lua
config.consistent_hash = {
    virtual_nodes = 150,      -- 虚拟节点数量
    hash_algorithm = "crc32"  -- 哈希算法: crc32, md5, sha1
}
```

## 🔌 API 接口

### 健康检查

```bash
GET /health
```

响应示例：
```json
{
    "status": "ok",
    "timestamp": "2024-01-01T12:00:00Z"
}
```

### 统计信息

```bash
GET /status
```

响应示例：
```json
{
    "applications": {
        "customer_service": {
            "total_requests": 1000,
            "instances": {
                "dify1": {
                    "requests": 334,
                    "status": "healthy"
                }
            }
        }
    }
}
```

## 📝 使用示例

### 基本请求

```bash
curl -X POST 'http://localhost:82/v1/chat-messages' \
  --header 'Authorization: Bearer usertoken--customer-service-v1' \
  --header 'Content-Type: application/json' \
  --data '{
    "inputs": {},
    "query": "Hello, how are you?",
    "user": "user-123",
    "response_mode": "blocking"
  }'
```

### 文件上传（Form-Data）

```bash
curl -X POST 'http://localhost:82/v1/files/upload' \
  --header 'Authorization: Bearer usertoken--customer-service-v1' \
  --form 'user=user-123' \
  --form 'file=@localfile.png;type=image/png'
```

### 支持的用户ID获取方式

负载均衡器支持以下5种方式获取用户ID（按优先级排序）：

1. **HTTP请求头** `X-User-ID`
2. **URL参数** `user_id`
3. **Cookie** `user_id`
4. **JSON请求体** 中的 `user` 字段
5. **Form-Data** 中的 `user` 字段

## 📊 监控与运维

### 日志查看

```bash
# 查看容器日志
docker-compose logs -f openresty-dify-lb

# 查看访问日志
tail -f openresty/logs/access.log

# 查看错误日志
tail -f openresty/logs/error.log
```

### 性能监控

- **CPU使用率**: 通过 `docker stats` 监控
- **内存使用**: 通过 `docker stats` 监控
- **请求统计**: 通过 `/status` 接口获取
- **健康状态**: 通过 `/health` 接口检查

### 故障排查

1. **检查配置文件语法**
```bash
docker-compose exec openresty-dify-lb nginx -t
```

2. **重新加载配置**
```bash
docker-compose exec openresty-dify-lb nginx -s reload
```

3. **查看实例健康状态**
```bash
curl http://localhost:82/status | jq
```

## 🔧 高级配置

### 性能优化

针对 x86_64 架构的性能优化配置：

- **Worker进程**: 自动根据CPU核心数设置
- **连接数**: 支持最大8192并发连接
- **内存优化**: 使用共享字典缓存配置和统计信息
- **CPU亲和性**: 自动绑定CPU核心

### SSL/HTTPS 支持

1. 将SSL证书放置在 `openresty/ssl/` 目录
2. 修改 `nginx.conf` 配置SSL
3. 重启服务

### 自定义健康检查

可以通过修改 `loadbalancer.lua` 中的健康检查逻辑来自定义检查规则。

## 📚 文档参考

- [Form-Data 支持说明](FORM_DATA_SUPPORT.md)
- [详细技术文档](dify.md)
- [配置示例](examples/config_example.lua)

## 🤝 贡献指南

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🆘 支持与反馈

如果您在使用过程中遇到问题或有改进建议，请：

1. 查看 [Issues](../../issues) 中是否有类似问题
2. 创建新的 Issue 描述问题
3. 提供详细的错误日志和配置信息

---

**注意**: 请确保在生产环境中使用前充分测试配置，并根据实际负载情况调整性能参数。