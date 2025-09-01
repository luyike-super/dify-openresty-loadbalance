#!/bin/bash

# 性能优化测试脚本
# 测试大文件上传时接口是否还会卡死

set -e

BASE_URL="http://localhost:82"
API_KEY="your-api-key"  # 请替换为实际的API key
TEST_USER="perf-test-user"

echo "🚀 开始性能优化测试..."
echo "================================"

# 创建测试文件
echo "📁 创建测试文件..."
mkdir -p /tmp/performance_test

# 创建小文件 (1KB)
dd if=/dev/zero of=/tmp/performance_test/small_file.dat bs=1024 count=1 2>/dev/null
echo "✅ 创建小文件: 1KB"

# 创建中等文件 (5MB)
dd if=/dev/zero of=/tmp/performance_test/medium_file.dat bs=1024 count=5120 2>/dev/null
echo "✅ 创建中等文件: 5MB"

# 创建大文件 (50MB)
dd if=/dev/zero of=/tmp/performance_test/large_file.dat bs=1024 count=51200 2>/dev/null
echo "✅ 创建大文件: 50MB"

echo ""
echo "🧪 测试场景1: 使用HTTP请求头 (推荐方式)"
echo "--------------------------------"

test_with_header() {
    local file_path=$1
    local file_name=$(basename $file_path)
    local start_time=$(date +%s.%N)
    
    echo -n "测试 $file_name ... "
    
    response=$(curl -s -w "%{http_code}" -o /tmp/test_response.json \
        -X POST "$BASE_URL/v1/files/upload" \
        -H "Authorization: Bearer $API_KEY" \
        -H "X-User-ID: $TEST_USER" \
        -F "file=@$file_path" \
        --max-time 30)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $response == "200" ]] || [[ $response == "404" ]] || [[ $response == "401" ]]; then
        printf "✅ 成功 (%.2f秒, HTTP %s)\n" $duration $response
    else
        printf "❌ 失败 (%.2f秒, HTTP %s)\n" $duration $response
        echo "   响应内容: $(cat /tmp/test_response.json)"
    fi
}

test_with_header "/tmp/performance_test/small_file.dat"
test_with_header "/tmp/performance_test/medium_file.dat"
test_with_header "/tmp/performance_test/large_file.dat"

echo ""
echo "🧪 测试场景2: 使用Form-Data中的user字段"
echo "--------------------------------"

test_with_form_data() {
    local file_path=$1
    local file_name=$(basename $file_path)
    local start_time=$(date +%s.%N)
    
    echo -n "测试 $file_name ... "
    
    response=$(curl -s -w "%{http_code}" -o /tmp/test_response.json \
        -X POST "$BASE_URL/v1/files/upload" \
        -H "Authorization: Bearer $API_KEY" \
        -F "user=$TEST_USER" \
        -F "file=@$file_path" \
        --max-time 30)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $response == "200" ]] || [[ $response == "404" ]] || [[ $response == "401" ]]; then
        printf "✅ 成功 (%.2f秒, HTTP %s)\n" $duration $response
    else
        printf "❌ 失败 (%.2f秒, HTTP %s)\n" $duration $response
        echo "   响应内容: $(cat /tmp/test_response.json)"
    fi
}

test_with_form_data "/tmp/performance_test/small_file.dat"
test_with_form_data "/tmp/performance_test/medium_file.dat" 
test_with_form_data "/tmp/performance_test/large_file.dat"

echo ""
echo "🧪 测试场景3: 使用URL参数"
echo "--------------------------------"

test_with_url_param() {
    local file_path=$1
    local file_name=$(basename $file_path)
    local start_time=$(date +%s.%N)
    
    echo -n "测试 $file_name ... "
    
    response=$(curl -s -w "%{http_code}" -o /tmp/test_response.json \
        -X POST "$BASE_URL/v1/files/upload?user_id=$TEST_USER" \
        -H "Authorization: Bearer $API_KEY" \
        -F "file=@$file_path" \
        --max-time 30)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $response == "200" ]] || [[ $response == "404" ]] || [[ $response == "401" ]]; then
        printf "✅ 成功 (%.2f秒, HTTP %s)\n" $duration $response
    else
        printf "❌ 失败 (%.2f秒, HTTP %s)\n" $duration $response
        echo "   响应内容: $(cat /tmp/test_response.json)"
    fi
}

test_with_url_param "/tmp/performance_test/small_file.dat"
test_with_url_param "/tmp/performance_test/medium_file.dat"
test_with_url_param "/tmp/performance_test/large_file.dat"

echo ""
echo "🧪 测试场景4: JSON请求体 (小数据)"
echo "--------------------------------"

test_json_request() {
    local data_size=$1
    local json_data='{"user":"'$TEST_USER'","query":"Hello","data":"'$(head -c $data_size /dev/zero | base64 | tr -d '\n')'"}'
    local start_time=$(date +%s.%N)
    
    echo -n "测试 JSON数据 (~$data_size bytes) ... "
    
    response=$(curl -s -w "%{http_code}" -o /tmp/test_response.json \
        -X POST "$BASE_URL/v1/chat-messages" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_data" \
        --max-time 30)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $response == "200" ]] || [[ $response == "404" ]] || [[ $response == "401" ]]; then
        printf "✅ 成功 (%.2f秒, HTTP %s)\n" $duration $response
    else
        printf "❌ 失败 (%.2f秒, HTTP %s)\n" $duration $response
    fi
}

test_json_request 1024      # 1KB
test_json_request 10240     # 10KB
test_json_request 102400    # 100KB

echo ""
echo "📊 性能统计"
echo "--------------------------------"
echo "检查负载均衡器状态:"
curl -s "$BASE_URL/status" | jq . 2>/dev/null || curl -s "$BASE_URL/status"

echo ""
echo "检查健康状态:"
curl -s "$BASE_URL/health" | jq . 2>/dev/null || curl -s "$BASE_URL/health"

echo ""
echo "🧹 清理测试文件..."
rm -rf /tmp/performance_test
rm -f /tmp/test_response.json

echo ""
echo "✨ 测试完成!"
echo "================================"
echo "📋 测试结果说明:"
echo "• HTTP 200: 请求成功处理"
echo "• HTTP 401: 认证失败 (API Key问题)"
echo "• HTTP 404: 后端服务不可用"
echo "• HTTP 502/504: 网关错误 (可能是优化前的卡死问题)"
echo ""
echo "💡 优化效果:"
echo "• 所有请求都应该在30秒内完成"
echo "• 大文件上传不应该导致超时"
echo "• 响应时间应该保持在合理范围内"
