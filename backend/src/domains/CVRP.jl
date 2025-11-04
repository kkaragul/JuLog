"""
Capacitated Vehicle Routing Problem (CVRP) Domain

Implementation of CVRP domain for MSHH framework.
Multiple routes with capacity constraints.
"""
module CVRPDomain

export CVRP, CVRPSolution, CVRPInstance

"""
    CVRPInstance

CVRP problem instance.
"""
struct CVRPInstance
    name::String
    n_customers::Int              # Number of customers (excluding depot)
    n_vehicles::Int               # Number of vehicles
    capacity::Float64             # Vehicle capacity
    coordinates::Matrix{Float64}  # (n_customers + 1) × 2, row 1 is depot
    demands::Vector{Float64}      # Customer demands (depot = 0)
    distances::Matrix{Float64}    # Distance matrix
end

"""
    CVRPRoute

Single route in CVRP solution.
"""
mutable struct CVRPRoute
    customers::Vector{Int}  # Customer sequence (not including depot)
    load::Float64          # Total load on this route
end

function CVRPRoute()
    CVRPRoute(Int[], 0.0)
end

"""
    CVRPSolution

Solution representation for CVRP: set of routes.
"""
mutable struct CVRPSolution
    routes::Vector{CVRPRoute}
    objective_value::Float64  # Total distance
    is_evaluated::Bool
    is_feasible::Bool        # Capacity constraints satisfied
end

function CVRPSolution(routes::Vector{CVRPRoute})
    CVRPSolution(routes, Inf, false, true)
end

"""
    CVRP

CVRP domain structure.
"""
struct CVRP
    instance::CVRPInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function CVRP(instance::CVRPInstance)
        # Define 8 LLHs for CVRP
        llh_ids = [
            "swap_intra",     # MU: Swap within route
            "swap_inter",     # MU: Swap between routes
            "relocate",       # MU: Move customer to different route
            "2opt_intra",     # HC: 2-opt within route
            "2opt_inter",     # HC: 2-opt between routes
            "merge_split",    # RR: Merge routes then re-split
            "ejection_chain", # HC: Chain of relocations
            "perturbation"    # MU: Random perturbation
        ]

        llh_map = Dict{String, Function}()
        objective_fn = (sol) -> calculate_total_distance(sol, instance)

        new_cvrp = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "CVRP")
        )

        # Initialize LLH map
        llh_map["swap_intra"] = (sol, intensity) -> llh_swap_intra(new_cvrp, sol, intensity)
        llh_map["swap_inter"] = (sol, intensity) -> llh_swap_inter(new_cvrp, sol, intensity)
        llh_map["relocate"] = (sol, intensity) -> llh_relocate(new_cvrp, sol, intensity)
        llh_map["2opt_intra"] = (sol, intensity) -> llh_2opt_intra(new_cvrp, sol, intensity)
        llh_map["2opt_inter"] = (sol, intensity) -> llh_2opt_inter(new_cvrp, sol, intensity)
        llh_map["merge_split"] = (sol, intensity) -> llh_merge_split(new_cvrp, sol, intensity)
        llh_map["ejection_chain"] = (sol, intensity) -> llh_ejection_chain(new_cvrp, sol, intensity)
        llh_map["perturbation"] = (sol, intensity) -> llh_perturbation(new_cvrp, sol, intensity)

        return new_cvrp
    end
end

"""
    calculate_total_distance(solution::CVRPSolution, instance::CVRPInstance)::Float64

Calculate total distance of all routes.
"""
function calculate_total_distance(solution::CVRPSolution, instance::CVRPInstance)::Float64
    if solution.is_evaluated
        return solution.objective_value
    end

    total = 0.0
    depot = 1  # Depot is node 1

    for route in solution.routes
        if isempty(route.customers)
            continue
        end

        # Depot to first customer
        total += instance.distances[depot, route.customers[1]]

        # Between customers
        for i in 1:length(route.customers)-1
            total += instance.distances[route.customers[i], route.customers[i+1]]
        end

        # Last customer back to depot
        total += instance.distances[route.customers[end], depot]
    end

    solution.objective_value = total
    solution.is_evaluated = true

    return total
end

"""
    check_feasibility(solution::CVRPSolution, instance::CVRPInstance)::Bool

Check if solution satisfies capacity constraints.
"""
function check_feasibility(solution::CVRPSolution, instance::CVRPInstance)::Bool
    for route in solution.routes
        if route.load > instance.capacity
            return false
        end
    end
    return true
end

"""
    calculate_route_load(customers::Vector{Int}, instance::CVRPInstance)::Float64

Calculate total load for a route.
"""
function calculate_route_load(customers::Vector{Int}, instance::CVRPInstance)::Float64
    return sum(instance.demands[c] for c in customers)
end

"""
    generate_initial_solution(domain::CVRP)::CVRPSolution

Generate initial solution using Clarke-Wright savings heuristic.
"""
function generate_initial_solution(domain::CVRP)::CVRPSolution
    instance = domain.instance
    n = instance.n_customers
    depot = 1

    # Start with each customer in separate route
    routes = CVRPRoute[]

    for customer in 2:n+1  # Skip depot (index 1)
        route = CVRPRoute([customer], instance.demands[customer])
        push!(routes, route)
    end

    # Calculate savings
    savings = []
    for i in 2:n+1
        for j in i+1:n+1
            saving = instance.distances[depot, i] + instance.distances[depot, j] -
                    instance.distances[i, j]
            push!(savings, (saving, i, j))
        end
    end

    # Sort by savings (descending)
    sort!(savings, by=x -> -x[1])

    # Merge routes based on savings
    for (_, i, j) in savings
        # Find routes containing i and j
        route_i_idx = findfirst(r -> i in r.customers, routes)
        route_j_idx = findfirst(r -> j in r.customers, routes)

        if isnothing(route_i_idx) || isnothing(route_j_idx) || route_i_idx == route_j_idx
            continue
        end

        route_i = routes[route_i_idx]
        route_j = routes[route_j_idx]

        # Check if merging is feasible
        if route_i.load + route_j.load <= instance.capacity
            # Merge routes
            append!(route_i.customers, route_j.customers)
            route_i.load += route_j.load

            # Remove route j
            deleteat!(routes, route_j_idx)
        end
    end

    return CVRPSolution(routes)
end

# ============================================================================
# LOW-LEVEL HEURISTICS (8 LLHs)
# ============================================================================

"""
LLH1: Swap Intra-route - Swap two customers within same route
"""
function llh_swap_intra(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)
    n_swaps = max(1, round(Int, intensity * 5))

    for _ in 1:n_swaps
        # Select random non-empty route
        non_empty = filter(r -> length(r.customers) >= 2, new_sol.routes)
        if isempty(non_empty)
            break
        end

        route = rand(non_empty)
        i, j = rand(1:length(route.customers), 2)
        route.customers[i], route.customers[j] = route.customers[j], route.customers[i]
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: Swap Inter-route - Swap customers between different routes
"""
function llh_swap_inter(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance
    n_swaps = max(1, round(Int, intensity * 5))

    for _ in 1:n_swaps
        if length(new_sol.routes) < 2
            break
        end

        # Select two different routes
        route1, route2 = rand(new_sol.routes, 2)
        while route1 === route2 || isempty(route1.customers) || isempty(route2.customers)
            route1, route2 = rand(new_sol.routes, 2)
        end

        # Select customers to swap
        i = rand(1:length(route1.customers))
        j = rand(1:length(route2.customers))

        cust1 = route1.customers[i]
        cust2 = route2.customers[j]

        # Check feasibility
        new_load1 = route1.load - instance.demands[cust1] + instance.demands[cust2]
        new_load2 = route2.load - instance.demands[cust2] + instance.demands[cust1]

        if new_load1 <= instance.capacity && new_load2 <= instance.capacity
            route1.customers[i] = cust2
            route2.customers[j] = cust1
            route1.load = new_load1
            route2.load = new_load2
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH3: Relocate - Move customer from one route to another
"""
function llh_relocate(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance
    n_moves = max(1, round(Int, intensity * 3))

    for _ in 1:n_moves
        if length(new_sol.routes) < 2
            break
        end

        # Select source route
        non_empty = filter(r -> !isempty(r.customers), new_sol.routes)
        if isempty(non_empty)
            break
        end

        source_route = rand(non_empty)
        target_route = rand(new_sol.routes)

        while source_route === target_route
            target_route = rand(new_sol.routes)
        end

        # Select customer to move
        cust_idx = rand(1:length(source_route.customers))
        customer = source_route.customers[cust_idx]

        # Check feasibility
        new_target_load = target_route.load + instance.demands[customer]

        if new_target_load <= instance.capacity
            # Move customer
            deleteat!(source_route.customers, cust_idx)
            source_route.load -= instance.demands[customer]

            push!(target_route.customers, customer)
            target_route.load += instance.demands[customer]
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH4: 2-opt Intra-route - 2-opt within a single route
"""
function llh_2opt_intra(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance
    depot = 1

    max_iterations = max(1, round(Int, intensity * 10))

    for route in new_sol.routes
        if length(route.customers) < 4
            continue
        end

        improved = true
        for _ in 1:max_iterations
            if !improved
                break
            end
            improved = false

            for i in 1:length(route.customers)-1
                for j in i+2:length(route.customers)
                    # Calculate current distance
                    current = instance.distances[route.customers[i], route.customers[i+1]] +
                             instance.distances[route.customers[j],
                             route.customers[mod1(j+1, length(route.customers))]]

                    # Calculate new distance
                    new_dist = instance.distances[route.customers[i], route.customers[j]] +
                              instance.distances[route.customers[i+1],
                              route.customers[mod1(j+1, length(route.customers))]]

                    if new_dist < current
                        reverse!(route.customers, i+1, j)
                        improved = true
                    end
                end
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: 2-opt Inter-route - 2-opt between two routes
"""
function llh_2opt_inter(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    if length(new_sol.routes) < 2
        return new_sol
    end

    # Try swapping tails between routes
    route1, route2 = rand(new_sol.routes, 2)
    while route1 === route2 || isempty(route1.customers) || isempty(route2.customers)
        route1, route2 = rand(new_sol.routes, 2)
    end

    i = rand(1:length(route1.customers))
    j = rand(1:length(route2.customers))

    # Calculate new loads
    tail1 = route1.customers[i:end]
    tail2 = route2.customers[j:end]

    load1_head = sum(instance.demands[c] for c in route1.customers[1:i-1]; init=0.0)
    load2_head = sum(instance.demands[c] for c in route2.customers[1:j-1]; init=0.0)
    load1_tail = sum(instance.demands[c] for c in tail1)
    load2_tail = sum(instance.demands[c] for c in tail2)

    new_load1 = load1_head + load2_tail
    new_load2 = load2_head + load1_tail

    if new_load1 <= instance.capacity && new_load2 <= instance.capacity
        route1.customers = vcat(route1.customers[1:i-1], tail2)
        route2.customers = vcat(route2.customers[1:j-1], tail1)
        route1.load = new_load1
        route2.load = new_load2
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH6: Merge-Split - Merge routes then re-split
"""
function llh_merge_split(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    if length(new_sol.routes) < 2
        return new_sol
    end

    # Merge two routes
    route1, route2 = rand(new_sol.routes, 2)
    while route1 === route2
        route1, route2 = rand(new_sol.routes, 2)
    end

    merged_customers = vcat(route1.customers, route2.customers)
    shuffle!(merged_customers)

    # Remove old routes
    filter!(r -> r !== route1 && r !== route2, new_sol.routes)

    # Re-split into new routes
    current_route = CVRPRoute()
    for customer in merged_customers
        if current_route.load + instance.demands[customer] <= instance.capacity
            push!(current_route.customers, customer)
            current_route.load += instance.demands[customer]
        else
            if !isempty(current_route.customers)
                push!(new_sol.routes, current_route)
            end
            current_route = CVRPRoute([customer], instance.demands[customer])
        end
    end

    if !isempty(current_route.customers)
        push!(new_sol.routes, current_route)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH7: Ejection Chain - Chain of customer relocations
"""
function llh_ejection_chain(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    chain_length = max(2, round(Int, intensity * 5))

    for _ in 1:chain_length
        new_sol = llh_relocate(domain, new_sol, 0.5)
    end

    return new_sol
end

"""
LLH8: Perturbation - Random perturbation for diversification
"""
function llh_perturbation(domain::CVRP, solution::CVRPSolution, intensity::Float64)::CVRPSolution
    new_sol = deepcopy(solution)

    n_moves = max(3, round(Int, intensity * 10))

    for _ in 1:n_moves
        move_type = rand(1:3)

        if move_type == 1
            new_sol = llh_swap_intra(domain, new_sol, 0.3)
        elseif move_type == 2
            new_sol = llh_swap_inter(domain, new_sol, 0.3)
        else
            new_sol = llh_relocate(domain, new_sol, 0.3)
        end
    end

    return new_sol
end

end # module
