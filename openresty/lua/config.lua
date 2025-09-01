-- Dify应用配置文件
-- 这是主要的配置文件，修改此文件即可调整负载均衡策略

local config = {}

-- 应用配置
config.applications = {
    -- 智能客服应用
    customer_service = {
        user_tokens = {
            "usertoken--customer-service-v1"
        },
        instances = {
            {
                name = "dify2",
                host = "172.20.62.200",
                port = 80,
                token = "app-5aXypUODhQ3GonYXmP7hO4DE",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            }
        }
    }
}

-- 一致性Hash配置
config.consistent_hash = {
    virtual_nodes = 200,  -- x86可以支持更多虚拟节点
    hash_algorithm = "crc32"  -- 支持 crc32, md5
}

-- 限流配置（x86性能更强，可以设置更高的限制）
config.rate_limit = {
    per_user_per_app = {
        rate = "50r/s",  -- 提高限流阈值
        burst = 100
    },
    per_app = {
        rate = "500r/s", -- 提高限流阈值
        burst = 200
    },
    per_ip = {
        rate = "200r/s", -- 提高限流阈值
        burst = 100
    }
}

-- 健康检查配置
config.health_check = {
    interval = 30,        -- 检查间隔（秒）
    timeout = 10,         -- 超时时间（秒）
    healthy_threshold = 2, -- 连续成功次数判定为健康
    unhealthy_threshold = 3 -- 连续失败次数判定为不健康
}

return config