"""
Batch Solving API Endpoints

Provides endpoints for batch solving multiple instances via web interface.
"""

# Batch job storage
const BATCH_JOBS = Dict{String, Any}()

"""
    POST /api/batch/start

Start a batch solving job.

Request:
{
    "domain": "tsp",
    "instance_pattern": "*.tsp",  // or specific files
    "time_limit": 60,
    "parameters": {...}
}

Response:
{
    "batch_id": "uuid",
    "status": "running",
    "total_instances": 5
}
"""
route("/api/batch/start", method = POST) do
    try
        payload = jsonpayload()

        domain = get(payload, "domain", "")
        instance_pattern = get(payload, "instance_pattern", "*")
        time_limit = get(payload, "time_limit", 300)
        params_dict = get(payload, "parameters", Dict())

        # Validate domain
        valid_domains = ["tsp", "cvrp", "cvrptw", "evrp", "co2vrp", "binpacking", "jobshop", "flowshop"]
        if !(domain in valid_domains)
            return json(Dict(
                "error" => "Invalid domain: $domain",
                "valid_domains" => valid_domains
            ), status = 400)
        end

        # Get extension for domain
        extensions = Dict(
            "tsp" => ".tsp",
            "cvrp" => ".vrp",
            "cvrptw" => ".txt",
            "evrp" => ".evrp",
            "co2vrp" => ".vrp",
            "binpacking" => ".bpp",
            "jobshop" => ".txt",
            "flowshop" => ".txt"
        )
        ext = extensions[domain]

        # Find instances
        instance_dir = joinpath(@__DIR__, "../../instances", domain)
        instance_files = String[]

        if isdir(instance_dir)
            for file in readdir(instance_dir, join=true)
                if isfile(file) && endswith(file, ext)
                    if instance_pattern == "*" || occursin(instance_pattern, basename(file))
                        push!(instance_files, file)
                    end
                end
            end
        end

        if isempty(instance_files)
            return json(Dict(
                "error" => "No instances found",
                "directory" => instance_dir,
                "pattern" => instance_pattern
            ), status = 404)
        end

        # Generate batch ID
        batch_id = string(uuid4())

        # Initialize batch job
        BATCH_JOBS[batch_id] = Dict(
            "batch_id" => batch_id,
            "domain" => domain,
            "status" => "running",
            "total_instances" => length(instance_files),
            "completed_instances" => 0,
            "failed_instances" => 0,
            "instance_files" => instance_files,
            "results" => [],
            "current_instance" => nothing,
            "started_at" => time(),
            "parameters" => params_dict,
            "time_limit" => time_limit
        )

        # Start batch job in background
        @async begin
            try
                batch_job = BATCH_JOBS[batch_id]

                # Create MSHH parameters
                params = MSHHParameters(
                    τ = get(params_dict, "tau", 0.015),
                    d = get(params_dict, "d", 9.0),
                    s1 = get(params_dict, "s1", 20.0),
                    s2 = get(params_dict, "s2", 5),
                    PS2HH = get(params_dict, "PS2HH", 0.3),
                    time_limit = time_limit
                )

                # Get domain functions
                parse_func, domain_constructor = get_domain_parser(domain)

                # Solve each instance
                for (idx, instance_file) in enumerate(instance_files)
                    batch_job["current_instance"] = basename(instance_file)
                    batch_job["current_index"] = idx

                    result = Dict(
                        "instance_name" => basename(instance_file),
                        "status" => "running"
                    )

                    try
                        # Parse and solve
                        instance = parse_func(instance_file)
                        domain_obj = domain_constructor(instance)

                        initial_solution = generate_initial_solution(domain_obj)
                        initial_obj = get_objective_value(initial_solution)

                        solver = MSHHSolver(domain_obj, params)
                        solve_result = solve!(solver)

                        # Store result
                        result["status"] = "completed"
                        result["initial_objective"] = initial_obj
                        result["best_objective"] = solve_result.best_objective
                        result["improvement"] = initial_obj - solve_result.best_objective
                        result["improvement_pct"] = ((initial_obj - solve_result.best_objective) / initial_obj) * 100.0
                        result["computation_time"] = solve_result.computation_time
                        result["stages_executed"] = solve_result.statistics.stages_executed

                        batch_job["completed_instances"] += 1

                    catch e
                        result["status"] = "failed"
                        result["error"] = string(e)
                        batch_job["failed_instances"] += 1
                    end

                    push!(batch_job["results"], result)
                end

                # Mark batch as completed
                batch_job["status"] = "completed"
                batch_job["completed_at"] = time()
                batch_job["current_instance"] = nothing

            catch e
                BATCH_JOBS[batch_id]["status"] = "error"
                BATCH_JOBS[batch_id]["error"] = string(e)
            end
        end

        return json(Dict(
            "batch_id" => batch_id,
            "status" => "running",
            "total_instances" => length(instance_files),
            "instance_files" => [basename(f) for f in instance_files]
        ))

    catch e
        return json(Dict(
            "error" => string(e),
            "status" => "error"
        ), status = 500)
    end
end

"""
Helper function to get domain parser and constructor
"""
function get_domain_parser(domain::String)
    if domain == "tsp"
        return parse_tsp, TSP
    elseif domain == "cvrp"
        return parse_vrp, CVRP
    elseif domain == "cvrptw"
        return parse_solomon, CVRPTW
    elseif domain == "evrp"
        return parse_evrp, EVRP
    elseif domain == "co2vrp"
        return parse_co2vrp, CO2VRP
    elseif domain == "binpacking"
        return parse_bpp, BinPacking
    elseif domain == "jobshop"
        return parse_jobshop, JobShop
    elseif domain == "flowshop"
        return parse_flowshop, FlowShop
    else
        error("Unknown domain: $domain")
    end
end

"""
    GET /api/batch/status/:batch_id

Get status of a batch job.
"""
route("/api/batch/status/:batch_id") do
    batch_id = @params(:batch_id)

    if !haskey(BATCH_JOBS, batch_id)
        return json(Dict(
            "error" => "Batch job not found"
        ), status = 404)
    end

    return json(BATCH_JOBS[batch_id])
end

"""
    GET /api/batch/list

List all batch jobs.
"""
route("/api/batch/list") do
    jobs = []
    for (batch_id, job) in BATCH_JOBS
        push!(jobs, Dict(
            "batch_id" => batch_id,
            "domain" => job["domain"],
            "status" => job["status"],
            "total_instances" => job["total_instances"],
            "completed_instances" => job["completed_instances"],
            "started_at" => job["started_at"]
        ))
    end

    # Sort by start time (newest first)
    sort!(jobs, by = j -> get(j, "started_at", 0), rev = true)

    return json(Dict("jobs" => jobs))
end

"""
    GET /api/batch/results/:batch_id

Get detailed results of a batch job.
"""
route("/api/batch/results/:batch_id") do
    batch_id = @params(:batch_id)

    if !haskey(BATCH_JOBS, batch_id)
        return json(Dict(
            "error" => "Batch job not found"
        ), status = 404)
    end

    job = BATCH_JOBS[batch_id]

    return json(Dict(
        "batch_id" => batch_id,
        "domain" => job["domain"],
        "status" => job["status"],
        "results" => job["results"],
        "summary" => calculate_batch_summary(job)
    ))
end

"""
Calculate summary statistics for batch job
"""
function calculate_batch_summary(job::Dict)
    completed = filter(r -> r["status"] == "completed", job["results"])

    if isempty(completed)
        return Dict(
            "completed" => 0,
            "failed" => job["failed_instances"],
            "avg_improvement" => 0.0,
            "avg_time" => 0.0
        )
    end

    avg_improvement = mean([r["improvement_pct"] for r in completed])
    avg_time = mean([r["computation_time"] for r in completed])
    total_time = sum([r["computation_time"] for r in completed])

    return Dict(
        "completed" => length(completed),
        "failed" => job["failed_instances"],
        "avg_improvement" => round(avg_improvement, digits=2),
        "avg_time" => round(avg_time, digits=2),
        "total_time" => round(total_time, digits=2),
        "best_improvement" => maximum([r["improvement_pct"] for r in completed])
    )
end

"""
    GET /api/batch/download/:batch_id

Download batch results as CSV.
"""
route("/api/batch/download/:batch_id") do
    batch_id = @params(:batch_id)

    if !haskey(BATCH_JOBS, batch_id)
        return json(Dict(
            "error" => "Batch job not found"
        ), status = 404)
    end

    job = BATCH_JOBS[batch_id]

    # Generate CSV
    csv_content = "Instance,Status,Initial,Best,Improvement,Improvement%,Time(s),Stages,Error\n"

    for result in job["results"]
        csv_content *= "$(result["instance_name"]),"
        csv_content *= "$(result["status"]),"

        if result["status"] == "completed"
            csv_content *= "$(round(result["initial_objective"], digits=2)),"
            csv_content *= "$(round(result["best_objective"], digits=2)),"
            csv_content *= "$(round(result["improvement"], digits=2)),"
            csv_content *= "$(round(result["improvement_pct"], digits=2)),"
            csv_content *= "$(round(result["computation_time"], digits=2)),"
            csv_content *= "$(result["stages_executed"]),"
            csv_content *= "\n"
        else
            csv_content *= ",,,,,,,"
            csv_content *= "$(get(result, "error", ""))\n"
        end
    end

    # Return CSV file
    return HTTP.Response(
        200,
        ["Content-Type" => "text/csv",
         "Content-Disposition" => "attachment; filename=\"batch_$(job["domain"])_$(batch_id).csv\""],
        csv_content
    )
end

"""
    DELETE /api/batch/delete/:batch_id

Delete a batch job from history.
"""
route("/api/batch/delete/:batch_id", method = DELETE) do
    batch_id = @params(:batch_id)

    if !haskey(BATCH_JOBS, batch_id)
        return json(Dict(
            "error" => "Batch job not found"
        ), status = 404)
    end

    delete!(BATCH_JOBS, batch_id)

    return json(Dict(
        "status" => "deleted",
        "batch_id" => batch_id
    ))
end

println("✓ Batch API routes loaded")
