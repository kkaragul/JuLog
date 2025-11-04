"""
Parsers for Problem Instance Files

Supports TSPLIB and VRPLIB formats for TSP and CVRP instances.
"""
module Parsers

using ..TSPDomain
using ..CVRPDomain
using ..CVRPTWDomain
using ..EVRPDomain
using ..CO2VRPDomain
using ..BinPackingDomain
using ..JobShopDomain
using ..FlowShopDomain

export parse_tsp, parse_vrp, save_solution_tsp, save_solution_vrp
export parse_solomon, parse_evrp, parse_co2vrp, parse_bpp
export parse_jobshop, parse_flowshop
export create_sample_solomon, create_sample_evrp, create_sample_bpp
export create_sample_jobshop, create_sample_flowshop

"""
    parse_tsp(filename::String)::TSPInstance

Parse a TSPLIB format file.

Supported formats:
- EUC_2D: Euclidean distances in 2D
- EXPLICIT: Distance matrix provided
- GEO: Geographic coordinates

# Example TSPLIB format:
```
NAME: eil51
TYPE: TSP
DIMENSION: 51
EDGE_WEIGHT_TYPE: EUC_2D
NODE_COORD_SECTION
1 37 52
2 49 49
...
EOF
```
"""
function parse_tsp(filename::String)::TSPInstance
    lines = readlines(filename)

    name = ""
    dimension = 0
    edge_weight_type = ""
    coordinates = Matrix{Float64}(undef, 0, 2)

    # Parse header
    i = 1
    while i <= length(lines)
        line = strip(lines[i])

        if startswith(line, "NAME")
            name = strip(split(line, ':')[2])
        elseif startswith(line, "DIMENSION")
            dimension = parse(Int, strip(split(line, ':')[2]))
            coordinates = Matrix{Float64}(undef, dimension, 2)
        elseif startswith(line, "EDGE_WEIGHT_TYPE")
            edge_weight_type = strip(split(line, ':')[2])
        elseif startswith(line, "NODE_COORD_SECTION")
            # Parse coordinates
            for j in 1:dimension
                i += 1
                parts = split(strip(lines[i]))
                node_id = parse(Int, parts[1])
                x = parse(Float64, parts[2])
                y = parse(Float64, parts[3])
                coordinates[node_id, :] = [x, y]
            end
            break
        end
        i += 1
    end

    # Calculate distance matrix
    distances = calculate_distance_matrix(coordinates, edge_weight_type)

    return TSPInstance(name, dimension, coordinates, distances)
end

"""
    parse_vrp(filename::String)::CVRPInstance

Parse a VRPLIB format file.

# Example VRPLIB format:
```
NAME : X-n101-k25
COMMENT : Generated instance
TYPE : CVRP
DIMENSION : 101
EDGE_WEIGHT_TYPE : EUC_2D
CAPACITY : 206
NODE_COORD_SECTION
1 380 440
2 150 465
...
DEMAND_SECTION
1 0
2 17
...
DEPOT_SECTION
1
-1
EOF
```
"""
function parse_vrp(filename::String)::CVRPInstance
    lines = readlines(filename)

    name = ""
    dimension = 0
    capacity = 0.0
    edge_weight_type = "EUC_2D"
    coordinates = Matrix{Float64}(undef, 0, 2)
    demands = Float64[]

    section = ""
    i = 1

    while i <= length(lines)
        line = strip(lines[i])

        if isempty(line) || startswith(line, "EOF")
            i += 1
            continue
        end

        # Header parsing
        if startswith(line, "NAME")
            name = strip(split(line, ':')[2])
        elseif startswith(line, "DIMENSION")
            dimension = parse(Int, strip(split(line, ':')[2]))
            coordinates = Matrix{Float64}(undef, dimension, 2)
            demands = zeros(Float64, dimension)
        elseif startswith(line, "CAPACITY")
            capacity = parse(Float64, strip(split(line, ':')[2]))
        elseif startswith(line, "EDGE_WEIGHT_TYPE")
            edge_weight_type = strip(split(line, ':')[2])

        # Section headers
        elseif startswith(line, "NODE_COORD_SECTION")
            section = "COORD"
        elseif startswith(line, "DEMAND_SECTION")
            section = "DEMAND"
        elseif startswith(line, "DEPOT_SECTION")
            section = "DEPOT"

        # Data parsing
        elseif section == "COORD"
            parts = split(line)
            if length(parts) >= 3
                node_id = parse(Int, parts[1])
                x = parse(Float64, parts[2])
                y = parse(Float64, parts[3])
                coordinates[node_id, :] = [x, y]
            end

        elseif section == "DEMAND"
            parts = split(line)
            if length(parts) >= 2
                node_id = parse(Int, parts[1])
                demand = parse(Float64, parts[2])
                demands[node_id] = demand
            end

        elseif section == "DEPOT"
            if line == "-1"
                break
            end
        end

        i += 1
    end

    # Calculate distance matrix
    distances = calculate_distance_matrix(coordinates, edge_weight_type)

    # Number of vehicles (estimate: can be refined)
    n_customers = dimension - 1
    total_demand = sum(demands[2:end])
    n_vehicles = ceil(Int, total_demand / capacity)

    return CVRPInstance(
        name,
        n_customers,
        n_vehicles,
        capacity,
        coordinates,
        demands,
        distances
    )
end

"""
    calculate_distance_matrix(coords::Matrix{Float64}, type::String)::Matrix{Float64}

Calculate distance matrix from coordinates based on distance type.
"""
function calculate_distance_matrix(coords::Matrix{Float64}, dist_type::String)::Matrix{Float64}
    n = size(coords, 1)
    distances = zeros(Float64, n, n)

    for i in 1:n
        for j in i+1:n
            if dist_type == "EUC_2D"
                # Euclidean distance rounded to nearest integer (TSPLIB convention)
                dx = coords[i, 1] - coords[j, 1]
                dy = coords[i, 2] - coords[j, 2]
                dist = round(sqrt(dx^2 + dy^2))
            elseif dist_type == "CEIL_2D"
                # Ceiling of Euclidean distance
                dx = coords[i, 1] - coords[j, 1]
                dy = coords[i, 2] - coords[j, 2]
                dist = ceil(sqrt(dx^2 + dy^2))
            elseif dist_type == "GEO"
                # Geographic distance (latitude/longitude)
                dist = geographic_distance(coords[i, :], coords[j, :])
            else
                error("Unsupported distance type: $dist_type")
            end

            distances[i, j] = dist
            distances[j, i] = dist
        end
    end

    return distances
end

"""
    geographic_distance(coord1::Vector{Float64}, coord2::Vector{Float64})::Float64

Calculate geographic distance between two lat/lon coordinates.
Used in TSPLIB GEO format.
"""
function geographic_distance(coord1::Vector{Float64}, coord2::Vector{Float64})::Float64
    # TSPLIB geographic distance calculation
    RRR = 6378.388  # Earth radius in km

    lat1 = coord1[1]
    lon1 = coord1[2]
    lat2 = coord2[1]
    lon2 = coord2[2]

    # Convert to radians
    deg1 = floor(Int, lat1)
    min1 = lat1 - deg1
    lat1_rad = π * (deg1 + 5.0 * min1 / 3.0) / 180.0

    deg2 = floor(Int, lon1)
    min2 = lon1 - deg2
    lon1_rad = π * (deg2 + 5.0 * min2 / 3.0) / 180.0

    deg1 = floor(Int, lat2)
    min1 = lat2 - deg1
    lat2_rad = π * (deg1 + 5.0 * min1 / 3.0) / 180.0

    deg2 = floor(Int, lon2)
    min2 = lon2 - deg2
    lon2_rad = π * (deg2 + 5.0 * min2 / 3.0) / 180.0

    # Calculate distance
    q1 = cos(lon1_rad - lon2_rad)
    q2 = cos(lat1_rad - lat2_rad)
    q3 = cos(lat1_rad + lat2_rad)

    distance = RRR * acos(0.5 * ((1.0 + q1) * q2 - (1.0 - q1) * q3)) + 1.0

    return floor(Int, distance)
end

"""
    save_solution_tsp(filename::String, solution::TSPSolution, instance::TSPInstance)

Save TSP solution to file.
"""
function save_solution_tsp(filename::String, solution::TSPSolution, instance::TSPInstance)
    open(filename, "w") do io
        println(io, "NAME : $(instance.name)")
        println(io, "TYPE : TOUR")
        println(io, "DIMENSION : $(instance.n_cities)")
        println(io, "TOUR_LENGTH : $(solution.objective_value)")
        println(io, "TOUR_SECTION")
        for city in solution.tour
            println(io, city)
        end
        println(io, "-1")
    end
end

"""
    save_solution_vrp(filename::String, solution::CVRPSolution, instance::CVRPInstance)

Save CVRP solution to file.
"""
function save_solution_vrp(filename::String, solution::CVRPSolution, instance::CVRPInstance)
    open(filename, "w") do io
        println(io, "NAME : $(instance.name)")
        println(io, "TYPE : CVRP")
        println(io, "TOTAL_DISTANCE : $(solution.objective_value)")
        println(io, "NUM_ROUTES : $(length(solution.routes))")
        println(io, "ROUTES:")

        for (i, route) in enumerate(solution.routes)
            print(io, "Route $i: 0")  # Depot is 0 in output
            for customer in route.customers
                print(io, " -> $(customer-1)")  # Adjust index
            end
            println(io, " -> 0")
            println(io, "  Load: $(route.load) / $(instance.capacity)")
        end
    end
end

"""
    create_sample_tsp(n::Int, filename::String)

Create a sample TSP instance with random coordinates.
"""
function create_sample_tsp(n::Int, filename::String)
    open(filename, "w") do io
        println(io, "NAME : random$n")
        println(io, "TYPE : TSP")
        println(io, "DIMENSION : $n")
        println(io, "EDGE_WEIGHT_TYPE : EUC_2D")
        println(io, "NODE_COORD_SECTION")

        for i in 1:n
            x = rand(0:1000)
            y = rand(0:1000)
            println(io, "$i $x $y")
        end

        println(io, "EOF")
    end
end

"""
    create_sample_vrp(n::Int, capacity::Int, filename::String)

Create a sample CVRP instance with random coordinates and demands.
"""
function create_sample_vrp(n::Int, capacity::Int, filename::String)
    open(filename, "w") do io
        println(io, "NAME : random$n")
        println(io, "TYPE : CVRP")
        println(io, "DIMENSION : $n")
        println(io, "EDGE_WEIGHT_TYPE : EUC_2D")
        println(io, "CAPACITY : $capacity")
        println(io, "NODE_COORD_SECTION")

        # Depot
        println(io, "1 500 500")

        # Customers
        for i in 2:n
            x = rand(0:1000)
            y = rand(0:1000)
            println(io, "$i $x $y")
        end

        println(io, "DEMAND_SECTION")
        println(io, "1 0")  # Depot demand = 0

        for i in 2:n
            demand = rand(1:capacity÷5)
            println(io, "$i $demand")
        end

        println(io, "DEPOT_SECTION")
        println(io, "1")
        println(io, "-1")
        println(io, "EOF")
    end
end

"""
    parse_solomon(filename::String)::CVRPTWInstance

Parse Solomon benchmark format for CVRPTW.
"""
function parse_solomon(filename::String)::CVRPTWInstance
    lines = readlines(filename)

    name = strip(split(lines[1])[1])

    # Line 5: VEHICLE NUMBER CAPACITY
    vehicle_info = split(strip(lines[5]))
    n_vehicles = parse(Int, vehicle_info[1])
    capacity = parse(Float64, vehicle_info[2])

    # Parse customer data starting from line 10
    customers = CVRPTWCustomer[]

    for i in 10:length(lines)
        line = strip(lines[i])
        if isempty(line)
            break
        end

        parts = split(line)
        if length(parts) >= 7
            id = parse(Int, parts[1])
            x = parse(Float64, parts[2])
            y = parse(Float64, parts[3])
            demand = parse(Float64, parts[4])
            ready_time = parse(Float64, parts[5])
            due_date = parse(Float64, parts[6])
            service_time = parse(Float64, parts[7])

            push!(customers, CVRPTWCustomer(id, x, y, demand, ready_time, due_date, service_time))
        end
    end

    n_customers = length(customers) - 1

    # Calculate distance and travel time matrices
    n_nodes = length(customers)
    distances = zeros(n_nodes, n_nodes)
    travel_times = zeros(n_nodes, n_nodes)

    for i in 1:n_nodes
        for j in 1:n_nodes
            dx = customers[i].x - customers[j].x
            dy = customers[i].y - customers[j].y
            dist = sqrt(dx^2 + dy^2)
            distances[i,j] = dist
            travel_times[i,j] = dist  # Assume speed = 1
        end
    end

    return CVRPTWInstance(name, n_customers, n_vehicles, capacity, customers, distances, travel_times)
end

"""
    parse_evrp(filename::String)::EVRPInstance

Parse EVRP format (extended VRPLIB with battery info).
"""
function parse_evrp(filename::String)::EVRPInstance
    lines = readlines(filename)

    name = ""
    dimension = 0
    capacity = 0.0
    battery_capacity = 100.0  # Default
    n_charging_stations = 0
    coordinates = Matrix{Float64}(undef, 0, 2)
    demands = Float64[]

    section = ""
    i = 1

    while i <= length(lines)
        line = strip(lines[i])

        if isempty(line) || startswith(line, "EOF")
            i += 1
            continue
        end

        if startswith(line, "NAME")
            name = strip(split(line, ':')[2])
        elseif startswith(line, "DIMENSION")
            dimension = parse(Int, strip(split(line, ':')[2]))
            coordinates = zeros(dimension, 2)
            demands = zeros(dimension)
        elseif startswith(line, "CAPACITY")
            capacity = parse(Float64, strip(split(line, ':')[2]))
        elseif startswith(line, "BATTERY_CAPACITY")
            battery_capacity = parse(Float64, strip(split(line, ':')[2]))
        elseif startswith(line, "STATIONS")
            n_charging_stations = parse(Int, strip(split(line, ':')[2]))
        elseif startswith(line, "NODE_COORD_SECTION")
            section = "COORD"
        elseif startswith(line, "DEMAND_SECTION")
            section = "DEMAND"
        elseif section == "COORD"
            parts = split(line)
            if length(parts) >= 3
                node_id = parse(Int, parts[1])
                coordinates[node_id, 1] = parse(Float64, parts[2])
                coordinates[node_id, 2] = parse(Float64, parts[3])
            end
        elseif section == "DEMAND"
            parts = split(line)
            if length(parts) >= 2
                node_id = parse(Int, parts[1])
                demands[node_id] = parse(Float64, parts[2])
            end
        end

        i += 1
    end

    # Create nodes
    nodes = EVRPNode[]
    n_customers = dimension - n_charging_stations - 1

    for i in 1:dimension
        is_station = i > (n_customers + 1)
        charge_rate = is_station ? 50.0 : 0.0
        push!(nodes, EVRPNode(i, coordinates[i,1], coordinates[i,2], demands[i], is_station, charge_rate))
    end

    # Calculate distances
    distances = calculate_distance_matrix(coordinates, "EUC_2D")

    return EVRPInstance(
        name, n_customers, n_charging_stations, 5,
        capacity, battery_capacity, 0.2, 0.01,
        nodes, distances
    )
end

"""
    parse_co2vrp(filename::String)::CO2VRPInstance

Parse CO2VRP format (VRPLIB + emission parameters).
"""
function parse_co2vrp(filename::String)::CO2VRPInstance
    # Parse as standard VRP first
    vrp_instance = parse_vrp(filename)

    # Default emission parameters
    fuel_rate = 0.15  # L/km
    load_factor = 0.0001  # Additional fuel per kg per km
    speed = 50.0  # km/h
    emission_factor = 2.68  # kg CO2/L

    # Parse green zones if specified (optional extension)
    green_zones = GreenZone[]

    return CO2VRPInstance(
        vrp_instance.name,
        vrp_instance.n_customers,
        vrp_instance.n_vehicles,
        vrp_instance.capacity,
        vrp_instance.coordinates,
        vrp_instance.demands,
        vrp_instance.distances,
        fuel_rate,
        load_factor,
        speed,
        emission_factor,
        green_zones
    )
end

"""
    parse_bpp(filename::String)::BPInstance

Parse Bin Packing Problem format.
"""
function parse_bpp(filename::String)::BPInstance
    lines = readlines(filename)

    name = ""
    n_items = 0
    capacity = 0
    item_sizes = Int[]

    for line in lines
        line = strip(line)
        if isempty(line) || startswith(line, "#")
            continue
        end

        if startswith(line, "NAME")
            name = strip(split(line, ':')[2])
        elseif startswith(line, "ITEMS")
            n_items = parse(Int, strip(split(line, ':')[2]))
        elseif startswith(line, "CAPACITY")
            capacity = parse(Int, strip(split(line, ':')[2]))
        elseif startswith(line, "SIZES")
            # Next n_items lines contain sizes
            for i in 1:n_items
                idx = findfirst(isequal(line), lines)
                if !isnothing(idx) && idx < length(lines)
                    size_line = strip(lines[idx + i])
                    if !isempty(size_line)
                        push!(item_sizes, parse(Int, size_line))
                    end
                end
            end
            break
        end
    end

    if isempty(item_sizes) && n_items > 0
        # Alternative format: all sizes on one line
        for line in lines
            if occursin("SIZES", line)
                continue
            end
            parts = split(strip(line))
            if !isempty(parts) && all(c -> isnumeric(c) || c == ' ', line)
                for part in parts
                    try
                        push!(item_sizes, parse(Int, part))
                    catch
                    end
                end
            end
        end
    end

    return BPInstance(name, n_items, capacity, item_sizes)
end

"""
    create_sample_solomon(n::Int, filename::String)

Create sample Solomon (CVRPTW) instance.
"""
function create_sample_solomon(n::Int, filename::String)
    open(filename, "w") do io
        println(io, "C101_$n")
        println(io, "")
        println(io, "VEHICLE")
        println(io, "NUMBER     CAPACITY")
        println(io, " 25        200")
        println(io, "")
        println(io, "CUSTOMER")
        println(io, "CUST NO.  XCOORD.   YCOORD.    DEMAND   READY TIME  DUE DATE   SERVICE TIME")
        println(io, "")

        # Depot
        println(io, "    0       40        50          0          0       1236          0")

        # Customers
        for i in 1:n
            x = rand(0:100)
            y = rand(0:100)
            demand = rand(5:30)
            ready = rand(0:800)
            due = ready + rand(100:400)
            service = rand(5:15)
            println(io, "    $i       $x        $y        $demand        $ready       $due        $service")
        end
    end
end

"""
    create_sample_evrp(n::Int, filename::String)

Create sample EVRP instance.
"""
function create_sample_evrp(n::Int, filename::String)
    n_stations = max(2, n ÷ 10)
    create_sample_vrp(n + n_stations + 1, 100, filename)

    # Add battery and station info
    content = read(filename, String)
    open(filename, "w") do io
        # Insert before DEPOT_SECTION
        lines = split(content, '\n')
        for line in lines
            println(io, line)
            if occursin("CAPACITY", line)
                println(io, "BATTERY_CAPACITY : 100")
                println(io, "STATIONS : $n_stations")
            end
        end
    end
end

"""
    create_sample_bpp(n::Int, capacity::Int, filename::String)

Create sample Bin Packing instance.
"""
function create_sample_bpp(n::Int, capacity::Int, filename::String)
    open(filename, "w") do io
        println(io, "NAME: random_bpp_$n")
        println(io, "ITEMS: $n")
        println(io, "CAPACITY: $capacity")
        println(io, "SIZES:")

        for i in 1:n
            size = rand(1:capacity÷2)
            println(io, size)
        end
    end
end

"""
    parse_jobshop(filename::String)::JobShopInstance

Parse Job Shop Scheduling format.

# Example format:
```
NAME: ft06
JOBS: 6
MACHINES: 6
OPERATIONS:
# Job Machine ProcessingTime
1 3 1
1 1 3
1 2 6
...
```
"""
function parse_jobshop(filename::String)::JobShopInstance
    lines = readlines(filename)

    name = ""
    n_jobs = 0
    n_machines = 0
    jobs = JobShopJob[]

    section = ""
    current_job_id = 0
    operations = Operation[]

    for line in lines
        line = strip(line)
        if isempty(line) || startswith(line, "#")
            continue
        end

        if startswith(line, "NAME")
            name = strip(split(line, ':')[2])
        elseif startswith(line, "JOBS")
            n_jobs = parse(Int, strip(split(line, ':')[2]))
        elseif startswith(line, "MACHINES")
            n_machines = parse(Int, strip(split(line, ':')[2]))
        elseif startswith(line, "OPERATIONS")
            section = "OPERATIONS"
        elseif section == "OPERATIONS"
            parts = split(line)
            if length(parts) >= 3
                job_id = parse(Int, parts[1])
                machine_id = parse(Int, parts[2])
                proc_time = parse(Int, parts[3])

                # If new job, save previous job
                if job_id != current_job_id && !isempty(operations)
                    push!(jobs, JobShopJob(current_job_id, operations))
                    operations = Operation[]
                end

                current_job_id = job_id
                op_id = length(operations) + 1
                push!(operations, Operation(job_id, op_id, machine_id, proc_time))
            end
        end
    end

    # Add last job
    if !isempty(operations)
        push!(jobs, JobShopJob(current_job_id, operations))
    end

    return JobShopInstance(name, n_jobs, n_machines, jobs)
end

"""
    parse_flowshop(filename::String)::FlowShopInstance

Parse Flow Shop Scheduling format (Taillard format).

# Example format:
```
NAME: tai20_5
JOBS: 20
MACHINES: 5
PROCESSING_TIMES:
# Each row is a job, each column is a machine
54 79 16 66 58
83 3 89 58 56
...
```
"""
function parse_flowshop(filename::String)::FlowShopInstance
    lines = readlines(filename)

    name = ""
    n_jobs = 0
    n_machines = 0
    processing_times = Matrix{Int}(undef, 0, 0)

    section = ""
    row_idx = 1

    for line in lines
        line = strip(line)
        if isempty(line) || startswith(line, "#")
            continue
        end

        if startswith(line, "NAME")
            name = strip(split(line, ':')[2])
        elseif startswith(line, "JOBS")
            n_jobs = parse(Int, strip(split(line, ':')[2]))
        elseif startswith(line, "MACHINES")
            n_machines = parse(Int, strip(split(line, ':')[2]))
            processing_times = zeros(Int, n_jobs, n_machines)
        elseif startswith(line, "PROCESSING_TIMES")
            section = "TIMES"
        elseif section == "TIMES"
            parts = split(line)
            if !isempty(parts) && all(c -> isdigit(c) || isspace(c), line)
                for (col_idx, part) in enumerate(parts)
                    if col_idx <= n_machines && row_idx <= n_jobs
                        processing_times[row_idx, col_idx] = parse(Int, part)
                    end
                end
                row_idx += 1
            end
        end
    end

    return FlowShopInstance(name, n_jobs, n_machines, processing_times)
end

"""
    create_sample_jobshop(n_jobs::Int, n_machines::Int, filename::String)

Create sample Job Shop instance.
"""
function create_sample_jobshop(n_jobs::Int, n_machines::Int, filename::String)
    open(filename, "w") do io
        println(io, "NAME: random_js_$(n_jobs)x$(n_machines)")
        println(io, "JOBS: $n_jobs")
        println(io, "MACHINES: $n_machines")
        println(io, "OPERATIONS:")
        println(io, "# Job Machine ProcessingTime")

        for job in 1:n_jobs
            # Each job has operations on all machines in random order
            machine_order = randperm(n_machines)

            for machine in machine_order
                proc_time = rand(1:100)
                println(io, "$job $machine $proc_time")
            end
        end
    end
end

"""
    create_sample_flowshop(n_jobs::Int, n_machines::Int, filename::String)

Create sample Flow Shop instance (Taillard format).
"""
function create_sample_flowshop(n_jobs::Int, n_machines::Int, filename::String)
    open(filename, "w") do io
        println(io, "NAME: random_fs_$(n_jobs)x$(n_machines)")
        println(io, "JOBS: $n_jobs")
        println(io, "MACHINES: $n_machines")
        println(io, "PROCESSING_TIMES:")
        println(io, "# Each row = job, each column = machine")

        for job in 1:n_jobs
            times = [rand(1:100) for _ in 1:n_machines]
            println(io, join(times, " "))
        end
    end
end

end # module
