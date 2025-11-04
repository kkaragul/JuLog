"""
Traveling Salesman Problem (TSP) Domain

Implementation of TSP domain for MSHH framework.
Uses permutation-based representation.
"""
module TSPDomain

export TSP, TSPSolution, TSPInstance

"""
    TSPInstance

TSP problem instance with cities and distance matrix.
"""
struct TSPInstance
    name::String
    n_cities::Int
    coordinates::Matrix{Float64}  # n_cities × 2 (x, y)
    distances::Matrix{Float64}    # n_cities × n_cities
end

"""
    TSPSolution

Solution representation for TSP: permutation of cities.
"""
mutable struct TSPSolution
    tour::Vector{Int}           # Permutation of city indices
    objective_value::Float64    # Total tour length
    is_evaluated::Bool          # Whether objective is up-to-date
end

function TSPSolution(tour::Vector{Int})
    TSPSolution(tour, Inf, false)
end

"""
    TSP

TSP domain structure implementing the AbstractDomain interface.
"""
struct TSP
    instance::TSPInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function TSP(instance::TSPInstance)
        # Define 7 LLHs for TSP (from paper Table 1: TSP has LLHs 0-4, 7-10)
        # We'll implement: swap, 2-opt, 3-opt, insert, invert, random-restart, perturbation
        llh_ids = [
            "swap",           # MU: Swap two cities
            "2opt",           # HC: 2-opt local search
            "3opt",           # HC: 3-opt local search
            "insert",         # MU: Remove and insert city
            "invert",         # MU: Reverse segment
            "random_restart", # RR: Random permutation of segment
            "perturbation"    # MU: Multiple random swaps
        ]

        llh_map = Dict{String, Function}()

        # Create objective function
        objective_fn = (sol) -> calculate_tour_length(sol, instance)

        new_tsp = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "TSP")
        )

        # Initialize LLH map with closures over domain
        llh_map["swap"] = (sol, intensity) -> llh_swap(new_tsp, sol, intensity)
        llh_map["2opt"] = (sol, intensity) -> llh_2opt(new_tsp, sol, intensity)
        llh_map["3opt"] = (sol, intensity) -> llh_3opt(new_tsp, sol, intensity)
        llh_map["insert"] = (sol, intensity) -> llh_insert(new_tsp, sol, intensity)
        llh_map["invert"] = (sol, intensity) -> llh_invert(new_tsp, sol, intensity)
        llh_map["random_restart"] = (sol, intensity) -> llh_random_restart(new_tsp, sol, intensity)
        llh_map["perturbation"] = (sol, intensity) -> llh_perturbation(new_tsp, sol, intensity)

        return new_tsp
    end
end

"""
    calculate_tour_length(solution::TSPSolution, instance::TSPInstance)::Float64

Calculate total tour length.
"""
function calculate_tour_length(solution::TSPSolution, instance::TSPInstance)::Float64
    if solution.is_evaluated
        return solution.objective_value
    end

    total = 0.0
    n = length(solution.tour)

    for i in 1:n
        from = solution.tour[i]
        to = solution.tour[mod1(i + 1, n)]
        total += instance.distances[from, to]
    end

    solution.objective_value = total
    solution.is_evaluated = true

    return total
end

"""
    generate_initial_solution(domain::TSP)::TSPSolution

Generate initial solution using nearest neighbor heuristic.
"""
function generate_initial_solution(domain::TSP)::TSPSolution
    n = domain.instance.n_cities
    visited = falses(n)
    tour = Vector{Int}(undef, n)

    # Start from random city
    current = rand(1:n)
    tour[1] = current
    visited[current] = true

    # Nearest neighbor construction
    for i in 2:n
        best_dist = Inf
        best_city = -1

        for city in 1:n
            if !visited[city]
                dist = domain.instance.distances[current, city]
                if dist < best_dist
                    best_dist = dist
                    best_city = city
                end
            end
        end

        tour[i] = best_city
        visited[best_city] = true
        current = best_city
    end

    return TSPSolution(tour)
end

# ============================================================================
# LOW-LEVEL HEURISTICS (7 LLHs)
# ============================================================================

"""
LLH1: Swap - Swap two random cities (Mutational)
"""
function llh_swap(domain::TSP, solution::TSPSolution, intensity::Float64)::TSPSolution
    new_sol = deepcopy(solution)
    n = length(new_sol.tour)

    # Number of swaps based on intensity
    n_swaps = max(1, round(Int, intensity * n / 10))

    for _ in 1:n_swaps
        i, j = rand(1:n, 2)
        new_sol.tour[i], new_sol.tour[j] = new_sol.tour[j], new_sol.tour[i]
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: 2-opt - 2-opt local search (Hill Climbing)
"""
function llh_2opt(domain::TSP, solution::TSPSolution, intensity::Float64)::TSPSolution
    new_sol = deepcopy(solution)
    n = length(new_sol.tour)
    distances = domain.instance.distances

    improved = true
    max_iterations = max(1, round(Int, intensity * n))

    for _ in 1:max_iterations
        if !improved
            break
        end
        improved = false

        for i in 1:n-1
            for j in i+2:n
                # Calculate current edge costs
                current_cost = distances[new_sol.tour[i], new_sol.tour[i+1]] +
                              distances[new_sol.tour[j], new_sol.tour[mod1(j+1, n)]]

                # Calculate new edge costs after 2-opt
                new_cost = distances[new_sol.tour[i], new_sol.tour[j]] +
                          distances[new_sol.tour[i+1], new_sol.tour[mod1(j+1, n)]]

                if new_cost < current_cost
                    # Perform 2-opt move: reverse segment [i+1, j]
                    reverse!(new_sol.tour, i+1, j)
                    improved = true
                    new_sol.is_evaluated = false
                end
            end
        end
    end

    return new_sol
end

"""
LLH3: 3-opt - 3-opt local search (Hill Climbing)
"""
function llh_3opt(domain::TSP, solution::TSPSolution, intensity::Float64)::TSPSolution
    new_sol = deepcopy(solution)
    n = length(new_sol.tour)
    distances = domain.instance.distances

    max_iterations = max(1, round(Int, intensity * min(10, n)))
    improved = true

    for _ in 1:max_iterations
        if !improved
            break
        end
        improved = false

        # Simplified 3-opt: try reconnecting 3 edges
        for i in 1:n-4
            for j in i+2:n-2
                for k in j+2:n
                    # Try one 3-opt reconnection
                    current_length = calculate_tour_length(new_sol, domain.instance)

                    # Create alternative tour
                    alt_tour = vcat(
                        new_sol.tour[1:i],
                        reverse(new_sol.tour[i+1:j]),
                        reverse(new_sol.tour[j+1:k]),
                        new_sol.tour[k+1:end]
                    )

                    alt_sol = TSPSolution(alt_tour)
                    alt_length = calculate_tour_length(alt_sol, domain.instance)

                    if alt_length < current_length
                        new_sol = alt_sol
                        improved = true
                    end
                end
            end
        end
    end

    return new_sol
end

"""
LLH4: Insert - Remove and reinsert a city at different position (Mutational)
"""
function llh_insert(domain::TSP, solution::TSPSolution, intensity::Float64)::TSPSolution
    new_sol = deepcopy(solution)
    n = length(new_sol.tour)

    n_moves = max(1, round(Int, intensity * n / 5))

    for _ in 1:n_moves
        # Remove random city
        remove_pos = rand(1:n)
        city = splice!(new_sol.tour, remove_pos)

        # Insert at random position
        insert_pos = rand(1:length(new_sol.tour)+1)
        insert!(new_sol.tour, insert_pos, city)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: Invert - Reverse a random segment (Mutational)
"""
function llh_invert(domain::TSP, solution::TSPSolution, intensity::Float64)::TSPSolution
    new_sol = deepcopy(solution)
    n = length(new_sol.tour)

    # Segment length based on intensity
    segment_len = max(2, round(Int, intensity * n / 3))

    i = rand(1:n)
    j = min(i + segment_len, n)

    reverse!(new_sol.tour, i, j)
    new_sol.is_evaluated = false

    return new_sol
end

"""
LLH6: Random Restart - Randomize a segment (Ruin and Recreate)
"""
function llh_random_restart(domain::TSP, solution::TSPSolution, intensity::Float64)::TSPSolution
    new_sol = deepcopy(solution)
    n = length(new_sol.tour)

    # Segment to randomize based on intensity
    segment_len = max(2, round(Int, intensity * n / 2))

    start_pos = rand(1:max(1, n - segment_len + 1))
    end_pos = min(start_pos + segment_len - 1, n)

    # Shuffle the segment
    segment = new_sol.tour[start_pos:end_pos]
    new_sol.tour[start_pos:end_pos] = shuffle(segment)

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH7: Perturbation - Multiple random swaps for diversification (Mutational)
"""
function llh_perturbation(domain::TSP, solution::TSPSolution, intensity::Float64)::TSPSolution
    new_sol = deepcopy(solution)
    n = length(new_sol.tour)

    # More swaps for higher intensity
    n_swaps = max(3, round(Int, intensity * n / 4))

    for _ in 1:n_swaps
        i, j = rand(1:n, 2)
        new_sol.tour[i], new_sol.tour[j] = new_sol.tour[j], new_sol.tour[i]
    end

    new_sol.is_evaluated = false
    return new_sol
end

end # module
