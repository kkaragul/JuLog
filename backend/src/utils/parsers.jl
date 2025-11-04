"""
Parsers for Problem Instance Files

Supports TSPLIB and VRPLIB formats for TSP and CVRP instances.
"""
module Parsers

using ..TSPDomain
using ..CVRPDomain

export parse_tsp, parse_vrp, save_solution_tsp, save_solution_vrp

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

end # module
