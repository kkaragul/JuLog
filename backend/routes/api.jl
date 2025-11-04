"""
MSHH Solver REST API

Provides endpoints for solving TSP and CVRP problems using MSHH.
"""

using Genie, Genie.Router, Genie.Renderer.Json
using HTTP
using JSON3

# Include MSHH module
include("../src/MSHH.jl")
using .MSHH
using .MSHH.TSPDomain
using .MSHH.CVRPDomain
using .MSHH.Parsers

# Store active solving jobs
const ACTIVE_JOBS = Dict{String, Any}()

"""
    POST /api/solve/tsp

Solve a TSP instance.

Request body:
{
    "instance_file": "path/to/instance.tsp",
    "time_limit": 60,
    "parameters": {
        "tau": 0.015,
        "d": 9.0,
        "s1": 20.0,
        "s2": 5,
        "PS2HH": 0.3
    }
}

Response:
{
    "job_id": "uuid",
    "status": "running"
}
"""
route("/api/solve/tsp", method = POST) do
    try
        payload = jsonpayload()

        # Parse instance
        instance_file = get(payload, "instance_file", "")
        if isempty(instance_file) || !isfile(instance_file)
            return json(Dict(
                "error" => "Invalid instance file",
                "status" => "error"
            ), status = 400)
        end

        # Parse parameters
        time_limit = get(payload, "time_limit", 60)
        params_dict = get(payload, "parameters", Dict())

        params = MSHHParameters(
            τ = get(params_dict, "tau", 0.015),
            d = get(params_dict, "d", 9.0),
            s1 = get(params_dict, "s1", 20.0),
            s2 = get(params_dict, "s2", 5),
            PS2HH = get(params_dict, "PS2HH", 0.3),
            time_limit = time_limit
        )

        # Generate job ID
        job_id = string(uuid4())

        # Start solving in background
        @async begin
            try
                # Parse instance
                instance = parse_tsp(instance_file)
                domain = TSP(instance)

                # Create solver
                solver = MSHHSolver(domain, params)

                # Solve
                result = solve!(solver)

                # Store result
                ACTIVE_JOBS[job_id] = Dict(
                    "status" => "completed",
                    "result" => Dict(
                        "best_objective" => result.best_objective,
                        "computation_time" => result.computation_time,
                        "stages_executed" => result.statistics.stages_executed,
                        "s1hh_executions" => result.statistics.s1hh_executions,
                        "s2hh_executions" => result.statistics.s2hh_executions,
                        "tour" => result.best_solution.tour
                    )
                )
            catch e
                ACTIVE_JOBS[job_id] = Dict(
                    "status" => "error",
                    "error" => string(e)
                )
            end
        end

        # Store initial job status
        ACTIVE_JOBS[job_id] = Dict("status" => "running")

        return json(Dict(
            "job_id" => job_id,
            "status" => "running"
        ))

    catch e
        return json(Dict(
            "error" => string(e),
            "status" => "error"
        ), status = 500)
    end
end

"""
    POST /api/solve/cvrp

Solve a CVRP instance.
"""
route("/api/solve/cvrp", method = POST) do
    try
        payload = jsonpayload()

        instance_file = get(payload, "instance_file", "")
        if isempty(instance_file) || !isfile(instance_file)
            return json(Dict(
                "error" => "Invalid instance file",
                "status" => "error"
            ), status = 400)
        end

        time_limit = get(payload, "time_limit", 60)
        params_dict = get(payload, "parameters", Dict())

        params = MSHHParameters(
            τ = get(params_dict, "tau", 0.015),
            d = get(params_dict, "d", 9.0),
            s1 = get(params_dict, "s1", 20.0),
            s2 = get(params_dict, "s2", 5),
            PS2HH = get(params_dict, "PS2HH", 0.3),
            time_limit = time_limit
        )

        job_id = string(uuid4())

        @async begin
            try
                instance = parse_vrp(instance_file)
                domain = CVRP(instance)
                solver = MSHHSolver(domain, params)
                result = solve!(solver)

                # Extract routes
                routes_data = []
                for route in result.best_solution.routes
                    push!(routes_data, Dict(
                        "customers" => route.customers,
                        "load" => route.load
                    ))
                end

                ACTIVE_JOBS[job_id] = Dict(
                    "status" => "completed",
                    "result" => Dict(
                        "best_objective" => result.best_objective,
                        "computation_time" => result.computation_time,
                        "stages_executed" => result.statistics.stages_executed,
                        "routes" => routes_data
                    )
                )
            catch e
                ACTIVE_JOBS[job_id] = Dict(
                    "status" => "error",
                    "error" => string(e)
                )
            end
        end

        ACTIVE_JOBS[job_id] = Dict("status" => "running")

        return json(Dict(
            "job_id" => job_id,
            "status" => "running"
        ))

    catch e
        return json(Dict(
            "error" => string(e),
            "status" => "error"
        ), status = 500)
    end
end

"""
    GET /api/status/:job_id

Get status of a solving job.
"""
route("/api/status/:job_id") do
    job_id = @params(:job_id)

    if !haskey(ACTIVE_JOBS, job_id)
        return json(Dict(
            "error" => "Job not found",
            "status" => "error"
        ), status = 404)
    end

    return json(ACTIVE_JOBS[job_id])
end

"""
    GET /api/instances/list

List available instances.
"""
route("/api/instances/list") do
    try
        instances = Dict(
            "tsp" => [],
            "cvrp" => []
        )

        # List TSP instances
        tsp_dir = joinpath(@__DIR__, "../../instances/tsp")
        if isdir(tsp_dir)
            instances["tsp"] = filter(f -> endswith(f, ".tsp"), readdir(tsp_dir))
        end

        # List CVRP instances
        cvrp_dir = joinpath(@__DIR__, "../../instances/cvrp")
        if isdir(cvrp_dir)
            instances["cvrp"] = filter(f -> endswith(f, ".vrp"), readdir(cvrp_dir))
        end

        return json(instances)

    catch e
        return json(Dict(
            "error" => string(e),
            "status" => "error"
        ), status = 500)
    end
end

"""
    GET /api/health

Health check endpoint.
"""
route("/api/health") do
    return json(Dict(
        "status" => "healthy",
        "version" => "1.0.0",
        "domains" => ["TSP", "CVRP"]
    ))
end

"""
    POST /api/upload/instance

Upload a new instance file.
"""
route("/api/upload/instance", method = POST) do
    try
        files = Genie.Requests.filespayload()

        if !haskey(files, "file")
            return json(Dict(
                "error" => "No file uploaded",
                "status" => "error"
            ), status = 400)
        end

        file = files["file"]
        filename = file.name
        domain_type = get(jsonpayload(), "domain", "tsp")

        # Determine directory
        target_dir = if domain_type == "tsp"
            joinpath(@__DIR__, "../../instances/tsp")
        elseif domain_type == "cvrp"
            joinpath(@__DIR__, "../../instances/cvrp")
        else
            return json(Dict(
                "error" => "Invalid domain type",
                "status" => "error"
            ), status = 400)
        end

        # Save file
        mkpath(target_dir)
        target_path = joinpath(target_dir, filename)
        write(target_path, file.data)

        return json(Dict(
            "status" => "success",
            "filename" => filename,
            "path" => target_path
        ))

    catch e
        return json(Dict(
            "error" => string(e),
            "status" => "error"
        ), status = 500)
    end
end

println("✓ API routes loaded")
