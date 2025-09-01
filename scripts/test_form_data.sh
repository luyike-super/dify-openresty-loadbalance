#!/bin/bash

# 测试multipart/form-data支持的脚本

echo "=== Dify OpenResty 负载均衡器 Form-Data 测试 ==="
echo

# 配置
LOADBALANCER_URL="http://localhost:82"
API_KEY="usertoken--customer-service-v1"  # 使用配置文件中的user_token
TEST_USER="test-user-123"
TEST_FILE="/tmp/test_image.png"

# 创建测试图片文件（如果不存在）
if [ ! -f "$TEST_FILE" ]; then
    echo "创建测试图片文件..."
    # 创建一个简单的1x1像素PNG图片
    echo -e "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\tpHYs\x00\x00\x0b\x13\x00\x00\x0b\x13\x01\x00\x9a\x9c\x18\x00\x00\x00\nIDATx\x9cc```\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82" > "$TEST_FILE"
    echo "测试图片文件已创建: $TEST_FILE"
fi

echo "开始测试..."
echo

# 测试1: 使用form-data中的user参数
echo "测试1: 使用form-data中的user参数"
echo "请求: curl -X POST '$LOADBALANCER_URL/v1/files/upload' --form 'user=$TEST_USER' --form 'file=@$TEST_FILE;type=image/png' --header 'Authorization: Bearer $API_KEY'"
echo

response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$LOADBALANCER_URL/v1/files/upload" \
  --header "Authorization: Bearer $API_KEY" \
  --form "user=$TEST_USER" \
  --form "file=@$TEST_FILE;type=image/png")

http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
body=$(echo "$response" | sed '/HTTP_CODE:/d')

echo "响应状态码: $http_code"
echo "响应内容: $body"
echo

# 测试2: 使用X-User-ID头（对比测试）
echo "测试2: 使用X-User-ID头（对比测试）"
echo "请求: curl -X POST '$LOADBALANCER_URL/v1/files/upload' --header 'X-User-ID: $TEST_USER' --form 'file=@$TEST_FILE;type=image/png' --header 'Authorization: Bearer $API_KEY'"
echo

response2=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$LOADBALANCER_URL/v1/files/upload" \
  --header "Authorization: Bearer $API_KEY" \
  --header "X-User-ID: $TEST_USER" \
  --form "file=@$TEST_FILE;type=image/png")

http_code2=$(echo "$response2" | grep "HTTP_CODE:" | cut -d: -f2)
body2=$(echo "$response2" | sed '/HTTP_CODE:/d')

echo "响应状态码: $http_code2"
echo "响应内容: $body2"
echo

# 测试3: 不提供user参数（应该返回400错误）
echo "测试3: 不提供user参数（应该返回400错误）"
echo "请求: curl -X POST '$LOADBALANCER_URL/v1/files/upload' --form 'file=@$TEST_FILE;type=image/png' --header 'Authorization: Bearer $API_KEY'"
echo

response3=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$LOADBALANCER_URL/v1/files/upload" \
  --header "Authorization: Bearer $API_KEY" \
  --form "file=@$TEST_FILE;type=image/png")

http_code3=$(echo "$response3" | grep "HTTP_CODE:" | cut -d: -f2)
body3=$(echo "$response3" | sed '/HTTP_CODE:/d')

echo "响应状态码: $http_code3"
echo "响应内容: $body3"
echo

# 测试结果总结
echo "=== 测试结果总结 ==="
echo "测试1 (form-data user): HTTP $http_code"
echo "测试2 (X-User-ID header): HTTP $http_code2"
echo "测试3 (无user参数): HTTP $http_code3"
echo

if [ "$http_code3" = "400" ]; then
    echo "✓ 无user参数时正确返回400错误"
else
    echo "✗ 无user参数时应该返回400错误，实际返回: $http_code3"
fi

if [ "$http_code" = "$http_code2" ] && [ "$http_code" != "400" ]; then
    echo "✓ form-data和header方式返回相同状态码，功能一致"
else
    echo "✗ form-data和header方式返回不同状态码，可能存在问题"
fi

echo
echo "测试完成！"
echo
echo "注意事项:"
echo "1. 请确保负载均衡器正在运行 (docker-compose up -d)"
echo "2. 请在脚本中设置正确的API_KEY"
echo "3. 请确保config.lua中配置了对应的应用实例"
echo "4. 如果返回401错误，请检查API Key配置"
echo "5. 如果返回503错误，请检查后端Dify实例是否正常运行"