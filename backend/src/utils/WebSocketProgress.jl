"""
WebSocket Progress Module

Provides real-time progress updates for MSHH solver via WebSocket.
Clients can subscribe to job updates and receive live statistics.
"""
module WebSocketProgress

export ProgressTracker, register_job, update_progress, broadcast_update

using JSON3

# Store active WebSocket connections per job
const JOB_SUBSCRIBERS = Dict{String, Vector{Any}}()

# Store progress data per job
const JOB_PROGRESS = Dict{String, Dict{String, Any}}()

"""
    ProgressTracker

Tracks solving progress for WebSocket broadcasting.
"""
mutable struct ProgressTracker
    job_id::String
    domain_type::String
    start_time::Float64
    last_update::Float64

    # Statistics
    current_objective::Float64
    best_objective::Float64
    stages_executed::Int
    s1hh_executions::Int
    s2hh_executions::Int
    improvements::Int

    # LLH usage
    llh_usage::Dict{String, Int}

    # Status
    status::String  # "running", "completed", "error"

    function ProgressTracker(job_id::String, domain_type::String)
        new(
            job_id,
            domain_type,
            time(),
            time(),
            Inf,
            Inf,
            0,
            0,
            0,
            0,
            Dict{String, Int}(),
            "running"
        )
    end
end

"""
    register_job(job_id::String, domain_type::String)

Register a new solving job for progress tracking.
"""
function register_job(job_id::String, domain_type::String)
    tracker = ProgressTracker(job_id, domain_type)
    JOB_PROGRESS[job_id] = Dict(
        "job_id" => job_id,
        "domain" => domain_type,
        "status" => "running",
        "start_time" => tracker.start_time,
        "current_objective" => Inf,
        "best_objective" => Inf,
        "stages_executed" => 0,
        "improvements" => 0
    )
    JOB_SUBSCRIBERS[job_id] = []
    return tracker
end

"""
    update_progress(tracker::ProgressTracker, stats::Dict)

Update progress with new statistics.
"""
function update_progress(tracker::ProgressTracker, stats::Dict)
    current_time = time()
    elapsed = current_time - tracker.start_time

    # Update tracker fields
    if haskey(stats, "current_objective")
        tracker.current_objective = stats["current_objective"]
    end
    if haskey(stats, "best_objective")
        tracker.best_objective = stats["best_objective"]
    end
    if haskey(stats, "stages_executed")
        tracker.stages_executed = stats["stages_executed"]
    end
    if haskey(stats, "improvements")
        tracker.improvements = stats["improvements"]
    end

    tracker.last_update = current_time

    # Update job progress data
    JOB_PROGRESS[tracker.job_id] = Dict(
        "job_id" => tracker.job_id,
        "domain" => tracker.domain_type,
        "status" => tracker.status,
        "elapsed_time" => elapsed,
        "current_objective" => tracker.current_objective,
        "best_objective" => tracker.best_objective,
        "stages_executed" => tracker.stages_executed,
        "s1hh_executions" => tracker.s1hh_executions,
        "s2hh_executions" => tracker.s2hh_executions,
        "improvements" => tracker.improvements,
        "llh_usage" => tracker.llh_usage,
        "timestamp" => current_time
    )

    # Broadcast to subscribers
    broadcast_update(tracker.job_id)
end

"""
    broadcast_update(job_id::String)

Broadcast progress update to all subscribers of a job.
"""
function broadcast_update(job_id::String)
    if !haskey(JOB_PROGRESS, job_id)
        return
    end

    progress_data = JOB_PROGRESS[job_id]
    message = JSON3.write(progress_data)

    # Send to all subscribers
    if haskey(JOB_SUBSCRIBERS, job_id)
        for ws in JOB_SUBSCRIBERS[job_id]
            try
                # Send message to WebSocket
                # Note: Actual implementation depends on Genie's WebSocket API
                # This is a placeholder for the broadcast mechanism
                # In real implementation: write(ws, message)
            catch e
                @warn "Failed to send WebSocket message" exception=e
            end
        end
    end
end

"""
    subscribe_to_job(job_id::String, ws::Any)

Subscribe a WebSocket connection to job updates.
"""
function subscribe_to_job(job_id::String, ws::Any)
    if !haskey(JOB_SUBSCRIBERS, job_id)
        JOB_SUBSCRIBERS[job_id] = []
    end

    push!(JOB_SUBSCRIBERS[job_id], ws)

    # Send current progress immediately
    if haskey(JOB_PROGRESS, job_id)
        message = JSON3.write(JOB_PROGRESS[job_id])
        try
            # write(ws, message)
        catch e
            @warn "Failed to send initial progress" exception=e
        end
    end
end

"""
    unsubscribe_from_job(job_id::String, ws::Any)

Unsubscribe a WebSocket connection from job updates.
"""
function unsubscribe_from_job(job_id::String, ws::Any)
    if haskey(JOB_SUBSCRIBERS, job_id)
        filter!(x -> x !== ws, JOB_SUBSCRIBERS[job_id])
    end
end

"""
    complete_job(job_id::String, final_stats::Dict)

Mark a job as completed and send final update.
"""
function complete_job(job_id::String, final_stats::Dict)
    if haskey(JOB_PROGRESS, job_id)
        JOB_PROGRESS[job_id]["status"] = "completed"
        JOB_PROGRESS[job_id]["final_objective"] = get(final_stats, "best_objective", Inf)
        JOB_PROGRESS[job_id]["total_time"] = get(final_stats, "computation_time", 0.0)

        broadcast_update(job_id)

        # Clean up subscribers after a delay
        @async begin
            sleep(60)  # Keep data for 1 minute
            cleanup_job(job_id)
        end
    end
end

"""
    error_job(job_id::String, error_msg::String)

Mark a job as failed with error message.
"""
function error_job(job_id::String, error_msg::String)
    if haskey(JOB_PROGRESS, job_id)
        JOB_PROGRESS[job_id]["status"] = "error"
        JOB_PROGRESS[job_id]["error"] = error_msg

        broadcast_update(job_id)

        # Clean up after delay
        @async begin
            sleep(60)
            cleanup_job(job_id)
        end
    end
end

"""
    cleanup_job(job_id::String)

Clean up job progress data and subscribers.
"""
function cleanup_job(job_id::String)
    if haskey(JOB_SUBSCRIBERS, job_id)
        delete!(JOB_SUBSCRIBERS, job_id)
    end
    if haskey(JOB_PROGRESS, job_id)
        delete!(JOB_PROGRESS, job_id)
    end
end

"""
    get_job_progress(job_id::String)

Get current progress for a job.
"""
function get_job_progress(job_id::String)
    return get(JOB_PROGRESS, job_id, Dict("error" => "Job not found"))
end

end # module
