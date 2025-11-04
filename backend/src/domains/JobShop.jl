"""
Job Shop Scheduling Problem (JSP)

Minimize makespan (total completion time) for scheduling n jobs on m machines.
Each job has a sequence of operations, each requiring a specific machine.
"""
module JobShopDomain

export JobShop, JobShopSolution, JobShopInstance

"""
    Operation

A single operation in a job: requires a specific machine for a duration.
"""
struct Operation
    job_id::Int
    operation_id::Int      # Position in job's sequence
    machine_id::Int        # Which machine processes this
    processing_time::Int   # Duration
end

"""
    JobShopInstance

Job Shop Scheduling problem instance.
"""
struct JobShopInstance
    name::String
    n_jobs::Int
    n_machines::Int
    operations::Vector{Vector{Operation}}  # operations[job_id] = list of operations
end

"""
    JobShopSolution

Solution representation: schedule of operations.
Represented as permutation of operations per machine.
"""
mutable struct JobShopSolution
    # Schedule: for each machine, list of operations in execution order
    machine_schedules::Vector{Vector{Operation}}

    # Computed values
    makespan::Int                      # Total completion time
    job_completion_times::Vector{Int}  # When each job finishes
    operation_start_times::Dict{Tuple{Int,Int}, Int}  # (job, op) -> start time
    is_evaluated::Bool
    is_feasible::Bool
end

function JobShopSolution(n_machines::Int)
    JobShopSolution(
        [Vector{Operation}() for _ in 1:n_machines],
        0, Int[], Dict{Tuple{Int,Int}, Int}(), false, true
    )
end

"""
    JobShop

Job Shop Scheduling domain structure.
"""
struct JobShop
    instance::JobShopInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function JobShop(instance::JobShopInstance)
        # 8 LLHs for Job Shop Scheduling
        llh_ids = [
            "js_swap_operations",     # MU: Swap operations on same machine
            "js_shift_operation",     # MU: Shift operation to different position
            "js_swap_jobs",           # MU: Swap blocks of operations
            "js_critical_path",       # HC: Improve critical path
            "js_local_search",        # HC: Local neighborhood search
            "js_reinsert",            # HC: Remove and reinsert operation
            "js_block_move",          # MU: Move block of operations
            "js_perturbation"         # MU: Random perturbation
        ]

        llh_map = Dict{String, Function}()
        objective_fn = (sol) -> calculate_makespan(sol, instance)

        new_js = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "JobShop")
        )

        # Initialize LLH map
        llh_map["js_swap_operations"] = (sol, intensity) -> llh_swap_operations(new_js, sol, intensity)
        llh_map["js_shift_operation"] = (sol, intensity) -> llh_shift_operation(new_js, sol, intensity)
        llh_map["js_swap_jobs"] = (sol, intensity) -> llh_swap_jobs(new_js, sol, intensity)
        llh_map["js_critical_path"] = (sol, intensity) -> llh_critical_path(new_js, sol, intensity)
        llh_map["js_local_search"] = (sol, intensity) -> llh_local_search(new_js, sol, intensity)
        llh_map["js_reinsert"] = (sol, intensity) -> llh_reinsert(new_js, sol, intensity)
        llh_map["js_block_move"] = (sol, intensity) -> llh_block_move(new_js, sol, intensity)
        llh_map["js_perturbation"] = (sol, intensity) -> llh_perturbation(new_js, sol, intensity)

        return new_js
    end
end

"""
    calculate_makespan(solution::JobShopSolution, instance::JobShopInstance)::Float64

Calculate makespan and schedule feasibility.
"""
function calculate_makespan(solution::JobShopSolution, instance::JobShopInstance)::Float64
    if solution.is_evaluated
        return Float64(solution.makespan)
    end

    # Reset
    solution.operation_start_times = Dict{Tuple{Int,Int}, Int}()
    solution.job_completion_times = zeros(Int, instance.n_jobs)

    # Track when each machine becomes available
    machine_available_time = zeros(Int, instance.n_machines)

    # Track when each job's last operation finished
    job_last_op_time = zeros(Int, instance.n_jobs)

    # Process operations machine by machine
    for machine_id in 1:instance.n_machines
        for op in solution.machine_schedules[machine_id]
            # Start time = max(machine available, previous operation in job finished)
            prev_op_finish_time = job_last_op_time[op.job_id]
            machine_ready_time = machine_available_time[machine_id]

            start_time = max(prev_op_finish_time, machine_ready_time)
            finish_time = start_time + op.processing_time

            # Record
            solution.operation_start_times[(op.job_id, op.operation_id)] = start_time
            job_last_op_time[op.job_id] = finish_time
            machine_available_time[machine_id] = finish_time
        end
    end

    # Job completion times
    solution.job_completion_times = job_last_op_time

    # Makespan is maximum completion time
    solution.makespan = maximum(job_last_op_time)
    solution.is_evaluated = true

    # Check feasibility: all operations scheduled exactly once
    total_ops_scheduled = sum(length(schedule) for schedule in solution.machine_schedules)
    total_ops_required = sum(length(ops) for ops in instance.operations)

    solution.is_feasible = (total_ops_scheduled == total_ops_required)

    return Float64(solution.makespan)
end

"""
    generate_initial_solution(domain::JobShop)::JobShopSolution

Generate initial solution using priority dispatching rule.
"""
function generate_initial_solution(domain::JobShop)::JobShopSolution
    instance = domain.instance
    solution = JobShopSolution(instance.n_machines)

    # Use Shortest Processing Time (SPT) rule
    # Track which operation each job is currently on
    job_next_operation = ones(Int, instance.n_jobs)

    # List of available operations
    available_ops = Operation[]

    # Initially, first operation of each job is available
    for job_id in 1:instance.n_jobs
        if !isempty(instance.operations[job_id])
            push!(available_ops, instance.operations[job_id][1])
        end
    end

    # Schedule operations
    while !isempty(available_ops)
        # Select operation with shortest processing time
        sort!(available_ops, by = op -> op.processing_time)
        selected_op = popfirst!(available_ops)

        # Add to machine schedule
        push!(solution.machine_schedules[selected_op.machine_id], selected_op)

        # Move to next operation in the job
        job_id = selected_op.job_id
        job_next_operation[job_id] += 1

        # Add next operation from this job if available
        if job_next_operation[job_id] <= length(instance.operations[job_id])
            next_op = instance.operations[job_id][job_next_operation[job_id]]
            push!(available_ops, next_op)
        end
    end

    calculate_makespan(solution, instance)
    return solution
end

# ============================================================================
# LOW-LEVEL HEURISTICS (8 LLHs)
# ============================================================================

"""
LLH1: Swap Operations on Same Machine
"""
function llh_swap_operations(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    n_swaps = max(1, round(Int, intensity * 5))

    for _ in 1:n_swaps
        # Select random machine with at least 2 operations
        non_empty = filter(i -> length(new_sol.machine_schedules[i]) >= 2, 1:instance.n_machines)
        if isempty(non_empty)
            break
        end

        machine_id = rand(non_empty)
        schedule = new_sol.machine_schedules[machine_id]

        # Swap two adjacent operations
        if length(schedule) >= 2
            i = rand(1:length(schedule)-1)
            schedule[i], schedule[i+1] = schedule[i+1], schedule[i]
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: Shift Operation to Different Position
"""
function llh_shift_operation(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    n_shifts = max(1, round(Int, intensity * 3))

    for _ in 1:n_shifts
        # Select machine
        non_empty = filter(i -> length(new_sol.machine_schedules[i]) >= 2, 1:instance.n_machines)
        if isempty(non_empty)
            break
        end

        machine_id = rand(non_empty)
        schedule = new_sol.machine_schedules[machine_id]

        if length(schedule) >= 2
            # Remove operation
            from_pos = rand(1:length(schedule))
            op = splice!(schedule, from_pos)

            # Insert at new position
            to_pos = rand(1:length(schedule)+1)
            insert!(schedule, to_pos, op)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH3: Swap Job Blocks
Swap blocks of operations from different jobs on same machine.
"""
function llh_swap_jobs(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    # Select machine with multiple jobs
    for machine_id in 1:instance.n_machines
        schedule = new_sol.machine_schedules[machine_id]

        if length(schedule) < 4
            continue
        end

        # Find blocks of same job
        blocks = []
        current_job = schedule[1].job_id
        block_start = 1

        for i in 2:length(schedule)
            if schedule[i].job_id != current_job
                push!(blocks, (block_start, i-1, current_job))
                current_job = schedule[i].job_id
                block_start = i
            end
        end
        push!(blocks, (block_start, length(schedule), current_job))

        # Swap two blocks
        if length(blocks) >= 2
            block1, block2 = rand(blocks, 2)

            # Extract blocks
            ops1 = schedule[block1[1]:block1[2]]
            ops2 = schedule[block2[1]:block2[2]]

            # Swap (simplified: just exchange positions)
            if block1[1] < block2[1]
                splice!(schedule, block2[1]:block2[2], ops1)
                splice!(schedule, block1[1]:block1[2], ops2)
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH4: Critical Path Improvement
Focus on operations on the critical path.
"""
function llh_critical_path(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    # Calculate makespan to get operation times
    calculate_makespan(new_sol, instance)

    # Find critical job (job with makespan completion time)
    critical_job = argmax(new_sol.job_completion_times)

    # Try to improve operations of critical job
    for machine_id in 1:instance.n_machines
        schedule = new_sol.machine_schedules[machine_id]

        # Find operations of critical job
        critical_indices = findall(op -> op.job_id == critical_job, schedule)

        if length(critical_indices) >= 1
            # Try to move critical operation earlier
            for idx in critical_indices
                if idx > 1
                    # Swap with previous
                    schedule[idx], schedule[idx-1] = schedule[idx-1], schedule[idx]
                end
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: Local Search on Machine Schedules
"""
function llh_local_search(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    current_makespan = calculate_makespan(new_sol, instance)
    improved = true
    max_iter = max(1, round(Int, intensity * 10))

    for _ in 1:max_iter
        if !improved
            break
        end
        improved = false

        # Try all adjacent swaps
        for machine_id in 1:instance.n_machines
            schedule = new_sol.machine_schedules[machine_id]

            for i in 1:length(schedule)-1
                # Try swap
                schedule[i], schedule[i+1] = schedule[i+1], schedule[i]
                new_makespan = calculate_makespan(new_sol, instance)

                if new_makespan < current_makespan
                    current_makespan = new_makespan
                    improved = true
                else
                    # Revert
                    schedule[i], schedule[i+1] = schedule[i+1], schedule[i]
                end
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH6: Remove and Reinsert Operation
"""
function llh_reinsert(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    n_moves = max(1, round(Int, intensity * 3))

    for _ in 1:n_moves
        non_empty = filter(i -> length(new_sol.machine_schedules[i]) >= 2, 1:instance.n_machines)
        if isempty(non_empty)
            break
        end

        machine_id = rand(non_empty)
        schedule = new_sol.machine_schedules[machine_id]

        if length(schedule) >= 2
            # Remove random operation
            remove_pos = rand(1:length(schedule))
            op = splice!(schedule, remove_pos)

            # Find best reinsertion position
            best_pos = 1
            best_makespan = Inf

            for pos in 1:length(schedule)+1
                insert!(schedule, pos, op)
                makespan = calculate_makespan(new_sol, instance)

                if makespan < best_makespan
                    best_makespan = makespan
                    best_pos = pos
                end

                deleteat!(schedule, pos)
            end

            # Insert at best position
            insert!(schedule, best_pos, op)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH7: Move Block of Operations
"""
function llh_block_move(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    # Select machine with enough operations
    non_empty = filter(i -> length(new_sol.machine_schedules[i]) >= 3, 1:instance.n_machines)
    if isempty(non_empty)
        return new_sol
    end

    machine_id = rand(non_empty)
    schedule = new_sol.machine_schedules[machine_id]

    # Select block
    block_size = min(3, length(schedule) - 1)
    block_start = rand(1:length(schedule)-block_size+1)
    block_end = block_start + block_size - 1

    # Extract block
    block = splice!(schedule, block_start:block_end)

    # Insert at new position
    new_pos = rand(1:length(schedule)+1)
    for (i, op) in enumerate(block)
        insert!(schedule, new_pos + i - 1, op)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH8: Random Perturbation
"""
function llh_perturbation(domain::JobShop, solution::JobShopSolution, intensity::Float64)::JobShopSolution
    new_sol = deepcopy(solution)

    n_moves = max(3, round(Int, intensity * 8))

    for _ in 1:n_moves
        move_type = rand(1:3)

        if move_type == 1
            new_sol = llh_swap_operations(domain, new_sol, 0.3)
        elseif move_type == 2
            new_sol = llh_shift_operation(domain, new_sol, 0.3)
        else
            new_sol = llh_reinsert(domain, new_sol, 0.5)
        end
    end

    return new_sol
end

end # module
