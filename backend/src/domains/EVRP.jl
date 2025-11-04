"""
Electric Vehicle Routing Problem (EVRP)

Extension of CVRP with electric vehicles that have limited battery capacity.
Vehicles can recharge at charging stations during routes.
"""
module EVRPDomain

export EVRP, EVRPSolution, EVRPInstance

"""
    EVRPNode

Node that can be either a customer or a charging station.
"""
mutable struct EVRPNode
    id::Int
    x::Float64
    y::Float64
    demand::Float64         # 0 for charging stations
    is_charging_station::Bool
    charging_rate::Float64  # kW for charging stations, 0 for customers
end

"""
    EVRPInstance

EVRP problem instance with charging stations.
"""
struct EVRPInstance
    name::String
    n_customers::Int
    n_charging_stations::Int
    n_vehicles::Int
    capacity::Float64              # Cargo capacity
    battery_capacity::Float64      # kWh
    energy_consumption_rate::Float64  # kWh per unit distance (base)
    load_factor::Float64           # Additional consumption per unit load
    nodes::Vector{EVRPNode}        # Depot (1), customers, then charging stations
    distances::Matrix{Float64}
end

"""
    EVRPRoute

Route with battery management.
"""
mutable struct EVRPRoute
    sequence::Vector{Int}          # Node sequence including charging stations
    customer_visits::Vector{Int}    # Only customer nodes
    load::Float64
    total_distance::Float64
    total_energy_consumed::Float64
    charging_visits::Vector{Int}    # Indices in sequence where charging occurs
    battery_levels::Vector{Float64} # Battery level after each node
    is_battery_feasible::Bool
end

function EVRPRoute()
    EVRPRoute(Int[], Int[], 0.0, 0.0, 0.0, Int[], Float64[], true)
end

"""
    EVRPSolution

Solution for EVRP.
"""
mutable struct EVRPSolution
    routes::Vector{EVRPRoute}
    objective_value::Float64
    is_evaluated::Bool
    is_feasible::Bool              # Capacity AND battery constraints
    total_battery_violations::Float64
end

function EVRPSolution(routes::Vector{EVRPRoute})
    EVRPSolution(routes, Inf, false, true, 0.0)
end

"""
    EVRP

EVRP domain structure.
"""
struct EVRP
    instance::EVRPInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function EVRP(instance::EVRPInstance)
        # 7 LLHs for EVRP
        llh_ids = [
            "ev_swap",                # MU: Swap customers
            "ev_relocate",            # MU: Relocate customer
            "ev_2opt",                # HC: 2-opt with battery check
            "ev_insert_charging",     # HC: Insert charging station optimally
            "ev_remove_charging",     # HC: Remove unnecessary charging stops
            "ev_battery_optimize",    # HC: Optimize charging stop positions
            "ev_perturbation"         # MU: Random perturbation
        ]

        llh_map = Dict{String, Function}()
        objective_fn = (sol) -> calculate_total_objective(sol, instance)

        new_evrp = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "EVRP")
        )

        # Initialize LLH map
        llh_map["ev_swap"] = (sol, intensity) -> llh_ev_swap(new_evrp, sol, intensity)
        llh_map["ev_relocate"] = (sol, intensity) -> llh_ev_relocate(new_evrp, sol, intensity)
        llh_map["ev_2opt"] = (sol, intensity) -> llh_ev_2opt(new_evrp, sol, intensity)
        llh_map["ev_insert_charging"] = (sol, intensity) -> llh_ev_insert_charging(new_evrp, sol, intensity)
        llh_map["ev_remove_charging"] = (sol, intensity) -> llh_ev_remove_charging(new_evrp, sol, intensity)
        llh_map["ev_battery_optimize"] = (sol, intensity) -> llh_ev_battery_optimize(new_evrp, sol, intensity)
        llh_map["ev_perturbation"] = (sol, intensity) -> llh_ev_perturbation(new_evrp, sol, intensity)

        return new_evrp
    end
end

"""
    calculate_energy_consumption(distance::Float64, load::Float64, instance::EVRPInstance)::Float64

Calculate energy consumption considering distance and load.
"""
function calculate_energy_consumption(distance::Float64, load::Float64, instance::EVRPInstance)::Float64
    base_consumption = instance.energy_consumption_rate * distance
    load_consumption = instance.load_factor * load * distance
    return base_consumption + load_consumption
end

"""
    calculate_route_battery!(route::EVRPRoute, instance::EVRPInstance)

Calculate battery levels throughout route and check feasibility.
"""
function calculate_route_battery!(route::EVRPRoute, instance::EVRPInstance)
    if isempty(route.sequence)
        route.is_battery_feasible = true
        route.total_energy_consumed = 0.0
        return 0.0
    end

    depot = instance.nodes[1]
    n = length(route.sequence)

    route.battery_levels = zeros(n + 1)  # +1 for return to depot
    route.battery_levels[1] = instance.battery_capacity  # Start with full battery
    route.total_distance = 0.0
    route.total_energy_consumed = 0.0

    current_location = 1  # Depot
    current_load = 0.0
    violations = 0.0

    route.charging_visits = Int[]

    for i in 1:n
        node_id = route.sequence[i]
        node = instance.nodes[node_id]

        # Calculate energy needed for this segment
        distance = instance.distances[current_location, node_id]
        route.total_distance += distance

        energy_needed = calculate_energy_consumption(distance, current_load, instance)

        # Check if we have enough battery
        if route.battery_levels[i] < energy_needed
            violations += (energy_needed - route.battery_levels[i])
            route.is_battery_feasible = false
        end

        # Consume energy
        route.battery_levels[i+1] = max(0.0, route.battery_levels[i] - energy_needed)
        route.total_energy_consumed += energy_needed

        # If this is a charging station, recharge
        if node.is_charging_station
            route.battery_levels[i+1] = instance.battery_capacity
            push!(route.charging_visits, i)
        else
            # Update load for customer
            current_load += node.demand
        end

        current_location = node_id
    end

    # Return to depot
    distance = instance.distances[current_location, 1]
    route.total_distance += distance
    energy_needed = calculate_energy_consumption(distance, current_load, instance)

    if route.battery_levels[n+1] < energy_needed
        violations += (energy_needed - route.battery_levels[n+1])
        route.is_battery_feasible = false
    end

    return violations
end

"""
    calculate_total_objective(solution::EVRPSolution, instance::EVRPInstance)::Float64

Calculate total objective: distance + penalty for battery violations.
"""
function calculate_total_objective(solution::EVRPSolution, instance::EVRPInstance)::Float64
    if solution.is_evaluated
        return solution.objective_value
    end

    total_distance = 0.0
    total_violations = 0.0
    all_feasible = true

    for route in solution.routes
        violations = calculate_route_battery!(route, instance)
        total_distance += route.total_distance
        total_violations += violations

        # Check capacity
        if route.load > instance.capacity
            all_feasible = false
            total_violations += (route.load - instance.capacity) * 100.0
        end

        if !route.is_battery_feasible
            all_feasible = false
        end
    end

    solution.is_feasible = all_feasible
    solution.total_battery_violations = total_violations

    # Objective: distance + large penalty for violations
    penalty_weight = 10000.0
    solution.objective_value = total_distance + penalty_weight * total_violations
    solution.is_evaluated = true

    return solution.objective_value
end

"""
    generate_initial_solution(domain::EVRP)::EVRPSolution

Generate initial solution with charging stations inserted as needed.
"""
function generate_initial_solution(domain::EVRP)::EVRPSolution
    instance = domain.instance

    # Simple initial solution: nearest neighbor with charging insertion
    unrouted = Set(2:instance.n_customers+1)  # Customer nodes
    routes = EVRPRoute[]

    while !isempty(unrouted)
        route = EVRPRoute()
        route.sequence = Int[]
        route.customer_visits = Int[]
        route.load = 0.0

        current_location = 1  # Depot
        current_battery = instance.battery_capacity

        while !isempty(unrouted)
            # Find nearest feasible customer
            best_customer = nothing
            best_distance = Inf

            for customer_id in unrouted
                customer = instance.nodes[customer_id]

                # Check capacity
                if route.load + customer.demand > instance.capacity
                    continue
                end

                distance = instance.distances[current_location, customer_id]

                # Check if we can reach
                energy_needed = calculate_energy_consumption(distance, route.load, instance)

                if energy_needed <= current_battery
                    if distance < best_distance
                        best_distance = distance
                        best_customer = customer_id
                    end
                end
            end

            if isnothing(best_customer)
                # Need charging station or route is full
                # Try to insert charging station
                nearest_station = find_nearest_charging_station(current_location, instance)

                if !isnothing(nearest_station)
                    dist_to_station = instance.distances[current_location, nearest_station]
                    energy_to_station = calculate_energy_consumption(dist_to_station, route.load, instance)

                    if energy_to_station <= current_battery
                        # Go to charging station
                        push!(route.sequence, nearest_station)
                        current_location = nearest_station
                        current_battery = instance.battery_capacity
                        continue
                    end
                end

                # Cannot continue this route
                break
            end

            # Add customer to route
            customer = instance.nodes[best_customer]
            push!(route.sequence, best_customer)
            push!(route.customer_visits, best_customer)

            distance = instance.distances[current_location, best_customer]
            energy_used = calculate_energy_consumption(distance, route.load, instance)

            current_battery -= energy_used
            current_location = best_customer
            route.load += customer.demand

            delete!(unrouted, best_customer)
        end

        if !isempty(route.sequence)
            calculate_route_battery!(route, instance)
            push!(routes, route)
        end
    end

    return EVRPSolution(routes)
end

"""
    find_nearest_charging_station(from::Int, instance::EVRPInstance)::Union{Int, Nothing}

Find nearest charging station from a given node.
"""
function find_nearest_charging_station(from::Int, instance::EVRPInstance)::Union{Int, Nothing}
    nearest = nothing
    min_distance = Inf

    # Charging stations are after customers
    start_idx = instance.n_customers + 2
    end_idx = instance.n_customers + instance.n_charging_stations + 1

    for station_id in start_idx:end_idx
        distance = instance.distances[from, station_id]
        if distance < min_distance
            min_distance = distance
            nearest = station_id
        end
    end

    return nearest
end

# ============================================================================
# LOW-LEVEL HEURISTICS (7 LLHs) - Battery Aware
# ============================================================================

"""
LLH1: Swap Customers (Battery-Aware)
"""
function llh_ev_swap(domain::EVRP, solution::EVRPSolution, intensity::Float64)::EVRPSolution
    new_sol = deepcopy(solution)
    n_swaps = max(1, round(Int, intensity * 5))

    for _ in 1:n_swaps
        non_empty = filter(r -> length(r.customer_visits) >= 2, new_sol.routes)
        if isempty(non_empty)
            break
        end

        route = rand(non_empty)

        # Swap two customers in sequence
        customer_positions = findall(id -> !domain.instance.nodes[id].is_charging_station, route.sequence)

        if length(customer_positions) < 2
            continue
        end

        i, j = rand(customer_positions, 2)
        route.sequence[i], route.sequence[j] = route.sequence[j], route.sequence[i]

        # Recompute
        violations = calculate_route_battery!(route, domain.instance)

        # Revert if too many violations
        if violations > 50.0
            route.sequence[i], route.sequence[j] = route.sequence[j], route.sequence[i]
            calculate_route_battery!(route, domain.instance)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: Relocate Customer (Battery-Aware)
"""
function llh_ev_relocate(domain::EVRP, solution::EVRPSolution, intensity::Float64)::EVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance
    n_moves = max(1, round(Int, intensity * 3))

    for _ in 1:n_moves
        if length(new_sol.routes) < 2
            break
        end

        non_empty = filter(r -> !isempty(r.customer_visits), new_sol.routes)
        if isempty(non_empty)
            break
        end

        source_route = rand(non_empty)
        target_route = rand(new_sol.routes)

        while source_route === target_route
            target_route = rand(new_sol.routes)
        end

        if isempty(source_route.customer_visits)
            continue
        end

        # Remove random customer
        customer_id = rand(source_route.customer_visits)
        customer = instance.nodes[customer_id]

        # Check capacity
        if target_route.load + customer.demand > instance.capacity
            continue
        end

        # Remove from source
        filter!(id -> id != customer_id, source_route.sequence)
        filter!(id -> id != customer_id, source_route.customer_visits)
        source_route.load -= customer.demand

        # Add to target
        push!(target_route.sequence, customer_id)
        push!(target_route.customer_visits, customer_id)
        target_route.load += customer.demand

        # Check battery feasibility
        v_source = calculate_route_battery!(source_route, instance)
        v_target = calculate_route_battery!(target_route, instance)

        # Revert if infeasible
        if v_target > 30.0
            deleteat!(target_route.sequence, length(target_route.sequence))
            deleteat!(target_route.customer_visits, length(target_route.customer_visits))
            target_route.load -= customer.demand
            push!(source_route.sequence, customer_id)
            push!(source_route.customer_visits, customer_id)
            source_route.load += customer.demand
            calculate_route_battery!(source_route, instance)
            calculate_route_battery!(target_route, instance)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH3: 2-opt with Battery Check
"""
function llh_ev_2opt(domain::EVRP, solution::EVRPSolution, intensity::Float64)::EVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    for route in new_sol.routes
        if length(route.sequence) < 4
            continue
        end

        improved = true
        max_iter = max(1, round(Int, intensity * 5))

        for _ in 1:max_iter
            if !improved
                break
            end
            improved = false

            for i in 1:length(route.sequence)-1
                for j in i+2:length(route.sequence)
                    current_dist = route.total_distance

                    # Try 2-opt
                    reverse!(route.sequence, i+1, j)

                    violations = calculate_route_battery!(route, instance)

                    if route.total_distance < current_dist && violations < 1.0
                        improved = true
                    else
                        # Revert
                        reverse!(route.sequence, i+1, j)
                        calculate_route_battery!(route, instance)
                    end
                end
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH4: Insert Charging Station Optimally
"""
function llh_ev_insert_charging(domain::EVRP, solution::EVRPSolution, intensity::Float64)::EVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    for route in new_sol.routes
        if !route.is_battery_feasible
            # Try to insert charging station to fix battery violations
            best_position = 0
            best_station = 0
            best_improvement = 0.0

            for pos in 1:length(route.sequence)+1
                for station_id in (instance.n_customers+2):(instance.n_customers+instance.n_charging_stations+1)
                    # Try insertion
                    insert!(route.sequence, pos, station_id)

                    violations = calculate_route_battery!(route, instance)
                    improvement = route.total_battery_violations - violations

                    if improvement > best_improvement
                        best_improvement = improvement
                        best_position = pos
                        best_station = station_id
                    end

                    # Remove for next try
                    deleteat!(route.sequence, pos)
                end
            end

            # Insert best station
            if best_improvement > 0.0
                insert!(route.sequence, best_position, best_station)
                calculate_route_battery!(route, instance)
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: Remove Unnecessary Charging Stops
"""
function llh_ev_remove_charging(domain::EVRP, solution::EVRPSolution, intensity::Float64)::EVRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    for route in new_sol.routes
        # Remove charging stations one by one and check if still feasible
        charging_positions = findall(id -> instance.nodes[id].is_charging_station, route.sequence)

        for pos in reverse(charging_positions)
            station_id = route.sequence[pos]

            # Try removing
            deleteat!(route.sequence, pos)
            violations = calculate_route_battery!(route, instance)

            if violations > 0.0
                # Need this station, reinsert
                insert!(route.sequence, pos, station_id)
                calculate_route_battery!(route, instance)
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH6: Optimize Charging Station Positions
"""
function llh_ev_battery_optimize(domain::EVRP, solution::EVRPSolution, intensity::Float64)::EVRPSolution
    new_sol = deepcopy(solution)

    # Try inserting and removing charging stations
    new_sol = llh_ev_insert_charging(domain, new_sol, intensity * 0.7)
    new_sol = llh_ev_remove_charging(domain, new_sol, intensity * 0.3)

    return new_sol
end

"""
LLH7: Battery-Aware Perturbation
"""
function llh_ev_perturbation(domain::EVRP, solution::EVRPSolution, intensity::Float64)::EVRPSolution
    new_sol = deepcopy(solution)

    n_moves = max(3, round(Int, intensity * 6))

    for _ in 1:n_moves
        move_type = rand(1:3)

        if move_type == 1
            new_sol = llh_ev_swap(domain, new_sol, 0.3)
        elseif move_type == 2
            new_sol = llh_ev_relocate(domain, new_sol, 0.3)
        else
            new_sol = llh_ev_insert_charging(domain, new_sol, 0.5)
        end
    end

    return new_sol
end

end # module
