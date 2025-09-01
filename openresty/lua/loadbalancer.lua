-- Dify负载均衡核心逻辑 (x86优化版本)
local config = require "app.config"
local consistent_hash = require "app.consistent_hash"
local cjson = require "cjson"

local _M = {}
_M._VERSION = '0.1'

-- 初始化应用配置和Hash环
local function init_hash_rings()
    local hash_rings = {}

    for app_name, app_config in pairs(config.applications) do
        local nodes = app_config.instances
        local virtual_nodes = config.consistent_hash.virtual_nodes
        local algorithm = config.consistent_hash.hash_algorithm
        
        hash_rings[app_name] = consistent_hash.create_ring(nodes, virtual_nodes, algorithm)
    end

    return hash_rings
end

-- 缓存Hash环到共享字典
local function cache_hash_rings()
    local hash_rings = init_hash_rings()
    local hash_ring_dict = ngx.shared.hash_ring

    for app_name, ring in pairs(hash_rings) do
        -- 确保ring.ring中的节点对象能够正确序列化
        local serializable_ring = {}
        for hash_key, node in pairs(ring.ring) do
            serializable_ring[tostring(hash_key)] = {
                name = node.name,
                host = node.host,
                port = node.port,
                token = node.token,
                weight = node.weight,
                max_fails = node.max_fails,
                fail_timeout = node.fail_timeout
            }
        end
        
        local ring_data = cjson.encode({
            ring = serializable_ring,
            sorted_keys = ring.sorted_keys,
            algorithm = ring.algorithm
        })
        hash_ring_dict:set(app_name, ring_data)
    end

    ngx.log(ngx.INFO, "Hash rings cached successfully")
end

-- 从共享字典获取Hash环
local function get_hash_ring(app_name)
    local hash_ring_dict = ngx.shared.hash_ring
    local ring_data = hash_ring_dict:get(app_name)

    if not ring_data then
        -- 如果缓存中没有，重新初始化
        cache_hash_rings()
        ring_data = hash_ring_dict:get(app_name)
    end

    if ring_data then
        local success, decoded_ring = pcall(cjson.decode, ring_data)
        if success then
            -- 将字符串键转换回数字键
            local numeric_ring = {}
            for str_key, node in pairs(decoded_ring.ring) do
                local numeric_key = tonumber(str_key)
                if numeric_key then
                    numeric_ring[numeric_key] = node
                end
            end
            decoded_ring.ring = numeric_ring
            
            return decoded_ring
        end
    end

    return nil
end

-- 根据Token获取应用类型
function _M.get_app_type(user_token)
    if not user_token or user_token == "" then
        return nil
    end

    for app_name, app_config in pairs(config.applications) do
        for _, token in ipairs(app_config.user_tokens) do
            if token == user_token then
                return app_name
            end
        end
    end

    return nil
end

-- 获取用户ID（支持多种方式）
function _M.get_user_id()
    -- 1. 优先使用请求头
    local user_id = ngx.var.http_x_user_id
    if user_id and user_id ~= "" then
        return user_id
    end

    -- 2. URL参数
    local args = ngx.req.get_uri_args()
    if args.user_id then
        return args.user_id
    end

    -- 3. Cookie
    local cookie_user_id = ngx.var.cookie_user_id
    if cookie_user_id and cookie_user_id ~= "" then
        return cookie_user_id
    end

    -- 4. 从请求体JSON中提取（支持Dify API）
    local content_type = ngx.var.content_type
    if content_type and string.find(content_type, "application/json") then
        -- 读取请求体
        ngx.req.read_body()
        local body = ngx.req.get_body_data()

        if body and body ~= "" then
            local success, json_data = pcall(cjson.decode, body)
            if success and json_data and json_data.user then
                return json_data.user
            end
        end
    end

    -- 5. 从multipart/form-data中提取user参数
    if content_type and string.find(content_type, "multipart/form%-data") then
        -- 读取请求体
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        
        if body and body ~= "" then
            -- 解析multipart/form-data
            local user_id = _M.parse_form_data_user(body, content_type)
            if user_id then
                return user_id
            end
        end
    end

    return nil
end

-- 解析multipart/form-data中的user参数
function _M.parse_form_data_user(body, content_type)
    if not body or not content_type then
        return nil
    end

    -- 提取boundary
    local boundary = string.match(content_type, "boundary=([^;]+)")
    if not boundary then
        return nil
    end

    -- 清理boundary（移除可能的引号）
    boundary = string.gsub(boundary, '"', '')
    
    -- 分割multipart数据
    local parts = {}
    local pattern = "--" .. boundary .. "\r?\n"
    local start_pos = 1
    
    while true do
        local boundary_start, boundary_end = string.find(body, pattern, start_pos)
        if not boundary_start then
            break
        end
        
        -- 查找下一个boundary或结束标记
        local next_boundary_start = string.find(body, "--" .. boundary, boundary_end + 1)
        if not next_boundary_start then
            break
        end
        
        -- 提取当前part的内容
        local part_content = string.sub(body, boundary_end + 1, next_boundary_start - 1)
        table.insert(parts, part_content)
        
        start_pos = next_boundary_start
    end
    
    -- 解析每个part，查找name="user"的字段
    for _, part in ipairs(parts) do
        -- 分离headers和content
        local header_end = string.find(part, "\r?\n\r?\n")
        if header_end then
            local headers = string.sub(part, 1, header_end - 1)
            local content = string.sub(part, header_end + 2)
            
            -- 检查是否是user字段
            if string.find(headers, 'name="user"') then
                -- 清理内容（移除可能的换行符）
                content = string.gsub(content, "\r?\n$", "")
                content = string.gsub(content, "^\r?\n", "")
                
                if content and content ~= "" then
                    return content
                end
            end
        end
    end
    
    return nil
end

-- 根据用户ID和应用类型获取后端实例
function _M.get_backend_instance(app_type, user_id)
    if not app_type or not user_id then
        return nil
    end

    local hash_ring = get_hash_ring(app_type)
    if not hash_ring then
        return nil
    end

    -- 使用一致性Hash选择节点
    local hash_key = app_type .. ":" .. user_id
    local node = consistent_hash.get_node(hash_ring, hash_key)

    if node then
        return node, hash_key
    end

    return nil
end

-- 更新统计信息
function _M.update_stats(app_type, user_id, instance_name, response_time)
    local stats_dict = ngx.shared.stats
    local timestamp = ngx.time()

    -- 更新应用访问计数
    local app_key = "app:" .. app_type
    stats_dict:incr(app_key, 1, 0)

    -- 更新实例访问计数
    local instance_key = "instance:" .. instance_name
    stats_dict:incr(instance_key, 1, 0)

    -- 更新响应时间（简单移动平均）
    if response_time then
        local rt_key = "rt:" .. instance_name
        local current_rt = stats_dict:get(rt_key) or 0
        local new_rt = (current_rt + response_time) / 2
        stats_dict:set(rt_key, new_rt)
    end
end

-- 获取统计信息
function _M.get_stats()
    local stats_dict = ngx.shared.stats
    local keys = stats_dict:get_keys(0)
    local stats = {}

    for _, key in ipairs(keys) do
        stats[key] = stats_dict:get(key)
    end

    return stats
end

-- 初始化（在init_worker_by_lua中调用）
function _M.init()
    cache_hash_rings()
    ngx.log(ngx.INFO, "Loadbalancer initialized successfully")
end

return _M