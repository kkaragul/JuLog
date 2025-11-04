"""
One-Dimensional Bin Packing Problem (1D-BPP)

Minimize the number of bins used to pack all items.
Each bin has a capacity and items have sizes.
"""
module BinPackingDomain

export BinPacking, BPSolution, BPInstance

"""
    BPInstance

Bin Packing problem instance.
"""
struct BPInstance
    name::String
    n_items::Int
    bin_capacity::Int
    item_sizes::Vector{Int}
end

"""
    Bin

A single bin containing items.
"""
mutable struct Bin
    items::Vector{Int}        # Item IDs
    current_load::Int        # Total size of items in bin
    remaining_capacity::Int  # Free space
end

function Bin(capacity::Int)
    Bin(Int[], 0, capacity)
end

"""
    BPSolution

Solution for Bin Packing: assignment of items to bins.
"""
mutable struct BPSolution
    bins::Vector{Bin}
    objective_value::Float64  # Number of bins used
    is_evaluated::Bool
    is_feasible::Bool         # All items packed, no bin exceeds capacity
end

function BPSolution(bins::Vector{Bin})
    BPSolution(bins, Inf, false, true)
end

"""
    BinPacking

Bin Packing domain structure.
"""
struct BinPacking
    instance::BPInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function BinPacking(instance::BPInstance)
        # 7 LLHs for Bin Packing
        llh_ids = [
            "bp_first_fit",       # HC: First-fit improvement
            "bp_best_fit",        # HC: Best-fit improvement
            "bp_swap",            # MU: Swap items between bins
            "bp_repack",          # RR: Empty and repack bins
            "bp_merge",           # HC: Try to merge bins
            "bp_split_large",     # MU: Split large bins
            "bp_perturbation"     # MU: Random perturbation
        ]

        llh_map = Dict{String, Function}()
        objective_fn = (sol) -> calculate_bins_used(sol, instance)

        new_bp = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "BinPacking")
        )

        # Initialize LLH map
        llh_map["bp_first_fit"] = (sol, intensity) -> llh_first_fit(new_bp, sol, intensity)
        llh_map["bp_best_fit"] = (sol, intensity) -> llh_best_fit(new_bp, sol, intensity)
        llh_map["bp_swap"] = (sol, intensity) -> llh_swap(new_bp, sol, intensity)
        llh_map["bp_repack"] = (sol, intensity) -> llh_repack(new_bp, sol, intensity)
        llh_map["bp_merge"] = (sol, intensity) -> llh_merge(new_bp, sol, intensity)
        llh_map["bp_split_large"] = (sol, intensity) -> llh_split_large(new_bp, sol, intensity)
        llh_map["bp_perturbation"] = (sol, intensity) -> llh_perturbation(new_bp, sol, intensity)

        return new_bp
    end
end

"""
    calculate_bins_used(solution::BPSolution, instance::BPInstance)::Float64

Calculate number of bins used (non-empty bins).
"""
function calculate_bins_used(solution::BPSolution, instance::BPInstance)::Float64
    if solution.is_evaluated
        return solution.objective_value
    end

    # Count non-empty bins
    n_bins = count(bin -> !isempty(bin.items), solution.bins)

    # Check feasibility: all items packed exactly once
    all_items = vcat([bin.items for bin in solution.bins]...)
    is_complete = length(all_items) == instance.n_items
    is_unique = length(unique(all_items)) == length(all_items)

    # Check capacity constraints
    all_feasible = all(bin -> bin.current_load <= instance.bin_capacity, solution.bins)

    solution.is_feasible = is_complete && is_unique && all_feasible
    solution.objective_value = Float64(n_bins)

    # Add penalty for infeasibility
    if !solution.is_feasible
        solution.objective_value += 1000.0
    end

    solution.is_evaluated = true
    return solution.objective_value
end

"""
    generate_initial_solution(domain::BinPacking)::BPSolution

Generate initial solution using First-Fit Decreasing (FFD) heuristic.
"""
function generate_initial_solution(domain::BinPacking)::BPSolution
    instance = domain.instance

    # Sort items by size (descending)
    items_sorted = sortperm(instance.item_sizes, rev=true)

    bins = Bin[]

    for item_id in items_sorted
        item_size = instance.item_sizes[item_id]

        # Try to fit in existing bin
        placed = false
        for bin in bins
            if bin.remaining_capacity >= item_size
                push!(bin.items, item_id)
                bin.current_load += item_size
                bin.remaining_capacity -= item_size
                placed = true
                break
            end
        end

        # Create new bin if needed
        if !placed
            new_bin = Bin(instance.bin_capacity)
            push!(new_bin.items, item_id)
            new_bin.current_load = item_size
            new_bin.remaining_capacity = instance.bin_capacity - item_size
            push!(bins, new_bin)
        end
    end

    return BPSolution(bins)
end

# ============================================================================
# LOW-LEVEL HEURISTICS (7 LLHs)
# ============================================================================

"""
LLH1: First-Fit Improvement
Try to repack items using first-fit to reduce bins.
"""
function llh_first_fit(domain::BinPacking, solution::BPSolution, intensity::Float64)::BPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    # Collect all items
    all_items = vcat([bin.items for bin in new_sol.bins]...)

    # Clear bins
    new_sol.bins = Bin[]

    # Repack using first-fit
    for item_id in all_items
        item_size = instance.item_sizes[item_id]

        placed = false
        for bin in new_sol.bins
            if bin.remaining_capacity >= item_size
                push!(bin.items, item_id)
                bin.current_load += item_size
                bin.remaining_capacity -= item_size
                placed = true
                break
            end
        end

        if !placed
            new_bin = Bin(instance.bin_capacity)
            push!(new_bin.items, item_id)
            new_bin.current_load = item_size
            new_bin.remaining_capacity = instance.bin_capacity - item_size
            push!(new_sol.bins, new_bin)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: Best-Fit Improvement
Try to place items in bins with tightest fit.
"""
function llh_best_fit(domain::BinPacking, solution::BPSolution, intensity::Float64)::BPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    # Collect all items
    all_items = vcat([bin.items for bin in new_sol.bins]...)

    # Sort by size (descending) for better packing
    sort!(all_items, by = id -> instance.item_sizes[id], rev=true)

    # Clear bins
    new_sol.bins = Bin[]

    # Repack using best-fit
    for item_id in all_items
        item_size = instance.item_sizes[item_id]

        best_bin = nothing
        best_remaining = typemax(Int)

        # Find bin with tightest fit
        for bin in new_sol.bins
            if bin.remaining_capacity >= item_size
                if bin.remaining_capacity < best_remaining
                    best_remaining = bin.remaining_capacity
                    best_bin = bin
                end
            end
        end

        if !isnothing(best_bin)
            push!(best_bin.items, item_id)
            best_bin.current_load += item_size
            best_bin.remaining_capacity -= item_size
        else
            # Create new bin
            new_bin = Bin(instance.bin_capacity)
            push!(new_bin.items, item_id)
            new_bin.current_load = item_size
            new_bin.remaining_capacity = instance.bin_capacity - item_size
            push!(new_sol.bins, new_bin)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH3: Swap Items Between Bins
"""
function llh_swap(domain::BinPacking, solution::BPSolution, intensity::Float64)::BPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    n_swaps = max(1, round(Int, intensity * 10))

    for _ in 1:n_swaps
        non_empty = filter(bin -> !isempty(bin.items), new_sol.bins)
        if length(non_empty) < 2
            break
        end

        bin1, bin2 = rand(non_empty, 2)
        while bin1 === bin2
            bin1, bin2 = rand(non_empty, 2)
        end

        if isempty(bin1.items) || isempty(bin2.items)
            continue
        end

        # Select random items
        item1_idx = rand(1:length(bin1.items))
        item2_idx = rand(1:length(bin2.items))

        item1 = bin1.items[item1_idx]
        item2 = bin2.items[item2_idx]

        size1 = instance.item_sizes[item1]
        size2 = instance.item_sizes[item2]

        # Check if swap is feasible
        new_load1 = bin1.current_load - size1 + size2
        new_load2 = bin2.current_load - size2 + size1

        if new_load1 <= instance.bin_capacity && new_load2 <= instance.bin_capacity
            # Perform swap
            bin1.items[item1_idx] = item2
            bin2.items[item2_idx] = item1

            bin1.current_load = new_load1
            bin1.remaining_capacity = instance.bin_capacity - new_load1

            bin2.current_load = new_load2
            bin2.remaining_capacity = instance.bin_capacity - new_load2
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH4: Repack Random Bins
Empty some bins and redistribute items.
"""
function llh_repack(domain::BinPacking, solution::BPSolution, intensity::Float64)::BPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    n_bins_to_repack = max(1, round(Int, intensity * length(new_sol.bins) * 0.3))

    non_empty = filter(bin -> !isempty(bin.items), new_sol.bins)
    if isempty(non_empty)
        return new_sol
    end

    # Select bins to repack
    bins_to_repack = rand(non_empty, min(n_bins_to_repack, length(non_empty)))

    # Collect items from selected bins
    items_to_repack = Int[]
    for bin in bins_to_repack
        append!(items_to_repack, bin.items)
        empty!(bin.items)
        bin.current_load = 0
        bin.remaining_capacity = instance.bin_capacity
    end

    # Repack items using first-fit
    for item_id in items_to_repack
        item_size = instance.item_sizes[item_id]

        placed = false
        for bin in new_sol.bins
            if bin.remaining_capacity >= item_size
                push!(bin.items, item_id)
                bin.current_load += item_size
                bin.remaining_capacity -= item_size
                placed = true
                break
            end
        end

        if !placed
            # Use a new bin
            new_bin = Bin(instance.bin_capacity)
            push!(new_bin.items, item_id)
            new_bin.current_load = item_size
            new_bin.remaining_capacity = instance.bin_capacity - item_size
            push!(new_sol.bins, new_bin)
        end
    end

    # Remove empty bins
    filter!(bin -> !isempty(bin.items), new_sol.bins)

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: Try to Merge Bins
Attempt to combine items from two bins into one.
"""
function llh_merge(domain::BinPacking, solution::BPSolution, intensity::Float64)::BPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    n_attempts = max(1, round(Int, intensity * 5))

    for _ in 1:n_attempts
        non_empty = filter(bin -> !isempty(bin.items), new_sol.bins)
        if length(non_empty) < 2
            break
        end

        # Find two bins that might merge
        bin1, bin2 = rand(non_empty, 2)
        while bin1 === bin2
            bin1, bin2 = rand(non_empty, 2)
        end

        # Check if they can merge
        combined_load = bin1.current_load + bin2.current_load

        if combined_load <= instance.bin_capacity
            # Merge bin2 into bin1
            append!(bin1.items, bin2.items)
            bin1.current_load = combined_load
            bin1.remaining_capacity = instance.bin_capacity - combined_load

            # Empty bin2
            empty!(bin2.items)
            bin2.current_load = 0
            bin2.remaining_capacity = instance.bin_capacity
        end
    end

    # Remove empty bins
    filter!(bin -> !isempty(bin.items), new_sol.bins)

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH6: Split Large Bins
Split bins with many items to potentially improve packing.
"""
function llh_split_large(domain::BinPacking, solution::BPSolution, intensity::Float64)::BPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    # Find bins with many items
    large_bins = filter(bin -> length(bin.items) >= 3, new_sol.bins)

    if isempty(large_bins)
        return new_sol
    end

    bin_to_split = rand(large_bins)

    if length(bin_to_split.items) < 3
        return new_sol
    end

    # Split into two bins
    n_items = length(bin_to_split.items)
    split_point = n_items ÷ 2

    items1 = bin_to_split.items[1:split_point]
    items2 = bin_to_split.items[split_point+1:end]

    # Create two new bins
    new_bin1 = Bin(instance.bin_capacity)
    new_bin2 = Bin(instance.bin_capacity)

    for item in items1
        push!(new_bin1.items, item)
        new_bin1.current_load += instance.item_sizes[item]
    end
    new_bin1.remaining_capacity = instance.bin_capacity - new_bin1.current_load

    for item in items2
        push!(new_bin2.items, item)
        new_bin2.current_load += instance.item_sizes[item]
    end
    new_bin2.remaining_capacity = instance.bin_capacity - new_bin2.current_load

    # Replace original bin with two new bins
    idx = findfirst(b -> b === bin_to_split, new_sol.bins)
    if !isnothing(idx)
        new_sol.bins[idx] = new_bin1
        insert!(new_sol.bins, idx+1, new_bin2)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH7: Random Perturbation
"""
function llh_perturbation(domain::BinPacking, solution::BPSolution, intensity::Float64)::BPSolution
    new_sol = deepcopy(solution)

    n_moves = max(3, round(Int, intensity * 8))

    for _ in 1:n_moves
        move_type = rand(1:3)

        if move_type == 1
            new_sol = llh_swap(domain, new_sol, 0.3)
        elseif move_type == 2
            new_sol = llh_merge(domain, new_sol, 0.5)
        else
            new_sol = llh_repack(domain, new_sol, 0.2)
        end
    end

    return new_sol
end

end # module
