# MSHH Solver - Deployment Guide

Complete guide for deploying the MSHH solver in various environments.

---

## Table of Contents

1. [Docker Deployment](#docker-deployment)
2. [Manual Deployment](#manual-deployment)
3. [Production Considerations](#production-considerations)
4. [Monitoring & Maintenance](#monitoring--maintenance)
5. [Troubleshooting](#troubleshooting)

---

## Docker Deployment

### Prerequisites

- **Docker**: 20.10+ ([Install Docker](https://docs.docker.com/get-docker/))
- **Docker Compose**: 1.29+ (included with Docker Desktop)
- **System Requirements**:
  - CPU: 4+ cores recommended
  - RAM: 8GB minimum, 16GB recommended
  - Disk: 10GB for Docker images + space for instances/results

### Quick Start

```bash
# Clone repository
git clone https://github.com/kkaragul/JuLog.git
cd JuLog

# Build and start services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f mshh-app

# Access services
# API: http://localhost:8000/api/health
# Frontend: http://localhost:3000
```

### Production Mode with Nginx

```bash
# Start with nginx reverse proxy
docker-compose --profile production up -d

# This starts:
# - mshh-app (backend + frontend)
# - nginx (reverse proxy on port 80/443)
```

### Environment Variables

Create `.env` file in root directory:

```bash
# Application
JULIA_NUM_THREADS=auto
GENIE_ENV=prod
PORT=8000

# Logging
LOG_LEVEL=info
LOG_FILE=/app/logs/mshh.log

# Timeouts
DEFAULT_SOLVER_TIMEOUT=600
MAX_CONCURRENT_JOBS=10

# Security (for production)
CORS_ORIGINS=https://yourdomain.com
API_KEY_ENABLED=true
API_KEY=your-secret-key-here
```

### Data Persistence

Volumes are automatically mounted for:
- `/app/instances` - Problem instance files
- `/app/results` - Solution output files
- `/app/logs` - Application logs

```bash
# Backup instances
docker cp mshh-solver:/app/instances ./backup/instances

# Restore instances
docker cp ./backup/instances mshh-solver:/app/instances
```

### Scaling

```bash
# Scale application horizontally
docker-compose up -d --scale mshh-app=3

# Note: Requires load balancer configuration
```

---

## Manual Deployment

### Prerequisites

**Backend:**
- Julia 1.9 or higher
- System packages: `build-essential`, `libssl-dev`

**Frontend:**
- Node.js 18 or higher
- npm 9 or higher

### Backend Setup

```bash
# Install Julia (Ubuntu/Debian)
wget https://julialang-s3.julialang.org/bin/linux/x64/1.9/julia-1.9.3-linux-x86_64.tar.gz
tar -xvzf julia-1.9.3-linux-x86_64.tar.gz
sudo mv julia-1.9.3 /opt/
sudo ln -s /opt/julia-1.9.3/bin/julia /usr/local/bin/julia

# Clone and setup
git clone https://github.com/kkaragul/JuLog.git
cd JuLog/backend

# Install Julia dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# Run tests
julia --project=. test/run_all_tests.jl

# Start server
julia --project=. server.jl
```

### Frontend Setup

```bash
cd JuLog/frontend

# Install dependencies
npm ci --production

# Build for production
npm run build

# Serve with a static file server
npm install -g serve
serve -s dist -l 3000
```

### Systemd Service (Linux)

Create `/etc/systemd/system/mshh-backend.service`:

```ini
[Unit]
Description=MSHH Solver Backend
After=network.target

[Service]
Type=simple
User=mshh
WorkingDirectory=/opt/JuLog/backend
Environment="JULIA_PROJECT=/opt/JuLog/backend"
Environment="GENIE_ENV=prod"
ExecStart=/usr/local/bin/julia server.jl
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable mshh-backend
sudo systemctl start mshh-backend
sudo systemctl status mshh-backend
```

### Nginx Configuration

Create `/etc/nginx/sites-available/mshh`:

```nginx
upstream mshh_backend {
    server localhost:8000;
}

server {
    listen 80;
    server_name mshh.yourdomain.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name mshh.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/mshh.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mshh.yourdomain.com/privkey.pem;

    # API proxy
    location /api/ {
        proxy_pass http://mshh_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        # Timeouts for long-running jobs
        proxy_read_timeout 600s;
        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
    }

    # WebSocket proxy
    location /ws/ {
        proxy_pass http://mshh_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    # Frontend static files
    location / {
        root /opt/JuLog/frontend/dist;
        try_files $uri $uri/ /index.html;
    }
}
```

Enable:

```bash
sudo ln -s /etc/nginx/sites-available/mshh /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## Production Considerations

### Security

**1. API Authentication**

Add middleware in `backend/routes/api.jl`:

```julia
# Simple API key authentication
function api_auth_middleware()
    return function(req, res)
        api_key = get(req.headers, "X-API-Key", "")
        if api_key != ENV["API_KEY"]
            return HTTP.Response(401, "Unauthorized")
        end
        return nothing
    end
end
```

**2. Rate Limiting**

Use nginx:

```nginx
http {
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

    server {
        location /api/ {
            limit_req zone=api_limit burst=20 nodelay;
            # ... rest of config
        }
    }
}
```

**3. CORS Configuration**

In production, restrict CORS to your domain:

```julia
# backend/server.jl
Genie.config.cors_headers["Access-Control-Allow-Origin"] = "https://yourdomain.com"
```

### Performance Optimization

**1. Julia Compilation**

Pre-compile on deployment:

```bash
julia --project=. -e 'using Pkg; Pkg.precompile()'
```

**2. Thread Configuration**

```bash
export JULIA_NUM_THREADS=8
julia --threads=8 server.jl
```

**3. Frontend Optimization**

```bash
# Enable gzip in nginx
gzip on;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
gzip_min_length 1000;

# Browser caching
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

### Database Integration (Optional)

For storing job history and results:

```julia
# Add to Project.toml
[deps]
SQLite = "0aa819cd-b072-5ff4-a722-6bc24af294d9"

# Create results database
using SQLite
db = SQLite.DB("results.db")
SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS jobs (
        id TEXT PRIMARY KEY,
        domain TEXT,
        instance TEXT,
        best_objective REAL,
        computation_time REAL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
""")
```

---

## Monitoring & Maintenance

### Health Checks

```bash
# API health
curl http://localhost:8000/api/health

# Expected response:
# {"status":"healthy","version":"1.0.0","domains":[...]}
```

### Logging

**View logs:**

```bash
# Docker
docker-compose logs -f mshh-app

# Systemd
sudo journalctl -u mshh-backend -f

# Direct logs
tail -f /app/logs/mshh.log
```

**Log rotation** (add to `/etc/logrotate.d/mshh`):

```
/app/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 mshh mshh
    sharedscripts
    postrotate
        systemctl reload mshh-backend > /dev/null 2>&1 || true
    endscript
}
```

### Monitoring

**Prometheus metrics** (future enhancement):

```julia
# Add Prometheus.jl
using Prometheus

# Expose metrics
route("/metrics") do
    return Prometheus.generate_metrics()
end
```

### Backup Strategy

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/backups/mshh/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup instances
tar -czf $BACKUP_DIR/instances.tar.gz /app/instances

# Backup results
tar -czf $BACKUP_DIR/results.tar.gz /app/results

# Backup database (if using SQLite)
cp /app/results.db $BACKUP_DIR/

# Keep last 30 days
find /backups/mshh -type d -mtime +30 -exec rm -rf {} \;
```

Add to crontab:

```bash
0 2 * * * /opt/scripts/backup.sh
```

---

## Troubleshooting

### Common Issues

**1. Julia Package Errors**

```bash
# Clear package cache
rm -rf ~/.julia/compiled

# Reinstall
julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
```

**2. Port Already in Use**

```bash
# Find process
sudo lsof -i :8000

# Kill process
sudo kill -9 <PID>
```

**3. Memory Issues**

```julia
# Add to server.jl
GC.gc()  # Force garbage collection after heavy operations
```

**4. Docker Build Fails**

```bash
# Clean build
docker-compose down
docker system prune -a
docker-compose build --no-cache
```

**5. Frontend Not Loading**

```bash
# Rebuild frontend
cd frontend
rm -rf node_modules dist
npm install
npm run build
```

### Performance Issues

**Slow Solver:**
- Increase time limit parameters
- Check thread utilization: `julia> Threads.nthreads()`
- Profile code: `using Profile; @profile solve!(solver)`

**High Memory Usage:**
- Limit concurrent jobs
- Implement job queue
- Add garbage collection between solves

**API Timeouts:**
- Increase nginx timeout
- Check solver parameters
- Monitor with `htop` or `docker stats`

### Getting Help

1. Check logs first
2. Review [GitHub Issues](https://github.com/kkaragul/JuLog/issues)
3. Consult [API Documentation](backend/docs/openapi.yaml)
4. Run test suite to isolate issue

---

## Update Procedure

```bash
# Backup first!
./backup.sh

# Pull updates
git pull origin main

# Docker deployment
docker-compose down
docker-compose build
docker-compose up -d

# Manual deployment
cd backend
julia --project=. -e 'using Pkg; Pkg.update()'
sudo systemctl restart mshh-backend

cd ../frontend
npm install
npm run build
```

---

## Performance Benchmarks

### Expected Response Times

| Domain | Instance Size | Time (avg) |
|--------|--------------|------------|
| TSP | 50 cities | ~30s |
| CVRP | 100 customers | ~60s |
| JobShop | 20x10 | ~45s |
| FlowShop | 50x10 | ~40s |

### Resource Usage

| Component | CPU | RAM | Disk I/O |
|-----------|-----|-----|----------|
| Backend | 30-80% | 2-4 GB | Low |
| Frontend | <5% | 100 MB | Minimal |
| Nginx | <5% | 50 MB | Low |

---

## Support

For deployment assistance:
- Email: support@example.com
- Issues: https://github.com/kkaragul/JuLog/issues
- Documentation: https://docs.example.com

---

*Last updated: November 2025*
