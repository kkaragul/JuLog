"""
Permutation Flow Shop Scheduling Problem (PFSP)

Minimize makespan for scheduling n jobs through m machines in the same order.
All jobs visit machines in the same sequence (permutation flow shop).
"""
module FlowShopDomain

export FlowShop, FlowShopSolution, FlowShopInstance

"""
    FlowShopInstance

Flow Shop Scheduling problem instance.
Processing times: processing_times[job][machine]
"""
struct FlowShopInstance
    name::String
    n_jobs::Int
    n_machines::Int
    processing_times::Matrix{Int}  # n_jobs × n_machines
end

"""
    FlowShopSolution

Solution representation: permutation of jobs.
All machines process jobs in this order.
"""
mutable struct FlowShopSolution
    job_sequence::Vector{Int}      # Permutation of job IDs
    makespan::Int                  # Total completion time
    completion_times::Matrix{Int}  # completion_times[job][machine]
    is_evaluated::Bool
end

function FlowShopSolution(job_sequence::Vector{Int})
    FlowShopSolution(job_sequence, 0, zeros(Int, 0, 0), false)
end

"""
    FlowShop

Flow Shop Scheduling domain structure.
"""
struct FlowShop
    instance::FlowShopInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function FlowShop(instance::FlowShopInstance)
        # 6 LLHs for Flow Shop Scheduling
        llh_ids = [
            "fs_swap",            # MU: Swap two jobs
            "fs_insert",          # MU: Remove and insert job
            "fs_2opt",            # HC: 2-opt reversal
            "fs_neh",             # HC: NEH-based improvement
            "fs_local_search",    # HC: Local search
            "fs_perturbation"     # MU: Random perturbation
        ]

        llh_map = Dict{String, Function}()
        objective_fn = (sol) -> calculate_makespan(sol, instance)

        new_fs = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "FlowShop")
        )

        # Initialize LLH map
        llh_map["fs_swap"] = (sol, intensity) -> llh_swap(new_fs, sol, intensity)
        llh_map["fs_insert"] = (sol, intensity) -> llh_insert(new_fs, sol, intensity)
        llh_map["fs_2opt"] = (sol, intensity) -> llh_2opt(new_fs, sol, intensity)
        llh_map["fs_neh"] = (sol, intensity) -> llh_neh(new_fs, sol, intensity)
        llh_map["fs_local_search"] = (sol, intensity) -> llh_local_search(new_fs, sol, intensity)
        llh_map["fs_perturbation"] = (sol, intensity) -> llh_perturbation(new_fs, sol, intensity)

        return new_fs
    end
end

"""
    calculate_makespan(solution::FlowShopSolution, instance::FlowShopInstance)::Float64

Calculate makespan using completion time matrix.
"""
function calculate_makespan(solution::FlowShopSolution, instance::FlowShopInstance)::Float64
    if solution.is_evaluated
        return Float64(solution.makespan)
    end

    n_jobs = length(solution.job_sequence)
    n_machines = instance.n_machines

    # Completion times: C[i][j] = completion time of job i on machine j
    C = zeros(Int, n_jobs, n_machines)

    for i in 1:n_jobs
        job = solution.job_sequence[i]

        for j in 1:n_machines
            proc_time = instance.processing_times[job, j]

            if i == 1 && j == 1
                # First job on first machine
                C[i, j] = proc_time
            elseif i == 1
                # First job on subsequent machines
                C[i, j] = C[i, j-1] + proc_time
            elseif j == 1
                # Subsequent jobs on first machine
                C[i, j] = C[i-1, j] + proc_time
            else
                # Subsequent jobs on subsequent machines
                # Must wait for: previous job on this machine AND this job on previous machine
                C[i, j] = max(C[i-1, j], C[i, j-1]) + proc_time
            end
        end
    end

    solution.completion_times = C
    solution.makespan = C[n_jobs, n_machines]
    solution.is_evaluated = true

    return Float64(solution.makespan)
end

"""
    generate_initial_solution(domain::FlowShop)::FlowShopSolution

Generate initial solution using NEH (Nawaz-Enscore-Ham) heuristic.
"""
function generate_initial_solution(domain::FlowShop)::FlowShopSolution
    instance = domain.instance

    # NEH heuristic:
    # 1. Sort jobs by total processing time (descending)
    total_times = [sum(instance.processing_times[j, :]) for j in 1:instance.n_jobs]
    sorted_jobs = sortperm(total_times, rev=true)

    # 2. Build sequence incrementally
    sequence = Int[]

    for job in sorted_jobs
        if isempty(sequence)
            push!(sequence, job)
        else
            # Try inserting job at each position
            best_makespan = Inf
            best_position = 1

            for pos in 1:length(sequence)+1
                # Try insertion
                test_sequence = copy(sequence)
                insert!(test_sequence, pos, job)

                # Calculate makespan
                test_sol = FlowShopSolution(test_sequence)
                makespan = calculate_makespan(test_sol, instance)

                if makespan < best_makespan
                    best_makespan = makespan
                    best_position = pos
                end
            end

            # Insert at best position
            insert!(sequence, best_position, job)
        end
    end

    solution = FlowShopSolution(sequence)
    calculate_makespan(solution, instance)

    return solution
end

# ============================================================================
# LOW-LEVEL HEURISTICS (6 LLHs)
# ============================================================================

"""
LLH1: Swap Two Jobs
"""
function llh_swap(domain::FlowShop, solution::FlowShopSolution, intensity::Float64)::FlowShopSolution
    new_sol = deepcopy(solution)
    n_swaps = max(1, round(Int, intensity * 5))

    for _ in 1:n_swaps
        if length(new_sol.job_sequence) < 2
            break
        end

        i, j = rand(1:length(new_sol.job_sequence), 2)
        new_sol.job_sequence[i], new_sol.job_sequence[j] = new_sol.job_sequence[j], new_sol.job_sequence[i]
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: Insert Job at Different Position
"""
function llh_insert(domain::FlowShop, solution::FlowShopSolution, intensity::Float64)::FlowShopSolution
    new_sol = deepcopy(solution)
    n_inserts = max(1, round(Int, intensity * 3))

    for _ in 1:n_inserts
        if length(new_sol.job_sequence) < 2
            break
        end

        # Remove job
        from_pos = rand(1:length(new_sol.job_sequence))
        job = splice!(new_sol.job_sequence, from_pos)

        # Insert at new position
        to_pos = rand(1:length(new_sol.job_sequence)+1)
        insert!(new_sol.job_sequence, to_pos, job)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH3: 2-opt (Reverse Segment)
"""
function llh_2opt(domain::FlowShop, solution::FlowShopSolution, intensity::Float64)::FlowShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    improved = true
    max_iter = max(1, round(Int, intensity * 10))

    for _ in 1:max_iter
        if !improved
            break
        end
        improved = false

        for i in 1:length(new_sol.job_sequence)-1
            for j in i+2:length(new_sol.job_sequence)
                current_makespan = calculate_makespan(new_sol, instance)

                # Reverse segment [i+1, j]
                reverse!(new_sol.job_sequence, i+1, j)
                new_makespan = calculate_makespan(new_sol, instance)

                if new_makespan < current_makespan
                    improved = true
                else
                    # Revert
                    reverse!(new_sol.job_sequence, i+1, j)
                end
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH4: NEH-based Improvement
Re-apply NEH logic to part of the sequence.
"""
function llh_neh(domain::FlowShop, solution::FlowShopSolution, intensity::Float64)::FlowShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    n_jobs = length(new_sol.job_sequence)
    segment_size = max(3, round(Int, intensity * n_jobs * 0.3))

    if n_jobs < segment_size
        return new_sol
    end

    # Select random segment
    start_pos = rand(1:n_jobs-segment_size+1)
    end_pos = start_pos + segment_size - 1

    # Extract segment
    segment_jobs = splice!(new_sol.job_sequence, start_pos:end_pos)

    # Reinsert jobs one by one at best positions
    for job in segment_jobs
        best_makespan = Inf
        best_position = start_pos

        for pos in start_pos:length(new_sol.job_sequence)+1
            # Try insertion
            insert!(new_sol.job_sequence, pos, job)
            makespan = calculate_makespan(new_sol, instance)

            if makespan < best_makespan
                best_makespan = makespan
                best_position = pos
            end

            deleteat!(new_sol.job_sequence, pos)
        end

        # Insert at best position
        insert!(new_sol.job_sequence, best_position, job)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: Local Search (Adjacent Swaps)
"""
function llh_local_search(domain::FlowShop, solution::FlowShopSolution, intensity::Float64)::FlowShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    improved = true
    max_iter = max(1, round(Int, intensity * 15))

    for _ in 1:max_iter
        if !improved
            break
        end
        improved = false

        # Try all adjacent swaps
        for i in 1:length(new_sol.job_sequence)-1
            current_makespan = calculate_makespan(new_sol, instance)

            # Swap adjacent jobs
            new_sol.job_sequence[i], new_sol.job_sequence[i+1] =
                new_sol.job_sequence[i+1], new_sol.job_sequence[i]

            new_makespan = calculate_makespan(new_sol, instance)

            if new_makespan < current_makespan
                improved = true
            else
                # Revert
                new_sol.job_sequence[i], new_sol.job_sequence[i+1] =
                    new_sol.job_sequence[i+1], new_sol.job_sequence[i]
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH6: Random Perturbation
"""
function llh_perturbation(domain::FlowShop, solution::FlowShopSolution, intensity::Float64)::FlowShopSolution
    new_sol = deepcopy(solution)

    n_moves = max(3, round(Int, intensity * 8))

    for _ in 1:n_moves
        move_type = rand(1:3)

        if move_type == 1
            new_sol = llh_swap(domain, new_sol, 0.3)
        elseif move_type == 2
            new_sol = llh_insert(domain, new_sol, 0.3)
        else
            new_sol = llh_2opt(domain, new_sol, 0.5)
        end
    end

    return new_sol
end

end # module
