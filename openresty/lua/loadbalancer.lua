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
    ngx.log(ngx.INFO, "[DEBUG] get_app_type called with token: ", user_token or "nil")
    
    if not user_token or user_token == "" then
        ngx.log(ngx.WARN, "[DEBUG] Token is empty or nil")
        return nil
    end

    for app_name, app_config in pairs(config.applications) do
        ngx.log(ngx.INFO, "[DEBUG] Checking app: ", app_name)
        for _, token in ipairs(app_config.user_tokens) do
            ngx.log(ngx.INFO, "[DEBUG] Comparing with configured token: ", token)
            if token == user_token then
                ngx.log(ngx.INFO, "[DEBUG] Token matched for app: ", app_name)
                return app_name
            end
        end
    end

    ngx.log(ngx.WARN, "[DEBUG] No matching token found for: ", user_token)
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

    -- 4. 从请求体JSON中提取（优化版本，避免阻塞）
    local content_type = ngx.var.content_type
    if content_type and string.find(content_type, "application/json") then
        -- 安全读取请求体，避免大文件阻塞
        local user_id_from_body = _M.safe_parse_json_user()
        if user_id_from_body then
            return user_id_from_body
        end
    end

    -- 5. 从multipart/form-data中提取 user 字段（文件上传场景）
    if content_type and string.find(content_type, "multipart/form%-data") then
        local user_id_from_form = _M.safe_parse_form_user()
        if user_id_from_form and user_id_from_form ~= "" then
            return user_id_from_form
        end
    end

    return nil
end

-- 安全解析JSON请求体中的user参数（避免大文件阻塞）
function _M.safe_parse_json_user()
    -- 检查请求体大小，如果太大则跳过解析
    local content_length = tonumber(ngx.var.http_content_length)
    if content_length and content_length > 1024 * 1024 then  -- 1MB限制
        ngx.log(ngx.WARN, "[OPTIMIZATION] Skipping JSON bod y parsing for large request: ", content_length, " bytes")
        return nil
    end

    -- 使用非阻塞方式读取请求体
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    -- 如果body为空，尝试从临时文件读取（但限制大小）
    if not body then
        local body_file = ngx.req.get_body_file()
        if body_file then
            ngx.log(ngx.WARN, "[OPTIMIZATION] Request body too large, stored in file: ", body_file)
            return nil  -- 不处理存储在文件中的大请求体
        end
    end

    if body and body ~= "" then
        local success, json_data = pcall(cjson.decode, body)
        if success and json_data and json_data.user then
            return json_data.user
        end
    end
    
    return nil
end

-- 解析multipart/form-data中的 user 字段（纯Lua实现）
local function parse_multipart_user(body, boundary)
    if not body or body == "" or not boundary or boundary == "" then
        return nil
    end

    local delimiter = "--" .. boundary

    -- 查找包含 name="user" 的part
    local header_pattern = "Content%-Disposition:%s*form%-data;[^\n]*name=\"user\""
    local start_pos, header_end = body:find(header_pattern)
    if not start_pos then
        return nil
    end

    -- 定位到该part的内容开始位置（空行 \r\n\r\n 之后）
    local sep_s, sep_e = body:find("\r\n\r\n", header_end + 1, true)
    if not sep_e then
        return nil
    end
    local content_start = sep_e + 1

    -- 定位到该part的结束边界（下一次出现 \r\n--boundary）
    local next_boundary = "\r\n" .. delimiter
    local content_end = body:find(next_boundary, content_start, true)
    if not content_end then
        -- 兼容某些环境只使用 \n 换行
        next_boundary = "\n" .. delimiter
        content_end = body:find(next_boundary, content_start, true)
    end

    local value
    if content_end then
        value = body:sub(content_start, content_end - 1)
    else
        -- 兜底：直到结束
        value = body:sub(content_start)
    end

    -- 去除可能的尾部换行与空白
    value = value:gsub("\r$", ""):gsub("\n$", "")
    value = value:gsub("%s+$", "")
    value = value:gsub("^%s+", "")

    if value == "" then
        return nil
    end

    return value
end

-- 安全解析multipart/form-data请求体中的user参数
function _M.safe_parse_form_user()
    -- 读取请求体与boundary
    local content_type = ngx.var.content_type or ""
    local boundary = content_type:match('boundary="?([^";]+)"?')
    if not boundary or boundary == "" then
        ngx.log(ngx.WARN, "[FORM] boundary not found in Content-Type: ", content_type)
        return nil
    end

    ngx.req.read_body()

    -- 优先从内存中获取
    local body = ngx.req.get_body_data()
    if body and #body > 0 then
        local ok, user_or_err = pcall(parse_multipart_user, body, boundary)
        if ok then
            return user_or_err
        else
            ngx.log(ngx.ERR, "[FORM] parse error: ", user_or_err)
            return nil
        end
    end

    -- 如果请求体被写入临时文件，读取文件内容进行解析（注意：可能较大）
    local body_file = ngx.req.get_body_file()
    if body_file then
        ngx.log(ngx.INFO, "[FORM] Reading body from temp file: ", body_file)
        local f, err = io.open(body_file, "rb")
        if not f then
            ngx.log(ngx.ERR, "[FORM] Failed to open temp body file: ", err)
            return nil
        end
        local data = f:read("*a")
        f:close()
        if not data or data == "" then
            return nil
        end
        local ok, user_or_err = pcall(parse_multipart_user, data, boundary)
        if ok then
            return user_or_err
        else
            ngx.log(ngx.ERR, "[FORM] parse error from file: ", user_or_err)
            return nil
        end
    end

    return nil
end

-- 根据用户ID和应用类型获取后端实例
function _M.get_backend_instance(app_type, user_id)
    ngx.log(ngx.INFO, "[DEBUG] get_backend_instance called with app_type: ", app_type or "nil", ", user_id: ", user_id or "nil")
    
    if not app_type or not user_id then
        ngx.log(ngx.WARN, "[DEBUG] Missing app_type or user_id")
        return nil
    end

    local hash_ring = get_hash_ring(app_type)
    if not hash_ring then
        ngx.log(ngx.ERR, "[DEBUG] No hash ring found for app_type: ", app_type)
        return nil
    end

    -- 使用一致性Hash选择节点
    local hash_key = app_type .. ":" .. user_id
    ngx.log(ngx.INFO, "[DEBUG] Using hash_key: ", hash_key)
    
    local node = consistent_hash.get_node(hash_ring, hash_key)

    if node then
        ngx.log(ngx.INFO, "[DEBUG] Selected Dify instance - name: ", node.name or "unknown", 
                         ", host: ", node.host or "unknown", 
                         ", port: ", node.port or "unknown", 
                         ", token: ", node.token or "unknown")
        return node, hash_key
    else
        ngx.log(ngx.ERR, "[DEBUG] No node selected for hash_key: ", hash_key)
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