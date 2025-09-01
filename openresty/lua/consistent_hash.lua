-- 一致性Hash算法实现 (x86优化版本)
local cjson = require "cjson"
local bit = require "bit"

local _M = {}
_M._VERSION = '0.1'

-- CRC32算法实现
local function crc32(str)
    local crc = 0xFFFFFFFF
    for i = 1, #str do
        local byte = string.byte(str, i)
        crc = bit.bxor(crc, byte)
        for j = 1, 8 do
            if bit.band(crc, 1) == 1 then
                crc = bit.bxor(bit.rshift(crc, 1), 0xEDB88320)
            else
                crc = bit.rshift(crc, 1)
            end
        end
    end
    return bit.bxor(crc, 0xFFFFFFFF)
end

-- MD5算法（使用resty.md5）
local function md5_hash(str)
    local resty_md5 = require "resty.md5"
    local md5 = resty_md5:new()
    md5:update(str)
    local digest = md5:final()

    -- 转换为32位整数
    local hash = 0
    for i = 1, 4 do
        hash = hash * 256 + string.byte(digest, i)
    end
    return hash
end

-- 获取hash值
local function get_hash(str, algorithm)
    if algorithm == "md5" then
        return md5_hash(str)
    else
        return crc32(str)
    end
end

-- 创建一致性Hash环
function _M.create_ring(nodes, virtual_nodes, algorithm)
    local ring = {}
    local sorted_keys = {}

    algorithm = algorithm or "crc32"
    virtual_nodes = virtual_nodes or 200  -- x86默认更多虚拟节点

    -- 为每个节点创建虚拟节点
    for _, node in ipairs(nodes) do
        for i = 1, virtual_nodes do
            local virtual_key = node.name .. "#" .. i
            local hash = get_hash(virtual_key, algorithm)

            ring[hash] = node
            table.insert(sorted_keys, hash)
        end
    end

    -- 对hash值排序
    table.sort(sorted_keys)

    return {
        ring = ring,
        sorted_keys = sorted_keys,
        algorithm = algorithm
    }
end

-- 根据key查找节点
function _M.get_node(hash_ring, key)
    if not hash_ring or not hash_ring.sorted_keys or #hash_ring.sorted_keys == 0 then
        return nil
    end

    local hash = get_hash(key, hash_ring.algorithm)
    local sorted_keys = hash_ring.sorted_keys

    -- 二分查找第一个大于等于hash的位置
    local left, right = 1, #sorted_keys
    while left < right do
        local mid = math.floor((left + right) / 2)
        if sorted_keys[mid] < hash then
            left = mid + 1
        else
            right = mid
        end
    end

    -- 如果hash大于所有键，则返回第一个节点（环形）
    local index = left > #sorted_keys and 1 or left
    local ring_key = sorted_keys[index]

    return hash_ring.ring[ring_key]
end

-- 移除节点
function _M.remove_node(hash_ring, node_name, virtual_nodes)
    virtual_nodes = virtual_nodes or 200

    -- 移除该节点的所有虚拟节点
    for i = 1, virtual_nodes do
        local virtual_key = node_name .. "#" .. i
        local hash = get_hash(virtual_key, hash_ring.algorithm)

        hash_ring.ring[hash] = nil

        -- 从sorted_keys中移除
        for j, key in ipairs(hash_ring.sorted_keys) do
            if key == hash then
                table.remove(hash_ring.sorted_keys, j)
                break
            end
        end
    end
end

-- 添加节点
function _M.add_node(hash_ring, node, virtual_nodes)
    virtual_nodes = virtual_nodes or 200

    -- 添加虚拟节点
    for i = 1, virtual_nodes do
        local virtual_key = node.name .. "#" .. i
        local hash = get_hash(virtual_key, hash_ring.algorithm)

        hash_ring.ring[hash] = node
        table.insert(hash_ring.sorted_keys, hash)
    end

    -- 重新排序
    table.sort(hash_ring.sorted_keys)
end

return _M