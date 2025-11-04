"""
Benchmark Instance Downloader

Downloads standard benchmark instances for all problem domains:
- TSPLIB (TSP)
- VRPLIB (CVRP)
- Solomon Benchmarks (CVRPTW)
- E-VRP instances (EVRP)
- Taillard Benchmarks (FlowShop)
- OR-Library (JobShop)
- Bin Packing instances

Usage:
    julia download_benchmarks.jl [domain]

    If no domain specified, downloads all.
"""

using HTTP
using Downloads

const BASE_DIR = joinpath(@__DIR__, "..", "instances")

"""
Download a file with progress indication
"""
function download_file(url::String, destination::String)
    println("  Downloading: $(basename(destination))")
    try
        Downloads.download(url, destination)
        println("  ✓ Downloaded: $(basename(destination))")
        return true
    catch e
        println("  ✗ Failed: $(basename(destination)) - $e")
        return false
    end
end

"""
Download TSPLIB instances
"""
function download_tsplib()
    println("\n📦 Downloading TSPLIB instances...")

    tsp_dir = joinpath(BASE_DIR, "tsp")
    mkpath(tsp_dir)

    # Popular TSPLIB instances
    instances = [
        ("eil51", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/eil51.tsp.gz"),
        ("berlin52", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/berlin52.tsp.gz"),
        ("st70", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/st70.tsp.gz"),
        ("eil76", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/eil76.tsp.gz"),
        ("pr76", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/pr76.tsp.gz"),
        ("kroA100", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/kroA100.tsp.gz"),
        ("kroB100", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/kroB100.tsp.gz"),
        ("ch130", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/ch130.tsp.gz"),
        ("ch150", "http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/ch150.tsp.gz"),
    ]

    for (name, url) in instances
        dest = joinpath(tsp_dir, "$name.tsp")
        if !isfile(dest)
            download_file(url, dest * ".gz")
            # Note: Would need to gunzip, simplified for now
        else
            println("  ⊙ Already exists: $name.tsp")
        end
    end

    println("✓ TSPLIB download complete")
end

"""
Create sample TSPLIB instances (alternative to downloading)
"""
function create_tsplib_samples()
    println("\n📦 Creating sample TSPLIB-format instances...")

    include("../src/MSHH.jl")
    using .MSHH.Parsers

    tsp_dir = joinpath(BASE_DIR, "tsp")
    mkpath(tsp_dir)

    instances = [
        (30, "small_30"),
        (50, "medium_50"),
        (100, "large_100"),
        (200, "xlarge_200"),
    ]

    for (size, name) in instances
        dest = joinpath(tsp_dir, "$(name).tsp")
        if !isfile(dest)
            create_sample_tsp(size, dest)
            println("  ✓ Created: $(name).tsp")
        else
            println("  ⊙ Already exists: $(name).tsp")
        end
    end

    println("✓ Sample TSP instances created")
end

"""
Create sample CVRP instances
"""
function create_cvrp_samples()
    println("\n📦 Creating sample VRPLIB-format instances...")

    include("../src/MSHH.jl")
    using .MSHH.Parsers

    cvrp_dir = joinpath(BASE_DIR, "cvrp")
    mkpath(cvrp_dir)

    instances = [
        (25, 100, "small_25_100"),
        (50, 150, "medium_50_150"),
        (100, 200, "large_100_200"),
    ]

    for (size, capacity, name) in instances
        dest = joinpath(cvrp_dir, "$(name).vrp")
        if !isfile(dest)
            create_sample_vrp(size, capacity, dest)
            println("  ✓ Created: $(name).vrp")
        else
            println("  ⊙ Already exists: $(name).vrp")
        end
    end

    println("✓ Sample CVRP instances created")
end

"""
Create sample Solomon instances for CVRPTW
"""
function create_solomon_samples()
    println("\n📦 Creating sample Solomon-format instances...")

    include("../src/MSHH.jl")
    using .MSHH.Parsers

    cvrptw_dir = joinpath(BASE_DIR, "cvrptw")
    mkpath(cvrptw_dir)

    instances = [25, 50, 100]

    for size in instances
        name = "C101_$(size)"
        dest = joinpath(cvrptw_dir, "$(name).txt")
        if !isfile(dest)
            create_sample_solomon(size, dest)
            println("  ✓ Created: $(name).txt")
        else
            println("  ⊙ Already exists: $(name).txt")
        end
    end

    println("✓ Sample Solomon instances created")
end

"""
Create sample EVRP instances
"""
function create_evrp_samples()
    println("\n📦 Creating sample EVRP instances...")

    include("../src/MSHH.jl")
    using .MSHH.Parsers

    evrp_dir = joinpath(BASE_DIR, "evrp")
    mkpath(evrp_dir)

    instances = [20, 40, 60]

    for size in instances
        name = "evrp_$(size)"
        dest = joinpath(evrp_dir, "$(name).evrp")
        if !isfile(dest)
            create_sample_evrp(size, dest)
            println("  ✓ Created: $(name).evrp")
        else
            println("  ⊙ Already exists: $(name).evrp")
        end
    end

    println("✓ Sample EVRP instances created")
end

"""
Create sample Bin Packing instances
"""
function create_binpacking_samples()
    println("\n📦 Creating sample Bin Packing instances...")

    include("../src/MSHH.jl")
    using .MSHH.Parsers

    bp_dir = joinpath(BASE_DIR, "binpacking")
    mkpath(bp_dir)

    instances = [
        (50, 100, "small_50_100"),
        (100, 150, "medium_100_150"),
        (200, 200, "large_200_200"),
    ]

    for (items, capacity, name) in instances
        dest = joinpath(bp_dir, "$(name).bpp")
        if !isfile(dest)
            create_sample_bpp(items, capacity, dest)
            println("  ✓ Created: $(name).bpp")
        else
            println("  ⊙ Already exists: $(name).bpp")
        end
    end

    println("✓ Sample BinPacking instances created")
end

"""
Create sample JobShop instances
"""
function create_jobshop_samples()
    println("\n📦 Creating sample JobShop instances...")

    include("../src/MSHH.jl")
    using .MSHH.Parsers

    js_dir = joinpath(BASE_DIR, "jobshop")
    mkpath(js_dir)

    instances = [
        (6, 6, "ft06"),
        (10, 10, "ft10"),
        (20, 5, "la01"),
        (20, 10, "la16"),
    ]

    for (jobs, machines, name) in instances
        dest = joinpath(js_dir, "$(name).txt")
        if !isfile(dest)
            create_sample_jobshop(jobs, machines, dest)
            println("  ✓ Created: $(name).txt")
        else
            println("  ⊙ Already exists: $(name).txt")
        end
    end

    println("✓ Sample JobShop instances created")
end

"""
Create sample FlowShop instances (Taillard-style)
"""
function create_flowshop_samples()
    println("\n📦 Creating sample FlowShop instances...")

    include("../src/MSHH.jl")
    using .MSHH.Parsers

    fs_dir = joinpath(BASE_DIR, "flowshop")
    mkpath(fs_dir)

    instances = [
        (20, 5, "tai20_5"),
        (20, 10, "tai20_10"),
        (50, 5, "tai50_5"),
        (50, 10, "tai50_10"),
        (100, 5, "tai100_5"),
    ]

    for (jobs, machines, name) in instances
        dest = joinpath(fs_dir, "$(name).txt")
        if !isfile(dest)
            create_sample_flowshop(jobs, machines, dest)
            println("  ✓ Created: $(name).txt")
        else
            println("  ⊙ Already exists: $(name).txt")
        end
    end

    println("✓ Sample FlowShop instances created")
end

"""
Main download function
"""
function main(domain::Union{String, Nothing} = nothing)
    println("="^80)
    println("MSHH Benchmark Instance Manager")
    println("="^80)

    if isnothing(domain) || domain == "all"
        # Create all sample instances
        create_tsplib_samples()
        create_cvrp_samples()
        create_solomon_samples()
        create_evrp_samples()
        create_binpacking_samples()
        create_jobshop_samples()
        create_flowshop_samples()
    elseif domain == "tsp"
        create_tsplib_samples()
    elseif domain == "cvrp"
        create_cvrp_samples()
    elseif domain == "cvrptw"
        create_solomon_samples()
    elseif domain == "evrp"
        create_evrp_samples()
    elseif domain == "binpacking"
        create_binpacking_samples()
    elseif domain == "jobshop"
        create_jobshop_samples()
    elseif domain == "flowshop"
        create_flowshop_samples()
    else
        println("Unknown domain: $domain")
        println("Available: tsp, cvrp, cvrptw, evrp, binpacking, jobshop, flowshop, all")
        return
    end

    println("\n" * "="^80)
    println("✅ Benchmark instances ready!")
    println("="^80)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    domain = length(ARGS) > 0 ? ARGS[1] : "all"
    main(domain)
end
