"""
CO2-Emission Vehicle Routing Problem (CO2VRP) / Pollution Routing Problem (PRP)

Minimizes CO2 emissions by considering speed-dependent fuel consumption,
load effects, and potential green zones with emission penalties.
"""
module CO2VRPDomain

export CO2VRP, CO2VRPSolution, CO2VRPInstance

"""
    GreenZone

Area with emission restrictions or penalties.
"""
struct GreenZone
    center_x::Float64
    center_y::Float64
    radius::Float64
    penalty_factor::Float64  # Multiplier for emissions in this zone
end

"""
    CO2VRPInstance

CO2VRP problem instance with emission parameters.
"""
struct CO2VRPInstance
    name::String
    n_customers::Int
    n_vehicles::Int
    capacity::Float64
    coordinates::Matrix{Float64}  # (n+1) × 2, row 1 is depot
    demands::Vector{Float64}
    distances::Matrix{Float64}

    # Emission parameters
    fuel_rate::Float64           # Base fuel consumption (L/km)
    load_factor::Float64         # Additional fuel per kg load per km
    speed::Float64               # Average speed (km/h)
    emission_factor::Float64     # CO2 per liter of fuel (kg CO2/L)
    green_zones::Vector{GreenZone}
end

"""
    CO2VRPRoute

Route with emission tracking.
"""
mutable struct CO2VRPRoute
    customers::Vector{Int}
    load::Float64
    total_distance::Float64
    total_fuel_consumption::Float64
    total_emissions::Float64        # kg CO2
    green_zone_emissions::Float64   # Emissions in green zones
end

function CO2VRPRoute()
    CO2VRPRoute(Int[], 0.0, 0.0, 0.0, 0.0, 0.0)
end

"""
    CO2VRPSolution

Solution for CO2VRP.
"""
mutable struct CO2VRPSolution
    routes::Vector{CO2VRPRoute}
    objective_value::Float64
    is_evaluated::Bool
    is_feasible::Bool
    total_emissions::Float64
    total_distance::Float64
end

function CO2VRPSolution(routes::Vector{CO2VRPRoute})
    CO2VRPSolution(routes, Inf, false, true, 0.0, 0.0)
end

"""
    CO2VRP

CO2VRP domain structure.
"""
struct CO2VRP
    instance::CO2VRPInstance
    llh_ids::Vector{String}
    llh_map::Dict{String, Function}
    objective::Function
    properties::Dict{Symbol, Any}

    function CO2VRP(instance::CO2VRPInstance)
        # 6 LLHs for CO2VRP (emission-aware)
        llh_ids = [
            "eco_swap",           # MU: Emission-aware swap
            "eco_relocate",       # MU: Emission-aware relocation
            "eco_2opt",           # HC: 2-opt minimizing emissions
            "eco_merge_split",    # RR: Merge-split with emission optimization
            "green_zone_avoid",   # HC: Avoid/minimize green zone traversal
            "eco_perturbation"    # MU: Emission-aware perturbation
        ]

        llh_map = Dict{String, Function}()
        objective_fn = (sol) -> calculate_total_emissions(sol, instance)

        new_co2vrp = new(
            instance,
            llh_ids,
            llh_map,
            objective_fn,
            Dict(:minimization => true, :domain => "CO2VRP")
        )

        # Initialize LLH map
        llh_map["eco_swap"] = (sol, intensity) -> llh_eco_swap(new_co2vrp, sol, intensity)
        llh_map["eco_relocate"] = (sol, intensity) -> llh_eco_relocate(new_co2vrp, sol, intensity)
        llh_map["eco_2opt"] = (sol, intensity) -> llh_eco_2opt(new_co2vrp, sol, intensity)
        llh_map["eco_merge_split"] = (sol, intensity) -> llh_eco_merge_split(new_co2vrp, sol, intensity)
        llh_map["green_zone_avoid"] = (sol, intensity) -> llh_green_zone_avoid(new_co2vrp, sol, intensity)
        llh_map["eco_perturbation"] = (sol, intensity) -> llh_eco_perturbation(new_co2vrp, sol, intensity)

        return new_co2vrp
    end
end

"""
    is_in_green_zone(x::Float64, y::Float64, zone::GreenZone)::Bool

Check if a point is within a green zone.
"""
function is_in_green_zone(x::Float64, y::Float64, zone::GreenZone)::Bool
    distance = sqrt((x - zone.center_x)^2 + (y - zone.center_y)^2)
    return distance <= zone.radius
end

"""
    calculate_segment_emissions(
        from_id::Int,
        to_id::Int,
        load::Float64,
        instance::CO2VRPInstance
    )::Tuple{Float64, Float64}

Calculate fuel consumption and emissions for a route segment.
Returns (fuel_consumed, emissions)
"""
function calculate_segment_emissions(
    from_id::Int,
    to_id::Int,
    load::Float64,
    instance::CO2VRPInstance
)::Tuple{Float64, Float64}

    distance = instance.distances[from_id, to_id]

    # Fuel consumption: base rate + load effect
    fuel = (instance.fuel_rate + instance.load_factor * load) * distance

    # Emissions
    emissions = fuel * instance.emission_factor

    # Check if segment passes through green zone
    from_coords = instance.coordinates[from_id, :]
    to_coords = instance.coordinates[to_id, :]

    green_zone_factor = 1.0
    for zone in instance.green_zones
        # Simple check: if either endpoint is in zone, apply penalty
        if is_in_green_zone(from_coords[1], from_coords[2], zone) ||
           is_in_green_zone(to_coords[1], to_coords[2], zone)
            green_zone_factor = max(green_zone_factor, zone.penalty_factor)
        end
    end

    emissions *= green_zone_factor

    return (fuel, emissions)
end

"""
    calculate_route_emissions!(route::CO2VRPRoute, instance::CO2VRPInstance)

Calculate emissions for a route.
"""
function calculate_route_emissions!(route::CO2VRPRoute, instance::CO2VRPInstance)
    if isempty(route.customers)
        route.total_distance = 0.0
        route.total_fuel_consumption = 0.0
        route.total_emissions = 0.0
        route.green_zone_emissions = 0.0
        return
    end

    depot = 1
    route.total_distance = 0.0
    route.total_fuel_consumption = 0.0
    route.total_emissions = 0.0
    route.green_zone_emissions = 0.0

    current_location = depot
    current_load = route.load

    # Depot to first customer
    fuel, emissions = calculate_segment_emissions(depot, route.customers[1], current_load, instance)
    route.total_distance += instance.distances[depot, route.customers[1]]
    route.total_fuel_consumption += fuel
    route.total_emissions += emissions

    # Between customers (load decreases as we serve)
    for i in 1:length(route.customers)-1
        from = route.customers[i]
        to = route.customers[i+1]

        # Update load after serving current customer
        current_load -= instance.demands[from]

        fuel, emissions = calculate_segment_emissions(from, to, current_load, instance)
        route.total_distance += instance.distances[from, to]
        route.total_fuel_consumption += fuel
        route.total_emissions += emissions
    end

    # Last customer back to depot
    current_load -= instance.demands[route.customers[end]]
    fuel, emissions = calculate_segment_emissions(route.customers[end], depot, current_load, instance)
    route.total_distance += instance.distances[route.customers[end], depot]
    route.total_fuel_consumption += fuel
    route.total_emissions += emissions
end

"""
    calculate_total_emissions(solution::CO2VRPSolution, instance::CO2VRPInstance)::Float64

Calculate total emissions for solution.
"""
function calculate_total_emissions(solution::CO2VRPSolution, instance::CO2VRPInstance)::Float64
    if solution.is_evaluated
        return solution.objective_value
    end

    total_emissions = 0.0
    total_distance = 0.0
    all_feasible = true

    for route in solution.routes
        calculate_route_emissions!(route, instance)
        total_emissions += route.total_emissions
        total_distance += route.total_distance

        if route.load > instance.capacity
            all_feasible = false
        end
    end

    solution.is_feasible = all_feasible
    solution.total_emissions = total_emissions
    solution.total_distance = total_distance

    # Objective: total emissions (kg CO2)
    # Add penalty for capacity violations
    if !all_feasible
        penalty = 100000.0
        solution.objective_value = total_emissions + penalty
    else
        solution.objective_value = total_emissions
    end

    solution.is_evaluated = true
    return solution.objective_value
end

"""
    generate_initial_solution(domain::CO2VRP)::CO2VRPSolution

Generate initial solution favoring low-emission routes.
"""
function generate_initial_solution(domain::CO2VRP)::CO2VRPSolution
    instance = domain.instance

    # Nearest neighbor with emission consideration
    unrouted = Set(2:instance.n_customers+1)
    routes = CO2VRPRoute[]

    while !isempty(unrouted)
        route = CO2VRPRoute()
        route.customers = Int[]
        route.load = 0.0

        current_location = 1

        while true
            best_customer = nothing
            best_cost = Inf

            for customer_id in unrouted
                # Check capacity
                if route.load + instance.demands[customer_id] > instance.capacity
                    continue
                end

                # Calculate emission cost
                fuel, emissions = calculate_segment_emissions(
                    current_location,
                    customer_id,
                    route.load,
                    instance
                )

                if emissions < best_cost
                    best_cost = emissions
                    best_customer = customer_id
                end
            end

            if isnothing(best_customer)
                break
            end

            push!(route.customers, best_customer)
            route.load += instance.demands[best_customer]
            current_location = best_customer
            delete!(unrouted, best_customer)
        end

        if !isempty(route.customers)
            calculate_route_emissions!(route, instance)
            push!(routes, route)
        end
    end

    return CO2VRPSolution(routes)
end

# ============================================================================
# LOW-LEVEL HEURISTICS (6 LLHs) - Emission Aware
# ============================================================================

"""
LLH1: Emission-Aware Swap
"""
function llh_eco_swap(domain::CO2VRP, solution::CO2VRPSolution, intensity::Float64)::CO2VRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance
    n_swaps = max(1, round(Int, intensity * 5))

    for _ in 1:n_swaps
        non_empty = filter(r -> length(r.customers) >= 2, new_sol.routes)
        if isempty(non_empty)
            break
        end

        route = rand(non_empty)
        i, j = rand(1:length(route.customers), 2)

        current_emissions = route.total_emissions

        # Try swap
        route.customers[i], route.customers[j] = route.customers[j], route.customers[i]
        calculate_route_emissions!(route, instance)

        # Revert if emissions increase significantly
        if route.total_emissions > current_emissions * 1.1
            route.customers[i], route.customers[j] = route.customers[j], route.customers[i]
            calculate_route_emissions!(route, instance)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH2: Emission-Aware Relocation
"""
function llh_eco_relocate(domain::CO2VRP, solution::CO2VRPSolution, intensity::Float64)::CO2VRPSolution
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

        if isempty(source_route.customers)
            continue
        end

        cust_idx = rand(1:length(source_route.customers))
        customer_id = source_route.customers[cust_idx]

        # Check capacity
        if target_route.load + instance.demands[customer_id] <= instance.capacity
            orig_source_emissions = source_route.total_emissions
            orig_target_emissions = target_route.total_emissions

            # Move customer
            deleteat!(source_route.customers, cust_idx)
            source_route.load -= instance.demands[customer_id]
            push!(target_route.customers, customer_id)
            target_route.load += instance.demands[customer_id]

            calculate_route_emissions!(source_route, instance)
            calculate_route_emissions!(target_route, instance)

            # Revert if total emissions increase
            new_total = source_route.total_emissions + target_route.total_emissions
            old_total = orig_source_emissions + orig_target_emissions

            if new_total > old_total * 1.05
                deleteat!(target_route.customers, length(target_route.customers))
                target_route.load -= instance.demands[customer_id]
                insert!(source_route.customers, cust_idx, customer_id)
                source_route.load += instance.demands[customer_id]
                calculate_route_emissions!(source_route, instance)
                calculate_route_emissions!(target_route, instance)
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH3: 2-opt Minimizing Emissions
"""
function llh_eco_2opt(domain::CO2VRP, solution::CO2VRPSolution, intensity::Float64)::CO2VRPSolution
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
                    current_emissions = route.total_emissions

                    # Try 2-opt
                    reverse!(route.customers, i+1, j)
                    calculate_route_emissions!(route, instance)

                    if route.total_emissions < current_emissions
                        improved = true
                    else
                        # Revert
                        reverse!(route.customers, i+1, j)
                        calculate_route_emissions!(route, instance)
                    end
                end
            end
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH4: Merge-Split with Emission Optimization
"""
function llh_eco_merge_split(domain::CO2VRP, solution::CO2VRPSolution, intensity::Float64)::CO2VRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    if length(new_sol.routes) < 2
        return new_sol
    end

    route1, route2 = rand(new_sol.routes, 2)
    while route1 === route2
        route1, route2 = rand(new_sol.routes, 2)
    end

    # Merge
    merged_customers = vcat(route1.customers, route2.customers)

    # Sort by angle from depot (polar coordinate heuristic)
    depot_coords = instance.coordinates[1, :]
    angles = [atan(instance.coordinates[c, 2] - depot_coords[2],
                   instance.coordinates[c, 1] - depot_coords[1]) for c in merged_customers]

    perm = sortperm(angles)
    merged_customers = merged_customers[perm]

    # Remove old routes
    filter!(r -> r !== route1 && r !== route2, new_sol.routes)

    # Re-split based on capacity and emissions
    current_route = CO2VRPRoute()
    for customer in merged_customers
        if current_route.load + instance.demands[customer] <= instance.capacity
            push!(current_route.customers, customer)
            current_route.load += instance.demands[customer]
        else
            if !isempty(current_route.customers)
                calculate_route_emissions!(current_route, instance)
                push!(new_sol.routes, current_route)
            end
            current_route = CO2VRPRoute([customer], instance.demands[customer], 0.0, 0.0, 0.0, 0.0)
        end
    end

    if !isempty(current_route.customers)
        calculate_route_emissions!(current_route, instance)
        push!(new_sol.routes, current_route)
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH5: Green Zone Avoidance
"""
function llh_green_zone_avoid(domain::CO2VRP, solution::CO2VRPSolution, intensity::Float64)::CO2VRPSolution
    new_sol = deepcopy(solution)
    instance = domain.instance

    if isempty(instance.green_zones)
        return new_sol
    end

    # Identify customers in or near green zones
    green_customers = Int[]
    for customer_id in 2:instance.n_customers+1
        coords = instance.coordinates[customer_id, :]
        for zone in instance.green_zones
            if is_in_green_zone(coords[1], coords[2], zone)
                push!(green_customers, customer_id)
                break
            end
        end
    end

    if isempty(green_customers)
        return new_sol
    end

    # Try to consolidate green customers in same routes
    for _ in 1:max(1, round(Int, intensity * 3))
        customer = rand(green_customers)

        # Find route containing this customer
        source_route_idx = findfirst(r -> customer in r.customers, new_sol.routes)
        if isnothing(source_route_idx)
            continue
        end

        source_route = new_sol.routes[source_route_idx]

        # Find route with most green customers (excluding source)
        best_target = nothing
        max_green = 0

        for (idx, route) in enumerate(new_sol.routes)
            if idx == source_route_idx
                continue
            end

            green_count = count(c -> c in green_customers, route.customers)
            if green_count > max_green && route.load + instance.demands[customer] <= instance.capacity
                max_green = green_count
                best_target = route
            end
        end

        # Relocate to best target
        if !isnothing(best_target)
            cust_idx = findfirst(c -> c == customer, source_route.customers)
            deleteat!(source_route.customers, cust_idx)
            source_route.load -= instance.demands[customer]
            push!(best_target.customers, customer)
            best_target.load += instance.demands[customer]

            calculate_route_emissions!(source_route, instance)
            calculate_route_emissions!(best_target, instance)
        end
    end

    new_sol.is_evaluated = false
    return new_sol
end

"""
LLH6: Emission-Aware Perturbation
"""
function llh_eco_perturbation(domain::CO2VRP, solution::CO2VRPSolution, intensity::Float64)::CO2VRPSolution
    new_sol = deepcopy(solution)

    n_moves = max(3, round(Int, intensity * 8))

    for _ in 1:n_moves
        move_type = rand(1:3)

        if move_type == 1
            new_sol = llh_eco_swap(domain, new_sol, 0.3)
        elseif move_type == 2
            new_sol = llh_eco_relocate(domain, new_sol, 0.3)
        else
            new_sol = llh_eco_2opt(domain, new_sol, 0.5)
        end
    end

    return new_sol
end

end # module
