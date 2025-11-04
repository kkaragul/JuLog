"""
Multi-Stage Selection Hyper-Heuristic (MSHH) Framework

Implementation based on:
Kheiri, A., & Özcan, E. (2016). An iterated multi-stage selection hyper-heuristic.
European Journal of Operational Research.

This module provides the main interface for the MSHH solver framework.
"""
module MSHH

# Export main types and functions
export AbstractDomain, AbstractSolution, AbstractLLH
export solve!, get_objective_value, is_feasible
export MSHHSolver, MSHHParameters, MSHHResult

# Core algorithm components
include("core/MoveAcceptance.jl")
include("core/RelayHybridisation.jl")
include("core/S1HH.jl")
include("core/S2HH.jl")
include("core/MultiStageLevel.jl")

# Domain abstractions
include("domains/AbstractDomain.jl")

# Specific domains
include("domains/TSP.jl")
include("domains/CVRP.jl")
include("domains/CVRPTW.jl")
include("domains/EVRP.jl")
include("domains/CO2VRP.jl")
include("domains/BinPacking.jl")

# Low-level heuristics (included in domain files)

# Utilities
include("utils/parsers.jl")

using .MoveAcceptance
using .RelayHybridisation
using .S1HH: stage_one_hh
using .S2HH: stage_two_hh
using .MultiStageLevel: multi_stage_level

"""
    MSHHParameters

Parameters for the MSHH algorithm as defined in the paper (Section 5.1).

Default values from paper:
- τ = 15ms (time per heuristic application)
- d = 9s (duration before epsilon update)
- s1 = 20s (stage 1 termination time without improvement)
- s2 = 5 (number of steps in stage 2)
- PS2HH = 0.3 (probability of applying S2HH)
- C = [0, 3, 6, 9] (threshold adjustment values)
"""
struct MSHHParameters
    τ::Float64              # Time per heuristic application (ms)
    d::Float64              # Duration threshold for epsilon update (s)
    s1::Float64             # Stage 1 termination time (s)
    s2::Int                 # Stage 2 number of steps
    PS2HH::Float64          # Probability to apply S2HH
    C::Vector{Int}          # Threshold adjustment values
    time_limit::Float64     # Overall time limit (s)

    function MSHHParameters(;
        τ = 0.015,          # 15ms in seconds
        d = 9.0,
        s1 = 20.0,
        s2 = 5,
        PS2HH = 0.3,
        C = [0, 3, 6, 9],
        time_limit = 600.0
    )
        new(τ, d, s1, s2, PS2HH, C, time_limit)
    end
end

"""
    MSHHResult

Result structure containing the best solution found and statistics.
"""
struct MSHHResult
    best_solution::Any
    best_objective::Float64
    computation_time::Float64
    stages_executed::Int
    improvements::Int
    llh_usage::Dict{String, Int}
end

"""
    MSHHSolver

Main solver structure for the MSHH framework.
"""
struct MSHHSolver
    domain::AbstractDomain
    params::MSHHParameters
end

"""
    solve!(solver::MSHHSolver, initial_solution=nothing)

Main entry point for solving a problem using MSHH.
Implements Algorithm 1 (Multi-stage hyper-heuristic framework) from the paper.

# Arguments
- `solver::MSHHSolver`: The configured solver
- `initial_solution`: Optional initial solution (will be generated if not provided)

# Returns
- `MSHHResult`: Result containing best solution and statistics
"""
function solve!(solver::MSHHSolver, initial_solution=nothing)
    # Generate initial solution if not provided
    if isnothing(initial_solution)
        initial_solution = generate_initial_solution(solver.domain)
    end

    # Run multi-stage level algorithm (Algorithm 2 from paper)
    result = multi_stage_level(
        solver.domain,
        initial_solution,
        solver.params
    )

    return result
end

end # module
