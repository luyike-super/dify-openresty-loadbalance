# Form-Data 支持扩展

## 概述

本扩展为 Dify OpenResty 负载均衡器添加了对 `multipart/form-data` 格式请求中 `user` 参数的支持，使得文件上传等场景下的负载均衡更加便捷。

## 新增功能

### 支持的用户ID获取方式

现在负载均衡器支持以下5种方式获取用户ID（按优先级排序）：

1. **HTTP请求头** `X-User-ID`
2. **URL参数** `user_id`
3. **Cookie** `user_id`
4. **JSON请求体** 中的 `user` 字段
5. **Form-Data** 中的 `user` 字段 ⭐ **新增**

### 使用示例

#### 文件上传（使用form-data中的user参数）

```bash
curl -X POST 'http://localhost:82/v1/files/upload' \
  --header 'Authorization: Bearer {api_key}' \
  --form 'user=abc-123' \
  --form 'file=@localfile.png;type=image/png'
```

#### 其他支持的方式

```bash
# 方式1: 使用HTTP头
curl -X POST 'http://localhost:82/v1/files/upload' \
  --header 'Authorization: Bearer {api_key}' \
  --header 'X-User-ID: abc-123' \
  --form 'file=@localfile.png;type=image/png'

# 方式2: 使用URL参数
curl -X POST 'http://localhost:82/v1/files/upload?user_id=abc-123' \
  --header 'Authorization: Bearer {api_key}' \
  --form 'file=@localfile.png;type=image/png'

# 方式3: JSON请求
curl -X POST 'http://localhost:82/v1/chat-messages' \
  --header 'Authorization: Bearer {api_key}' \
  --header 'Content-Type: application/json' \
  --data '{"user": "abc-123", "query": "Hello"}'
```

## 技术实现

### 核心修改

1. **扩展 `get_user_id()` 函数**
   - 位置: `openresty/lua/loadbalancer.lua`
   - 添加了对 `multipart/form-data` 的检测和解析

2. **新增 `parse_form_data_user()` 函数**
   - 解析 multipart/form-data 格式的请求体
   - 提取 boundary 分隔符
   - 查找 `name="user"` 的字段并返回其值

3. **更新错误信息**
   - 位置: `openresty/conf/conf.d/dify-loadbalancer.conf`
   - 更新了用户ID缺失时的错误提示信息

### 解析流程

```
1. 检测 Content-Type 是否包含 "multipart/form-data"
2. 从 Content-Type 中提取 boundary 参数
3. 使用 boundary 分割请求体
4. 遍历每个 part，查找 name="user" 的字段
5. 提取并返回 user 字段的值
```

## 测试

### 运行测试脚本

```bash
# 给测试脚本执行权限
chmod +x scripts/test_form_data.sh

# 运行测试
./scripts/test_form_data.sh
```

### 测试内容

测试脚本会验证以下场景：

1. ✅ 使用 form-data 中的 user 参数
2. ✅ 使用 X-User-ID 头（对比测试）
3. ✅ 不提供 user 参数（应返回400错误）

### 手动测试

```bash
# 测试1: form-data方式
curl -v -X POST 'http://localhost:82/v1/files/upload' \
  --header 'Authorization: Bearer your-api-key' \
  --form 'user=test-user-123' \
  --form 'file=@test.png;type=image/png'

# 测试2: 检查负载均衡状态
curl http://localhost:82/status
```

## 配置要求

### 1. 确保配置文件正确

复制示例配置：
```bash
cp examples/config_example.lua openresty/lua/config.lua
```

编辑 `openresty/lua/config.lua`，配置你的应用实例。

### 2. 启动负载均衡器

```bash
docker-compose up -d
```

### 3. 验证服务状态

```bash
# 检查健康状态
curl http://localhost:82/health

# 检查负载均衡状态
curl http://localhost:82/status
```

## 性能考虑

### 解析性能

- Form-data 解析是纯 Lua 实现，性能良好
- 只在检测到 `multipart/form-data` 时才进行解析
- 解析过程中会缓存 boundary，避免重复计算

### 内存使用

- 解析过程中会读取完整请求体到内存
- 对于大文件上传，建议设置合适的 `client_max_body_size`
- 当前配置支持最大 100MB 的请求体

## 故障排除

### 常见问题

1. **返回400错误：User ID required**
   - 检查是否正确设置了 `user` 参数
   - 确认 Content-Type 包含 `multipart/form-data`
   - 验证 form 数据格式是否正确

2. **返回401错误：Invalid authorization token**
   - 检查 Authorization 头是否正确
   - 确认 API Key 在 config.lua 中已配置

3. **返回503错误：Service temporarily unavailable**
   - 检查后端 Dify 实例是否正常运行
   - 验证网络连接是否正常
   - 查看负载均衡器日志

### 调试方法

1. **查看日志**
   ```bash
   docker-compose logs -f openresty-dify-lb
   ```

2. **检查请求头**
   - 负载均衡器会添加调试头信息
   - 查看 `X-App-Type`, `X-User-ID-Used`, `X-Hash-Key` 等

3. **测试解析功能**
   ```bash
   # 使用 -v 参数查看详细请求信息
   curl -v -X POST 'http://localhost:82/v1/files/upload' \
     --header 'Authorization: Bearer test-token' \
     --form 'user=debug-user' \
     --form 'file=@small-test-file.txt'
   ```

## 兼容性

- ✅ 向后兼容：现有的所有用户ID获取方式仍然有效
- ✅ 性能影响：只在 multipart/form-data 请求时才进行额外解析
- ✅ 标准兼容：严格按照 RFC 7578 multipart/form-data 标准实现

## 更新日志

### v1.1.0 (当前版本)
- ✨ 新增 multipart/form-data 中 user 参数支持
- 🔧 优化错误信息提示
- 📝 添加测试脚本和文档
- 🐛 修复边界情况下的解析问题

---

如有问题或建议，请查看项目文档或提交 Issue。