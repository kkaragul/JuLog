"""
Capacitated Vehicle Routing Problem with Time Windows (CVRPTW)

Extension of CVRP adding time window constraints.
Each customer must be visited within their time window [early, late].
"""
module CVRPTWDomain

export CVRPTW, CVRPTWSolution, CVRPTWInstance

"""
    CVRPTWCustomer

Customer with time window and service time.
"""
struct CVRPTWCustomer
    id::Int
    x::Float64
    y::Float64
    demand::Float64
    ready_time::Float64      # Early time (earliest arrival)
    due_date::Float64        # Late time (latest arrival)
    service_time::Float64    # Time required to serve customer
end

"""
    CVRPTWInstance

CVRPTW problem instance.
"""
struct CVRPTWInstance
    name::String
    n_customers::Int
    n_vehicles::Int
    capacity::Float64
    customers::Vector{CVRPTWCustomer}  # Index 1 is depot
    distances::Matrix{Float64}
    travel_times::Matrix{Float64}      # Can differ from distances
end

"""
    CVRPTWRoute

Route with time window feasibility tracking.
"""
mutable struct CVRPTWRoute
    customers::Vector{Int}
    load::Float64
    total_distance::Float64
    total_time::Float64          # Total time including service
    arrival_times::Vector{Float64}  # Arrival time at each customer
    waiting_times::Vector{Float64}  # Waiting time at each customer
    is_time_feasible::Bool
end

function CVRPTWRoute()
    CVRPTWRoute(Int[], 0.0, 0.0, 0.0, Float64[], Float64[], true)
end

"""
    CVRPTWSolution

Solution for CVRPTW.
"""
mutable struct CVRPTWSolution
    routes::Vector{CVRPTWRoute}
    objective_value::Float64
    is_evaluated::Bool
    is_feasible::Bool           # Capacity AND time windows satisfied
    total_time_window_violations::Float64
end

function CVRPTWSolution(routes::Vector{CVRPTWRoute})
    CVRPTWSolution(routes, Inf, false, true, 0.0)
end

"""
    CVRPTW

CVRPTW domain structure.
"""
struct CVRPTW
    instance::CVRPTWInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function CVRPTW(instance::CVRPTWInstance)
        # 8 LLHs for CVRPTW (time-window aware)
        llh_ids = [
            "tw_swap_intra",      # MU: Time-window aware intra-route swap
            "tw_swap_inter",      # MU: Time-window aware inter-route swap
            "tw_relocate",        # MU: Time-window aware relocation
            "tw_2opt",            # HC: 2-opt with time window checking
            "tw_insert_best",     # HC: Best insertion considering time windows
            "tw_cross_exchange",  # HC: Cross-exchange between routes
            "tw_ejection_chain",  # HC: Ejection chain with time feasibility
            "tw_perturbation"     # MU: Random time-aware perturbation
        ]

        llh_map = Dict{String, Function}()
        objective_fn = (sol) -> calculate_total_objective(sol, instance)

        new_cvrptw = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "CVRPTW")
        )

        # Initialize LLH map
        llh_map["tw_swap_intra"] = (sol, intensity) -> llh_tw_swap_intra(new_cvrptw, sol, intensity)
        llh_map["tw_swap_inter"] = (sol, intensity) -> llh_tw_swap_inter(new_cvrptw, sol, intensity)
        llh_map["tw_relocate"] = (sol, intensity) -> llh_tw_relocate(new_cvrptw, sol, intensity)
        llh_map["tw_2opt"] = (sol, intensity) -> llh_tw_2opt(new_cvrptw, sol, intensity)
        llh_map["tw_insert_best"] = (sol, intensity) -> llh_tw_insert_best(new_cvrptw, sol, intensity)
        llh_map["tw_cross_exchange"] = (sol, intensity) -> llh_tw_cross_exchange(new_cvrptw, sol, intensity)
        llh_map["tw_ejection_chain"] = (sol, intensity) -> llh_tw_ejection_chain(new_cvrptw, sol, intensity)
        llh_map["tw_perturbation"] = (sol, intensity) -> llh_tw_perturbation(new_cvrptw, sol, intensity)

        return new_cvrptw
    end
end

"""
    calculate_route_times!(route::CVRPTWRoute, instance::CVRPTWInstance)

Calculate arrival times and check time window feasibility for a route.
"""
function calculate_route_times!(route::CVRPTWRoute, instance::CVRPTWInstance)
    if isempty(route.customers)
        route.is_time_feasible = true
        route.total_time = 0.0
        return
    end

    depot = instance.customers[1]
    n = length(route.customers)

    route.arrival_times = zeros(n)
    route.waiting_times = zeros(n)
    route.total_distance = 0.0
    route.total_time = 0.0

    current_time = depot.ready_time
    current_location = 1  # Depot

    violations = 0.0

    for i in 1:n
        customer_id = route.customers[i]
        customer = instance.customers[customer_id]

        # Travel to customer
        travel_time = instance.travel_times[current_location, customer_id]
        route.total_distance += instance.distances[current_location, customer_id]

        arrival_time = current_time + travel_time
        route.arrival_times[i] = arrival_time

        # Check time window
        if arrival_time < customer.ready_time
            # Arrive early, must wait
            route.waiting_times[i] = customer.ready_time - arrival_time
            current_time = customer.ready_time + customer.service_time
        elseif arrival_time > customer.due_date
            # Arrive late - time window violation
            violations += arrival_time - customer.due_date
            current_time = arrival_time + customer.service_time
            route.is_time_feasible = false
        else
            # Arrive within time window
            route.waiting_times[i] = 0.0
            current_time = arrival_time + customer.service_time
        end

        current_location = customer_id
    end

    # Return to depot
    route.total_distance += instance.distances[current_location, 1]
    route.total_time = current_time - depot.ready_time

    # Check return to depot time window
    return_time = current_time + instance.travel_times[current_location, 1]
    if return_time > depot.due_date
        violations += return_time - depot.due_date
        route.is_time_feasible = false
    end

    return violations
end

"""
    calculate_total_objective(solution::CVRPTWSolution, instance::CVRPTWInstance)::Float64

Calculate total objective: distance + penalty for time window violations.
"""
function calculate_total_objective(solution::CVRPTWSolution, instance::CVRPTWInstance)::Float64
    if solution.is_evaluated
        return solution.objective_value
    end

    total_distance = 0.0
    total_violations = 0.0
    all_feasible = true

    for route in solution.routes
        violations = calculate_route_times!(route, instance)
        total_distance += route.total_distance
        total_violations += violations

        if !route.is_time_feasible
            all_feasible = false
        end
    end

    solution.is_feasible = all_feasible
    solution.total_time_window_violations = total_violations

    # Objective: distance + large penalty for time window violations
    penalty_weight = 10000.0
    solution.objective_value = total_distance + penalty_weight * total_violations
    solution.is_evaluated = true

    return solution.objective_value
end

"""
    check_feasibility(solution::CVRPTWSolution, instance::CVRPTWInstance)::Bool

Check if solution satisfies capacity and time window constraints.
"""
function check_feasibility(solution::CVRPTWSolution, instance::CVRPTWInstance)::Bool
    for route in solution.routes
        # Check capacity
        if route.load > instance.capacity
            return false
        end

        # Check time windows
        if !route.is_time_feasible
            return false
        end
    end
    return true
end

"""
    generate_initial_solution(domain::CVRPTW)::CVRPTWSolution

Generate initial solution using time-window aware nearest neighbor.
"""
function generate_initial_solution(domain::CVRPTW)::CVRPTWSolution
    instance = domain.instance
    depot = instance.customers[1]

    unrouted = Set(2:instance.n_customers+1)
    routes = CVRPTWRoute[]

    while !isempty(unrouted)
        route = CVRPTWRoute()
        route.customers = Int[]
        route.load = 0.0

        current_location = 1
        current_time = depot.ready_time

        while true
            best_customer = nothing
            best_cost = Inf

            for customer_id in unrouted
                customer = instance.customers[customer_id]

                # Check capacity
                if route.load + customer.demand > instance.capacity
                    continue
                end

                # Calculate arrival time
                travel_time = instance.travel_times[current_location, customer_id]
                arrival_time = current_time + travel_time

                # Check time window
                if arrival_time > customer.due_date
                    continue
                end

                # Adjust for waiting
                service_start = max(arrival_time, customer.ready_time)

                # Cost: distance + urgency (favor customers with tight windows)
                distance = instance.distances[current_location, customer_id]
                urgency = 1.0 / (customer.due_date - service_start + 1.0)
                cost = distance + urgency

                if cost < best_cost
                    best_cost = cost
                    best_customer = customer_id
                end
            end

            if isnothing(best_customer)
                break
            end

            # Add customer to route
            customer = instance.customers[best_customer]
            push!(route.customers, best_customer)
            route.load += customer.demand

            # Update time
            travel_time = instance.travel_times[current_location, best_customer]
            arrival_time = current_time + travel_time
            service_start = max(arrival_time, customer.ready_time)
            current_time = service_start + customer.service_time
            current_location = best_customer

            delete!(unrouted, best_customer)
        end

        if !isempty(route.customers)
            push!(routes, route)
        end
    end

    return CVRPTWSolution(routes)
end

# ============================================================================
# LOW-LEVEL HEURISTICS (8 LLHs) - Time Window Aware
# ============================================================================

"""
LLH1: Time-Window Aware Intra-Route Swap
"""
function llh_tw_swap_intra(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)
    n_swaps = max(1, round(Int, intensity * 5))

    for _ in 1:n_swaps
        non_empty = filter(r -> length(r.customers) >= 2, new_sol.routes)
        if isempty(non_empty)
            break
        end

        route = rand(non_empty)
        i, j = rand(1:length(route.customers), 2)

        # Try swap
        route.customers[i], route.customers[j] = route.customers[j], route.customers[i]

        # Check time feasibility
        violations = calculate_route_times!(route, domain.instance)

        # Accept if feasible or improves violations
        if violations > 100.0  # Too many violations, revert
            route.customers[i], route.customers[j] = route.customers[j], route.customers[i]
            calculate_route_times!(route, domain.instance)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: Time-Window Aware Inter-Route Swap
"""
function llh_tw_swap_inter(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)
    instance = domain.instance
    n_swaps = max(1, round(Int, intensity * 3))

    for _ in 1:n_swaps
        if length(new_sol.routes) < 2
            break
        end

        route1, route2 = rand(new_sol.routes, 2)
        while route1 === route2 || isempty(route1.customers) || isempty(route2.customers)
            route1, route2 = rand(new_sol.routes, 2)
        end

        i = rand(1:length(route1.customers))
        j = rand(1:length(route2.customers))

        cust1 = route1.customers[i]
        cust2 = route2.customers[j]

        # Check capacity feasibility
        new_load1 = route1.load - instance.customers[cust1].demand + instance.customers[cust2].demand
        new_load2 = route2.load - instance.customers[cust2].demand + instance.customers[cust1].demand

        if new_load1 <= instance.capacity && new_load2 <= instance.capacity
            # Try swap
            route1.customers[i] = cust2
            route2.customers[j] = cust1
            route1.load = new_load1
            route2.load = new_load2

            # Check time feasibility
            v1 = calculate_route_times!(route1, instance)
            v2 = calculate_route_times!(route2, instance)

            # Revert if too many violations
            if v1 + v2 > 50.0
                route1.customers[i] = cust1
                route2.customers[j] = cust2
                route1.load = route1.load - instance.customers[cust2].demand + instance.customers[cust1].demand
                route2.load = route2.load - instance.customers[cust1].demand + instance.customers[cust2].demand
                calculate_route_times!(route1, instance)
                calculate_route_times!(route2, instance)
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH3: Time-Window Aware Relocation
"""
function llh_tw_relocate(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)
    instance = domain.instance
    n_moves = max(1, round(Int, intensity * 3))

    for _ in 1:n_moves
        if length(new_sol.routes) < 2
            break
        end

        non_empty = filter(r -> !isempty(r.customers), new_sol.routes)
        if isempty(non_empty)
            break
        end

        source_route = rand(non_empty)
        target_route = rand(new_sol.routes)

        while source_route === target_route
            target_route = rand(new_sol.routes)
        end

        cust_idx = rand(1:length(source_route.customers))
        customer_id = source_route.customers[cust_idx]
        customer = instance.customers[customer_id]

        # Check capacity
        if target_route.load + customer.demand <= instance.capacity
            # Remove from source
            deleteat!(source_route.customers, cust_idx)
            source_route.load -= customer.demand

            # Add to target
            push!(target_route.customers, customer_id)
            target_route.load += customer.demand

            # Check time feasibility
            v_source = calculate_route_times!(source_route, instance)
            v_target = calculate_route_times!(target_route, instance)

            # Revert if creates too many violations
            if v_target > 30.0
                deleteat!(target_route.customers, length(target_route.customers))
                target_route.load -= customer.demand
                insert!(source_route.customers, cust_idx, customer_id)
                source_route.load += customer.demand
                calculate_route_times!(source_route, instance)
                calculate_route_times!(target_route, instance)
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH4: 2-opt with Time Window Checking
"""
function llh_tw_2opt(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    for route in new_sol.routes
        if length(route.customers) < 4
            continue
        end

        improved = true
        max_iter = max(1, round(Int, intensity * 10))

        for _ in 1:max_iter
            if !improved
                break
            end
            improved = false

            for i in 1:length(route.customers)-1
                for j in i+2:length(route.customers)
                    # Current distance
                    current_dist = route.total_distance

                    # Try 2-opt
                    reverse!(route.customers, i+1, j)

                    violations = calculate_route_times!(route, instance)

                    # Accept if improves and feasible
                    if route.total_distance < current_dist && violations < 1.0
                        improved = true
                    else
                        # Revert
                        reverse!(route.customers, i+1, j)
                        calculate_route_times!(route, instance)
                    end
                end
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: Best Insertion (Time-Window Aware)
"""
function llh_tw_insert_best(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    # Remove random customers and reinsert at best positions
    n_relocations = max(1, round(Int, intensity * 3))

    for _ in 1:n_relocations
        non_empty = filter(r -> !isempty(r.customers), new_sol.routes)
        if isempty(non_empty)
            break
        end

        route = rand(non_empty)
        if isempty(route.customers)
            continue
        end

        # Remove random customer
        cust_idx = rand(1:length(route.customers))
        customer_id = splice!(route.customers, cust_idx)
        customer = instance.customers[customer_id]
        route.load -= customer.demand

        # Find best insertion position across all routes
        best_route = nothing
        best_position = 0
        best_cost = Inf

        for try_route in new_sol.routes
            if try_route.load + customer.demand > instance.capacity
                continue
            end

            for pos in 0:length(try_route.customers)
                # Try insertion
                insert!(try_route.customers, pos+1, customer_id)
                try_route.load += customer.demand

                violations = calculate_route_times!(try_route, instance)
                cost = try_route.total_distance + 1000.0 * violations

                if cost < best_cost
                    best_cost = cost
                    best_route = try_route
                    best_position = pos+1
                end

                # Remove for next try
                deleteat!(try_route.customers, pos+1)
                try_route.load -= customer.demand
            end
        end

        # Insert at best position
        if !isnothing(best_route)
            insert!(best_route.customers, best_position, customer_id)
            best_route.load += customer.demand
            calculate_route_times!(best_route, instance)
        else
            # Reinsert at original position if no feasible insertion found
            insert!(route.customers, cust_idx, customer_id)
            route.load += customer.demand
        end

        calculate_route_times!(route, instance)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH6: Cross-Exchange between Routes
"""
function llh_tw_cross_exchange(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    if length(new_sol.routes) < 2
        return new_sol
    end

    route1, route2 = rand(new_sol.routes, 2)
    while route1 === route2 || isempty(route1.customers) || isempty(route2.customers)
        route1, route2 = rand(new_sol.routes, 2)
    end

    # Exchange segments
    if length(route1.customers) >= 2 && length(route2.customers) >= 2
        seg_len = max(1, round(Int, intensity * 3))

        i = rand(1:max(1, length(route1.customers) - seg_len + 1))
        j = rand(1:max(1, length(route2.customers) - seg_len + 1))

        # Store original
        orig1 = copy(route1.customers)
        orig2 = copy(route2.customers)

        # Exchange segments
        seg1 = route1.customers[i:min(i+seg_len-1, length(route1.customers))]
        seg2 = route2.customers[j:min(j+seg_len-1, length(route2.customers))]

        splice!(route1.customers, i:i+length(seg1)-1, seg2)
        splice!(route2.customers, j:j+length(seg2)-1, seg1)

        # Recalculate loads
        route1.load = sum(instance.customers[c].demand for c in route1.customers)
        route2.load = sum(instance.customers[c].demand for c in route2.customers)

        # Check feasibility
        v1 = calculate_route_times!(route1, instance)
        v2 = calculate_route_times!(route2, instance)

        if route1.load > instance.capacity || route2.load > instance.capacity || v1 + v2 > 50.0
            # Revert
            route1.customers = orig1
            route2.customers = orig2
            route1.load = sum(instance.customers[c].demand for c in route1.customers)
            route2.load = sum(instance.customers[c].demand for c in route2.customers)
            calculate_route_times!(route1, instance)
            calculate_route_times!(route2, instance)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH7: Ejection Chain with Time Feasibility
"""
function llh_tw_ejection_chain(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)

    chain_length = max(2, round(Int, intensity * 4))

    for _ in 1:chain_length
        new_sol = llh_tw_relocate(domain, new_sol, 0.5)
    end

    return new_sol
end

"""
LLH8: Time-Aware Perturbation
"""
function llh_tw_perturbation(domain::CVRPTW, solution::CVRPTWSolution, intensity::Float64)::CVRPTWSolution
    new_sol = deepcopy(solution)

    n_moves = max(3, round(Int, intensity * 8))

    for _ in 1:n_moves
        move_type = rand(1:3)

        if move_type == 1
            new_sol = llh_tw_swap_intra(domain, new_sol, 0.3)
        elseif move_type == 2
            new_sol = llh_tw_swap_inter(domain, new_sol, 0.3)
        else
            new_sol = llh_tw_relocate(domain, new_sol, 0.3)
        end
    end

    return new_sol
end

end # module
