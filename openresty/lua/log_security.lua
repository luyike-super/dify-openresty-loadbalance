-- 企业级日志安全模块
-- 负责敏感信息脱敏、安全事件记录、异常检测

local _M = {}
local cjson = require "cjson"

-- 敏感信息脱敏配置
local SENSITIVE_PATTERNS = {
    -- API密钥和Token
    { pattern = "Bearer%s+([%w%-_%.]+)", replacement = "Bearer ***MASKED***" },
    { pattern = "token[%s]*=[%s]*([%w%-_%.]+)", replacement = "token=***MASKED***" },
    { pattern = "api[_%-]?key[%s]*=[%s]*([%w%-_%.]+)", replacement = "api_key=***MASKED***" },
    
    -- 密码
    { pattern = "password[%s]*=[%s]*([^&%s]+)", replacement = "password=***MASKED***" },
    { pattern = "passwd[%s]*=[%s]*([^&%s]+)", replacement = "passwd=***MASKED***" },
    
    -- 邮箱
    { pattern = "([%w%.%-_]+@[%w%.%-_]+%.%w+)", replacement = "***@***.***" },
    
    -- 手机号
    { pattern = "(1[3-9]%d{9})", replacement = "***PHONE***" },
    
    -- 身份证号
    { pattern = "([1-9]%d{5}[1-9]%d{3}[0-1]%d[0-3]%d%d{3}[%dxX])", replacement = "***ID***" },
    
    -- 银行卡号
    { pattern = "(%d{4}[%s%-]?%d{4}[%s%-]?%d{4}[%s%-]?%d{4})", replacement = "***CARD***" }
}

-- 可疑请求模式
local SUSPICIOUS_PATTERNS = {
    "%.%.%/",  -- 路径遍历
    "<script",  -- XSS
    "union%s+select",  -- SQL注入
    "exec%s*%(",  -- 命令注入
    "/etc/passwd",  -- 系统文件访问
    "cmd%.exe",  -- Windows命令
    "powershell",  -- PowerShell
    "base64",  -- Base64编码（可能的payload）
}

-- 脱敏函数
function _M.sanitize_data(data)
    if not data or type(data) ~= "string" then
        return data
    end
    
    local sanitized = data
    
    for _, pattern_config in ipairs(SENSITIVE_PATTERNS) do
        sanitized = string.gsub(sanitized, pattern_config.pattern, pattern_config.replacement)
    end
    
    return sanitized
 end

-- 检测可疑请求
function _M.detect_suspicious_request(uri, user_agent, headers)
    local suspicious_indicators = {}
    
    -- 检查URI
    if uri then
        for _, pattern in ipairs(SUSPICIOUS_PATTERNS) do
            if string.match(string.lower(uri), pattern) then
                table.insert(suspicious_indicators, {
                    type = "suspicious_uri",
                    pattern = pattern,
                    value = _M.sanitize_data(uri)
                })
            end
        end
    end
    
    -- 检查User-Agent
    if user_agent then
        local ua_lower = string.lower(user_agent)
        if string.match(ua_lower, "sqlmap") or 
           string.match(ua_lower, "nmap") or
           string.match(ua_lower, "nikto") or
           string.match(ua_lower, "burp") then
            table.insert(suspicious_indicators, {
                type = "suspicious_user_agent",
                value = _M.sanitize_data(user_agent)
            })
        end
    end
    
    return suspicious_indicators
end

-- 记录安全事件
function _M.log_security_event(event_type, details)
    local security_log = {
        timestamp = ngx.utctime(),
        event_type = event_type,
        request_id = ngx.var.request_id or "unknown",
        remote_addr = ngx.var.remote_addr,
        details = details,
        server_name = ngx.var.server_name
    }
    
    -- 脱敏处理
    if details.uri then
        details.uri = _M.sanitize_data(details.uri)
    end
    if details.user_agent then
        details.user_agent = _M.sanitize_data(details.user_agent)
    end
    if details.headers then
        for k, v in pairs(details.headers) do
            details.headers[k] = _M.sanitize_data(v)
        end
    end
    
    -- 记录到错误日志
    ngx.log(ngx.ERR, "[SECURITY_EVENT] ", cjson.encode(security_log))
end

-- 检查请求频率异常
function _M.check_rate_anomaly(remote_addr)
    local stats_dict = ngx.shared.stats
    if not stats_dict then
        return false
    end
    
    local key = "rate_" .. remote_addr
    local current_time = ngx.time()
    local window_size = 60  -- 1分钟窗口
    
    -- 获取当前计数
    local count, flags = stats_dict:get(key)
    if not count then
        stats_dict:set(key, 1, window_size)
        return false
    end
    
    -- 增加计数
    local new_count, err = stats_dict:incr(key, 1)
    if err then
        ngx.log(ngx.ERR, "Failed to increment rate counter: ", err)
        return false
    end
    
    -- 检查是否超过阈值
    local threshold = 100  -- 每分钟100次请求
    if new_count > threshold then
        _M.log_security_event("rate_limit_exceeded", {
            remote_addr = remote_addr,
            request_count = new_count,
            threshold = threshold,
            window_size = window_size
        })
        return true
    end
    
    return false
end

-- 验证JWT Token（简化版）
function _M.validate_token_format(token)
    if not token then
        return false, "missing_token"
    end
    
    -- 检查JWT格式
    local parts = {}
    for part in string.gmatch(token, "[^%.]+") do
        table.insert(parts, part)
    end
    
    if #parts ~= 3 then
        return false, "invalid_jwt_format"
    end
    
    -- 检查Token长度（防止异常长Token）
    if string.len(token) > 2048 then
        return false, "token_too_long"
    end
    
    return true, "valid"
end

-- 主安全检查函数
function _M.security_check()
    local uri = ngx.var.request_uri
    local user_agent = ngx.var.http_user_agent
    local remote_addr = ngx.var.remote_addr
    local auth_header = ngx.var.http_authorization
    
    -- 检查可疑请求
    local suspicious = _M.detect_suspicious_request(uri, user_agent)
    if #suspicious > 0 then
        _M.log_security_event("suspicious_request_detected", {
            uri = uri,
            user_agent = user_agent,
            remote_addr = remote_addr,
            indicators = suspicious
        })
    end
    
    -- 检查请求频率
    if _M.check_rate_anomaly(remote_addr) then
        ngx.log(ngx.WARN, "Rate limit anomaly detected for ", remote_addr)
    end
    
    -- 验证Token格式
    if auth_header then
        local token = string.match(auth_header, "Bearer%s+(.+)")
        local valid, reason = _M.validate_token_format(token)
        if not valid then
            _M.log_security_event("invalid_token_format", {
                reason = reason,
                remote_addr = remote_addr,
                uri = uri
            })
        end
    end
end

return _M