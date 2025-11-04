"""
Test Suite for TSP Domain

Tests TSP functionality including:
- Instance parsing
- Solution generation
- Low-level heuristics
- MSHH solver
"""

include("../src/MSHH.jl")
using .MSHH
using .MSHH.TSPDomain
using .MSHH.Parsers
using Test

@testset "TSP Tests" begin

    @testset "Sample Instance Creation" begin
        # Create a small test instance
        filename = "test_instance.tsp"
        create_sample_tsp(10, filename)

        @test isfile(filename)

        # Clean up
        rm(filename)
    end

    @testset "TSP Instance Parsing" begin
        # Create and parse instance
        filename = "test_parse.tsp"
        create_sample_tsp(10, filename)

        instance = parse_tsp(filename)

        @test instance.n_cities == 10
        @test size(instance.coordinates) == (10, 2)
        @test size(instance.distances) == (10, 10)

        # Distances should be symmetric
        for i in 1:10, j in 1:10
            @test instance.distances[i,j] ≈ instance.distances[j,i]
        end

        # Diagonal should be 0
        for i in 1:10
            @test instance.distances[i,i] == 0.0
        end

        rm(filename)
    end

    @testset "TSP Domain Initialization" begin
        filename = "test_domain.tsp"
        create_sample_tsp(10, filename)
        instance = parse_tsp(filename)

        domain = TSP(instance)

        @test length(domain.llh_ids) == 7
        @test haskey(domain.llh_map, "swap")
        @test haskey(domain.llh_map, "2opt")

        rm(filename)
    end

    @testset "Initial Solution Generation" begin
        filename = "test_init.tsp"
        create_sample_tsp(10, filename)
        instance = parse_tsp(filename)
        domain = TSP(instance)

        solution = generate_initial_solution(domain)

        @test length(solution.tour) == 10
        @test length(unique(solution.tour)) == 10  # All cities visited once
        @test all(c -> 1 <= c <= 10, solution.tour)

        rm(filename)
    end

    @testset "Objective Calculation" begin
        filename = "test_obj.tsp"
        create_sample_tsp(5, filename)
        instance = parse_tsp(filename)
        domain = TSP(instance)

        solution = TSPSolution([1, 2, 3, 4, 5])
        obj = calculate_tour_length(solution, instance)

        @test obj > 0
        @test solution.is_evaluated == true
        @test solution.objective_value == obj

        rm(filename)
    end

    @testset "Low-Level Heuristics" begin
        filename = "test_llh.tsp"
        create_sample_tsp(10, filename)
        instance = parse_tsp(filename)
        domain = TSP(instance)

        initial_solution = generate_initial_solution(domain)

        # Test each LLH
        for llh_id in domain.llh_ids
            new_solution = domain.llh_map[llh_id](initial_solution, 0.5)

            @test length(new_solution.tour) == 10
            @test length(unique(new_solution.tour)) == 10
            @test new_solution !== initial_solution  # Should be a new object
        end

        rm(filename)
    end

    @testset "MSHH Solver Integration" begin
        filename = "test_solve.tsp"
        create_sample_tsp(15, filename)
        instance = parse_tsp(filename)
        domain = TSP(instance)

        # Quick solve with short time limit
        params = MSHHParameters(time_limit = 5.0)
        solver = MSHHSolver(domain, params)

        result = solve!(solver)

        @test result.best_objective > 0
        @test result.computation_time <= 6.0  # Allow small overhead
        @test result.statistics.stages_executed > 0

        println("Test solve result:")
        println("  Objective: $(result.best_objective)")
        println("  Time: $(result.computation_time)s")
        println("  Stages: $(result.statistics.stages_executed)")

        rm(filename)
    end

    @testset "Solution Saving" begin
        filename_tsp = "test_save.tsp"
        filename_sol = "test_solution.tour"

        create_sample_tsp(10, filename_tsp)
        instance = parse_tsp(filename_tsp)
        solution = TSPSolution([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        calculate_tour_length(solution, instance)

        save_solution_tsp(filename_sol, solution, instance)

        @test isfile(filename_sol)

        # Clean up
        rm(filename_tsp)
        rm(filename_sol)
    end

end

println("\n✓ TSP tests completed")
