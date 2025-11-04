"""
WebSocket Routes for MSHH Solver

Provides real-time progress updates via WebSocket connections.
"""

using Genie, Genie.Router
using HTTP

include("../src/utils/WebSocketProgress.jl")
using .WebSocketProgress

"""
WebSocket endpoint for job progress updates.

Connect to: ws://localhost:8000/ws/progress/:job_id

Messages received:
{
    "job_id": "uuid",
    "domain": "TSP",
    "status": "running",
    "elapsed_time": 5.2,
    "current_objective": 1250.5,
    "best_objective": 1200.3,
    "stages_executed": 15,
    "improvements": 8,
    "timestamp": 1234567890.123
}
"""

# WebSocket route for progress updates
# Note: This is a placeholder structure - actual WebSocket implementation
# depends on Genie's WebSocket support which may require additional setup

"""
HTTP endpoint to get progress (alternative to WebSocket for polling)

GET /api/progress/:job_id
"""
route("/api/progress/:job_id") do
    job_id = @params(:job_id)
    progress = get_job_progress(job_id)

    return json(progress)
end

println("✓ WebSocket routes loaded")
