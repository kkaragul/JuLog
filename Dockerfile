# MSHH Framework - Production Docker Image
# Multi-stage build for optimized image size

# Stage 1: Julia backend builder
FROM julia:1.9 as backend-builder

WORKDIR /app/backend

# Copy backend files
COPY backend/Project.toml backend/Manifest.toml ./

# Install Julia dependencies
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# Copy backend source
COPY backend/ .

# Stage 2: Frontend builder
FROM node:18-alpine as frontend-builder

WORKDIR /app/frontend

# Copy frontend package files
COPY frontend/package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy frontend source
COPY frontend/ .

# Build frontend for production
RUN npm run build

# Stage 3: Production image
FROM julia:1.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend from builder
COPY --from=backend-builder /app/backend /app/backend

# Copy built frontend from builder
COPY --from=frontend-builder /app/frontend/dist /app/frontend/dist

# Create directories for instances and results
RUN mkdir -p /app/instances/{tsp,cvrp,cvrptw,evrp,co2vrp,binpacking,jobshop,flowshop}
RUN mkdir -p /app/results

# Set environment variables
ENV JULIA_PROJECT=/app/backend
ENV GENIE_ENV=prod
ENV PORT=8000

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/api/health || exit 1

# Run the application
WORKDIR /app/backend
CMD ["julia", "--project=.", "server.jl"]
