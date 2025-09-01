-- Dify应用配置示例
-- 复制此文件到 openresty/lua/config.lua 并根据实际情况修改

local _M = {}

-- 一致性Hash配置
_M.consistent_hash = {
    virtual_nodes = 150,  -- 虚拟节点数量
    hash_algorithm = "crc32"  -- 哈希算法: crc32, md5, sha1
}

-- 应用配置
_M.applications = {
    -- 应用1: 智能客服
    ["customer_service"] = {
        -- 用户Token列表（用于识别应用类型）
        user_tokens = {
            "app-customer-service-token-1",
            "app-customer-service-token-2"
        },
        -- 后端实例列表
        instances = {
            {
                name = "dify-cs-1",
                host = "192.168.1.10",
                port = 5001,
                token = "app-real-dify-token-cs-1",  -- 真实的Dify API Token
                weight = 100,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "dify-cs-2",
                host = "192.168.1.11",
                port = 5001,
                token = "app-real-dify-token-cs-2",
                weight = 100,
                max_fails = 3,
                fail_timeout = 30
            }
        }
    },
    
    -- 应用2: 内容生成
    ["content_generation"] = {
        user_tokens = {
            "app-content-gen-token-1",
            "app-content-gen-token-2"
        },
        instances = {
            {
                name = "dify-cg-1",
                host = "192.168.1.20",
                port = 5001,
                token = "app-real-dify-token-cg-1",
                weight = 150,  -- 更高权重
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "dify-cg-2",
                host = "192.168.1.21",
                port = 5001,
                token = "app-real-dify-token-cg-2",
                weight = 100,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "dify-cg-3",
                host = "192.168.1.22",
                port = 5001,
                token = "app-real-dify-token-cg-3",
                weight = 100,
                max_fails = 3,
                fail_timeout = 30
            }
        }
    },
    
    -- 应用3: 数据分析
    ["data_analysis"] = {
        user_tokens = {
            "app-data-analysis-token-1"
        },
        instances = {
            {
                name = "dify-da-1",
                host = "192.168.1.30",
                port = 5001,
                token = "app-real-dify-token-da-1",
                weight = 100,
                max_fails = 3,
                fail_timeout = 30
            }
        }
    }
}

return _M

--[[
配置说明:

1. user_tokens: 客户端使用的Token，负载均衡器根据此Token识别应用类型
2. instances.token: 真实的Dify API Token，负载均衡器会替换客户端Token
3. weight: 实例权重，权重越高分配的请求越多
4. max_fails: 最大失败次数，超过后标记为不可用
5. fail_timeout: 失败超时时间（秒）

使用示例:

# 客户端请求（使用form-data）
curl -X POST 'http://localhost:82/v1/files/upload' \
  --header 'Authorization: Bearer app-customer-service-token-1' \
  --form 'user=user123' \
  --form 'file=@image.png;type=image/png'

# 客户端请求（使用header）
curl -X POST 'http://localhost:82/v1/files/upload' \
  --header 'Authorization: Bearer app-content-gen-token-1' \
  --header 'X-User-ID: user456' \
  --form 'file=@document.pdf;type=application/pdf'

# 客户端请求（使用URL参数）
curl -X POST 'http://localhost:82/v1/chat-messages?user_id=user789' \
  --header 'Authorization: Bearer app-data-analysis-token-1' \
  --header 'Content-Type: application/json' \
  --data '{"query": "分析这些数据", "inputs": {}}'
--]]