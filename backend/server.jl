#!/usr/bin/env julia

"""
MSHH Solver Backend Server

Main entry point for the MSHH solver backend API server.
"""

using Genie, Genie.Router
using Genie.Renderer.Json

# Configure Genie
Genie.config.run_as_server = true
Genie.config.server_host = "0.0.0.0"
Genie.config.server_port = 8000
Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
Genie.config.cors_headers["Access-Control-Allow-Headers"] = "Content-Type"
Genie.config.cors_headers["Access-Control-Allow-Methods"] = "GET,POST,PUT,DELETE,OPTIONS"
Genie.config.cors_allowed_origins = ["*"]

println("="^80)
println("MSHH Solver Backend Server")
println("="^80)
println("Loading modules...")

# Load API routes
include("routes/api.jl")

println("="^80)
println("Server configuration:")
println("  Host: $(Genie.config.server_host)")
println("  Port: $(Genie.config.server_port)")
println("  CORS: Enabled")
println("="^80)
println("Starting server...")
println("API endpoints available at: http://localhost:8000/api/")
println("="^80)

# Start server
Genie.Server.up()
