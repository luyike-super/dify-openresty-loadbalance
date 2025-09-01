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
                name = "dify1",
                host = "172.20.62.200",
                port = 80,
                token = "app-9VSEFXR2qoMRoUHfmzxClGhe",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "dify2",
                host = "172.20.62.200",
                port = 80,
                token = "app-kwMz2oOx7WZpiP4buVFoMwcf",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "dify3",
                host = "172.20.62.200",
                port = 80,
                token = "app-kwMz2oOx7WZpiP4buVFoMwcf",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            }
        }
    },

    -- 内容生成应用
    content_generator = {
        user_tokens = {
            "user-token-content-generator-v1",
            "user-token-content-generator-v2"
        },
        instances = {
            {
                name = "cg_dify1",
                host = "192.168.1.20",
                port = 5001,
                token = "app-YOUR-CONTENT-GENERATOR-TOKEN-1",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "cg_dify2",
                host = "192.168.1.21",
                port = 5001,
                token = "app-YOUR-CONTENT-GENERATOR-TOKEN-2", 
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "cg_dify3",
                host = "192.168.1.22",
                port = 5001,
                token = "app-YOUR-CONTENT-GENERATOR-TOKEN-3",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            }
        }
    },

    -- 数据分析应用
    data_analysis = {
        user_tokens = {
            "user-token-data-analysis-v1",
            "user-token-data-analysis-v2"
        },
        instances = {
            {
                name = "da_dify1",
                host = "192.168.1.30",
                port = 5001,
                token = "app-YOUR-DATA-ANALYSIS-TOKEN-1",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "da_dify2",
                host = "192.168.1.31",
                port = 5001,
                token = "app-YOUR-DATA-ANALYSIS-TOKEN-2",
                weight = 1,
                max_fails = 3,
                fail_timeout = 30
            },
            {
                name = "da_dify3",
                host = "192.168.1.32",
                port = 5001,
                token = "app-YOUR-DATA-ANALYSIS-TOKEN-3",
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