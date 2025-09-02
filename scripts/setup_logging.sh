#!/bin/bash

# 企业级日志系统部署脚本
# 自动配置和启动 ELK Stack + Grafana + Prometheus

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    log_success "依赖检查完成"
}

# 创建必要的目录
create_directories() {
    log_info "创建日志目录结构..."
    
    # 创建日志目录
    sudo mkdir -p /var/log/nginx
    sudo mkdir -p /var/log/nginx/security_backup
    sudo mkdir -p ./openresty/logs
    sudo mkdir -p ./config/{grafana/provisioning/{dashboards,datasources},grafana/dashboards}
    
    # 设置权限
    sudo chown -R nobody:nobody /var/log/nginx
    sudo chmod -R 755 /var/log/nginx
    
    # 创建软链接（如果不存在）
    if [ ! -L "./openresty/logs" ]; then
        ln -sf /var/log/nginx ./openresty/logs
    fi
    
    log_success "目录创建完成"
}

# 生成配置文件
generate_configs() {
    log_info "生成配置文件..."
    
    # Elasticsearch 配置
    cat > ./config/elasticsearch.yml << 'EOF'
cluster.name: "dify-logs"
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
xpack.monitoring.collection.enabled: true
EOF

    # Logstash 配置
    cat > ./config/logstash.conf << 'EOF'
input {
  file {
    path => "/var/log/nginx/access.log"
    start_position => "beginning"
    type => "nginx_access"
    codec => "json"
  }
  
  file {
    path => "/var/log/nginx/app_routing.log"
    start_position => "beginning"
    type => "app_routing"
    codec => "json"
  }
  
  file {
    path => "/var/log/nginx/security_audit.log"
    start_position => "beginning"
    type => "security_audit"
    codec => "json"
  }
  
  file {
    path => "/var/log/nginx/performance.log"
    start_position => "beginning"
    type => "performance"
    codec => "json"
  }
}

filter {
  if [timestamp] {
    date {
      match => [ "timestamp", "ISO8601" ]
    }
  }
  
  if [remote_addr] {
    geoip {
      source => "remote_addr"
      target => "geoip"
    }
  }
  
  if [http_user_agent] {
    useragent {
      source => "http_user_agent"
      target => "user_agent"
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "nginx-logs-%{+YYYY.MM.dd}"
  }
  
  stdout {
    codec => rubydebug
  }
}
EOF

    # Kibana 配置
    cat > ./config/kibana.yml << 'EOF'
server.name: kibana
server.host: 0.0.0.0
elasticsearch.hosts: ["http://elasticsearch:9200"]
monitoring.ui.container.elasticsearch.enabled: true
EOF

    # Prometheus 配置
    cat > ./config/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "nginx_alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'nginx-exporter'
    static_configs:
      - targets: ['nginx-exporter:9113']
  
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF

    # Prometheus 告警规则
    cat > ./config/nginx_alerts.yml << 'EOF'
groups:
  - name: nginx_alerts
    rules:
      - alert: NginxHighErrorRate
        expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) > 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Nginx 5xx错误率过高"
          description: "5xx错误率超过10%，持续5分钟"
          
      - alert: NginxSlowResponse
        expr: nginx_http_request_duration_seconds > 2
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Nginx 响应时间过慢"
          description: "平均响应时间超过2秒"
EOF

    # AlertManager 配置
    cat > ./config/alertmanager.yml << 'EOF'
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@company.com'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
EOF

    # Grafana 数据源配置
    cat > ./config/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

    # Grafana 仪表板配置
    cat > ./config/grafana/provisioning/dashboards/dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log_success "配置文件生成完成"
}

# 设置系统参数
setup_system() {
    log_info "优化系统参数..."
    
    # 增加虚拟内存映射限制（Elasticsearch 需要）
    echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
    
    # 增加文件描述符限制
    echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
    
    log_success "系统参数优化完成"
}

# 启动服务
start_services() {
    log_info "启动日志分析服务..."
    
    # 停止现有服务
    docker-compose -f docker-compose.logging.yml down 2>/dev/null || true
    
    # 启动核心服务
    docker-compose -f docker-compose.logging.yml up -d elasticsearch
    
    # 等待 Elasticsearch 启动
    log_info "等待 Elasticsearch 启动..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if curl -s http://localhost:9200/_cluster/health >/dev/null 2>&1; then
            log_success "Elasticsearch 已启动"
            break
        fi
        sleep 2
        timeout=$((timeout-2))
    done
    
    if [ $timeout -le 0 ]; then
        log_error "Elasticsearch 启动超时"
        exit 1
    fi
    
    # 启动其他服务
    docker-compose -f docker-compose.logging.yml up -d
    
    log_success "所有服务已启动"
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."
    
    services=("elasticsearch:9200" "kibana:5601" "grafana:3000" "prometheus:9090")
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service"
        log_info "检查 $name 服务..."
        
        timeout=30
        while [ $timeout -gt 0 ]; do
            if curl -s "http://localhost:$port" >/dev/null 2>&1; then
                log_success "$name 服务正常运行 (http://localhost:$port)"
                break
            fi
            sleep 2
            timeout=$((timeout-2))
        done
        
        if [ $timeout -le 0 ]; then
            log_warning "$name 服务可能未完全启动，请稍后检查"
        fi
    done
}

# 显示访问信息
show_access_info() {
    log_info "部署完成！访问信息："
    echo ""
    echo "📊 Kibana (日志分析):     http://localhost:5601"
    echo "📈 Grafana (指标监控):    http://localhost:3000 (admin/admin123)"
    echo "🔍 Prometheus (指标收集): http://localhost:9090"
    echo "🚨 AlertManager (告警):   http://localhost:9093"
    echo "🔧 Elasticsearch (搜索):  http://localhost:9200"
    echo ""
    echo "📁 日志文件位置: /var/log/nginx/"
    echo "🐳 管理命令:"
    echo "   启动: docker-compose -f docker-compose.logging.yml up -d"
    echo "   停止: docker-compose -f docker-compose.logging.yml down"
    echo "   查看: docker-compose -f docker-compose.logging.yml ps"
    echo ""
}

# 主函数
main() {
    echo "============================================"
    echo "    企业级日志分析系统部署脚本"
    echo "============================================"
    echo ""
    
    check_dependencies
    create_directories
    generate_configs
    setup_system
    start_services
    verify_deployment
    show_access_info
    
    log_success "日志分析系统部署完成！"
}

# 执行主函数
main "$@"