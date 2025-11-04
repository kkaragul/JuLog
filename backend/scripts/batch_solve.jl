"""
Batch Solver for MSHH Framework

Solves multiple instances of a domain and generates comprehensive reports.

Usage:
    julia batch_solve.jl <domain> [options]

Options:
    --time-limit <seconds>    Time limit per instance (default: 300)
    --output <directory>      Output directory for results (default: results/)
    --instances <directory>   Instance directory (default: instances/<domain>/)
    --params <json_file>      Parameter configuration file

Examples:
    julia batch_solve.jl tsp --time-limit 60
    julia batch_solve.jl cvrp --instances custom_instances/
    julia batch_solve.jl jobshop --output batch_results/
"""

using Dates
using Printf
using JSON3

# Include MSHH framework
include("../src/MSHH.jl")
using .MSHH
using .MSHH.TSPDomain
using .MSHH.CVRPDomain
using .MSHH.CVRPTWDomain
using .MSHH.EVRPDomain
using .MSHH.CO2VRPDomain
using .MSHH.BinPackingDomain
using .MSHH.JobShopDomain
using .MSHH.FlowShopDomain
using .MSHH.Parsers

"""
Result structure for batch solving
"""
mutable struct BatchResult
    instance_name::String
    domain::String
    instance_size::String
    initial_objective::Float64
    best_objective::Float64
    improvement::Float64
    improvement_pct::Float64
    computation_time::Float64
    stages_executed::Int
    s1hh_executions::Int
    s2hh_executions::Int
    status::String
    error_message::String

    function BatchResult(name::String, domain::String)
        new(name, domain, "", Inf, Inf, 0.0, 0.0, 0.0, 0, 0, 0, "pending", "")
    end
end

"""
Get domain-specific parser and domain constructor
"""
function get_domain_functions(domain_type::String)
    if domain_type == "tsp"
        return parse_tsp, TSP, ".tsp"
    elseif domain_type == "cvrp"
        return parse_vrp, CVRP, ".vrp"
    elseif domain_type == "cvrptw"
        return parse_solomon, CVRPTW, ".txt"
    elseif domain_type == "evrp"
        return parse_evrp, EVRP, ".evrp"
    elseif domain_type == "co2vrp"
        return parse_co2vrp, CO2VRP, ".vrp"
    elseif domain_type == "binpacking"
        return parse_bpp, BinPacking, ".bpp"
    elseif domain_type == "jobshop"
        return parse_jobshop, JobShop, ".txt"
    elseif domain_type == "flowshop"
        return parse_flowshop, FlowShop, ".txt"
    else
        error("Unknown domain: $domain_type")
    end
end

"""
Get instance size descriptor
"""
function get_instance_size(domain_type::String, instance)
    if domain_type == "tsp"
        return "$(instance.n_cities) cities"
    elseif domain_type in ["cvrp", "cvrptw", "evrp", "co2vrp"]
        return "$(instance.n_customers) customers, $(instance.n_vehicles) vehicles"
    elseif domain_type == "binpacking"
        return "$(instance.n_items) items"
    elseif domain_type in ["jobshop", "flowshop"]
        return "$(instance.n_jobs) jobs, $(instance.n_machines) machines"
    else
        return "unknown"
    end
end

"""
Solve a single instance and return result
"""
function solve_instance(
    instance_file::String,
    domain_type::String,
    params::MSHHParameters
)
    result = BatchResult(basename(instance_file), domain_type)

    try
        # Get domain-specific functions
        parse_func, domain_constructor, _ = get_domain_functions(domain_type)

        println("  Parsing instance...")
        instance = parse_func(instance_file)
        result.instance_size = get_instance_size(domain_type, instance)

        println("  Creating domain...")
        domain = domain_constructor(instance)

        println("  Generating initial solution...")
        initial_solution = generate_initial_solution(domain)
        result.initial_objective = get_objective_value(initial_solution)

        println("  Running MSHH solver...")
        solver = MSHHSolver(domain, params)
        start_time = time()
        solve_result = solve!(solver)
        elapsed = time() - start_time

        # Extract results
        result.best_objective = solve_result.best_objective
        result.computation_time = elapsed
        result.stages_executed = solve_result.statistics.stages_executed
        result.s1hh_executions = solve_result.statistics.s1hh_executions
        result.s2hh_executions = solve_result.statistics.s2hh_executions

        # Calculate improvement
        result.improvement = result.initial_objective - result.best_objective
        result.improvement_pct = (result.improvement / result.initial_objective) * 100.0

        result.status = "completed"

        println("  ✓ Completed: Best=$(result.best_objective), Time=$(round(elapsed, digits=2))s")

    catch e
        result.status = "error"
        result.error_message = string(e)
        println("  ✗ Error: $e")
    end

    return result
end

"""
Find all instance files in directory
"""
function find_instances(instance_dir::String, extension::String)
    if !isdir(instance_dir)
        return String[]
    end

    instances = String[]
    for file in readdir(instance_dir, join=true)
        if isfile(file) && endswith(file, extension)
            push!(instances, file)
        end
    end

    return sort(instances)
end

"""
Save results to CSV
"""
function save_results_csv(results::Vector{BatchResult}, output_file::String)
    open(output_file, "w") do io
        # Header
        println(io, "Instance,Domain,Size,Initial,Best,Improvement,Improvement%,Time(s),Stages,S1HH,S2HH,Status,Error")

        # Data rows
        for r in results
            println(io, join([
                r.instance_name,
                r.domain,
                r.instance_size,
                @sprintf("%.2f", r.initial_objective),
                @sprintf("%.2f", r.best_objective),
                @sprintf("%.2f", r.improvement),
                @sprintf("%.2f", r.improvement_pct),
                @sprintf("%.2f", r.computation_time),
                r.stages_executed,
                r.s1hh_executions,
                r.s2hh_executions,
                r.status,
                replace(r.error_message, "," => ";")
            ], ","))
        end
    end

    println("\n✓ Results saved to: $output_file")
end

"""
Generate summary report
"""
function generate_summary(results::Vector{BatchResult})
    completed = filter(r -> r.status == "completed", results)
    failed = filter(r -> r.status == "error", results)

    println("\n" * "="^80)
    println("BATCH SOLVE SUMMARY")
    println("="^80)
    println()

    if isempty(results)
        println("No instances processed.")
        return
    end

    println("Total Instances:  $(length(results))")
    println("Completed:        $(length(completed))")
    println("Failed:           $(length(failed))")
    println()

    if !isempty(completed)
        avg_improvement = mean([r.improvement_pct for r in completed])
        avg_time = mean([r.computation_time for r in completed])
        total_time = sum([r.computation_time for r in completed])
        avg_stages = mean([r.stages_executed for r in completed])

        println("Performance Statistics:")
        println("  Average Improvement:  $(round(avg_improvement, digits=2))%")
        println("  Average Time:         $(round(avg_time, digits=2))s")
        println("  Total Time:           $(round(total_time, digits=2))s")
        println("  Average Stages:       $(round(avg_stages, digits=1))")
        println()

        println("Best Results:")
        sorted = sort(completed, by=r -> r.improvement_pct, rev=true)
        for (i, r) in enumerate(sorted[1:min(5, length(sorted))])
            println("  $i. $(r.instance_name): $(round(r.improvement_pct, digits=2))% improvement")
        end
        println()
    end

    if !isempty(failed)
        println("Failed Instances:")
        for r in failed
            println("  ✗ $(r.instance_name): $(r.error_message)")
        end
        println()
    end

    println("="^80)
end

"""
Main batch solving function
"""
function batch_solve(
    domain_type::String;
    time_limit::Float64 = 300.0,
    output_dir::String = "results",
    instance_dir::Union{String, Nothing} = nothing,
    param_file::Union{String, Nothing} = nothing
)
    println("="^80)
    println("MSHH BATCH SOLVER")
    println("="^80)
    println()
    println("Domain:       $(uppercase(domain_type))")
    println("Time Limit:   $(time_limit)s per instance")
    println("Output Dir:   $output_dir")
    println()

    # Setup directories
    mkpath(output_dir)

    if isnothing(instance_dir)
        instance_dir = joinpath(@__DIR__, "..", "instances", domain_type)
    end

    # Get domain functions
    _, _, extension = get_domain_functions(domain_type)

    # Find instances
    instance_files = find_instances(instance_dir, extension)

    if isempty(instance_files)
        println("❌ No instances found in: $instance_dir")
        println("   Expected extension: $extension")
        return
    end

    println("Found $(length(instance_files)) instances in: $instance_dir")
    println()

    # Load or create parameters
    if !isnothing(param_file) && isfile(param_file)
        # Load custom parameters from JSON
        println("Loading parameters from: $param_file")
        param_dict = JSON3.read(read(param_file, String))
        params = MSHHParameters(;
            τ = get(param_dict, :tau, 0.015),
            d = get(param_dict, :d, 9.0),
            s1 = get(param_dict, :s1, 20.0),
            s2 = get(param_dict, :s2, 5),
            PS2HH = get(param_dict, :PS2HH, 0.3),
            time_limit = time_limit
        )
    else
        # Use defaults
        params = MSHHParameters(time_limit = time_limit)
    end

    # Solve each instance
    results = BatchResult[]
    start_time = time()

    for (idx, instance_file) in enumerate(instance_files)
        println("─"^80)
        println("[$idx/$(length(instance_files))] Solving: $(basename(instance_file))")
        println("─"^80)

        result = solve_instance(instance_file, domain_type, params)
        push!(results, result)

        println()
    end

    total_elapsed = time() - start_time

    # Save results
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    csv_file = joinpath(output_dir, "batch_$(domain_type)_$(timestamp).csv")
    save_results_csv(results, csv_file)

    # Generate summary
    generate_summary(results)

    println("Total Elapsed Time: $(round(total_elapsed, digits=2))s")
    println()
end

"""
Parse command line arguments
"""
function parse_args(args::Vector{String})
    if isempty(args)
        println("Usage: julia batch_solve.jl <domain> [options]")
        println("\nDomains: tsp, cvrp, cvrptw, evrp, co2vrp, binpacking, jobshop, flowshop")
        println("\nOptions:")
        println("  --time-limit <seconds>")
        println("  --output <directory>")
        println("  --instances <directory>")
        println("  --params <json_file>")
        exit(1)
    end

    domain = args[1]
    time_limit = 300.0
    output_dir = "results"
    instance_dir = nothing
    param_file = nothing

    i = 2
    while i <= length(args)
        if args[i] == "--time-limit" && i < length(args)
            time_limit = parse(Float64, args[i+1])
            i += 2
        elseif args[i] == "--output" && i < length(args)
            output_dir = args[i+1]
            i += 2
        elseif args[i] == "--instances" && i < length(args)
            instance_dir = args[i+1]
            i += 2
        elseif args[i] == "--params" && i < length(args)
            param_file = args[i+1]
            i += 2
        else
            println("Unknown option: $(args[i])")
            exit(1)
        end
    end

    return domain, time_limit, output_dir, instance_dir, param_file
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    domain, time_limit, output_dir, instance_dir, param_file = parse_args(ARGS)

    batch_solve(
        domain,
        time_limit = time_limit,
        output_dir = output_dir,
        instance_dir = instance_dir,
        param_file = param_file
    )
end
