"""
Test Suite for CVRP Domain

Tests CVRP functionality including:
- Instance parsing
- Solution generation
- Feasibility checking
- Low-level heuristics
- MSHH solver
"""

include("../src/MSHH.jl")
using .MSHH
using .MSHH.CVRPDomain
using .MSHH.Parsers
using Test

@testset "CVRP Tests" begin

    @testset "Sample Instance Creation" begin
        filename = "test_instance.vrp"
        create_sample_vrp(20, 100, filename)

        @test isfile(filename)

        rm(filename)
    end

    @testset "CVRP Instance Parsing" begin
        filename = "test_parse.vrp"
        create_sample_vrp(20, 100, filename)

        instance = parse_vrp(filename)

        @test instance.n_customers == 19  # 20 nodes - 1 depot
        @test instance.capacity == 100.0
        @test size(instance.coordinates) == (20, 2)
        @test size(instance.distances) == (20, 20)
        @test length(instance.demands) == 20
        @test instance.demands[1] == 0.0  # Depot has 0 demand

        rm(filename)
    end

    @testset "CVRP Domain Initialization" begin
        filename = "test_domain.vrp"
        create_sample_vrp(15, 100, filename)
        instance = parse_vrp(filename)

        domain = CVRP(instance)

        @test length(domain.llh_ids) == 8
        @test haskey(domain.llh_map, "swap_intra")
        @test haskey(domain.llh_map, "relocate")

        rm(filename)
    end

    @testset "Initial Solution Generation" begin
        filename = "test_init.vrp"
        create_sample_vrp(15, 100, filename)
        instance = parse_vrp(filename)
        domain = CVRP(instance)

        solution = generate_initial_solution(domain)

        # All customers should be served
        all_customers = vcat([route.customers for route in solution.routes]...)
        @test length(unique(all_customers)) == instance.n_customers
        @test all(c -> 2 <= c <= instance.n_customers + 1, all_customers)

        # All routes should be feasible
        for route in solution.routes
            @test route.load <= instance.capacity
        end

        rm(filename)
    end

    @testset "Objective Calculation" begin
        filename = "test_obj.vrp"
        create_sample_vrp(10, 100, filename)
        instance = parse_vrp(filename)
        domain = CVRP(instance)

        solution = generate_initial_solution(domain)
        obj = calculate_total_distance(solution, instance)

        @test obj > 0
        @test solution.is_evaluated == true
        @test solution.objective_value == obj

        rm(filename)
    end

    @testset "Feasibility Checking" begin
        filename = "test_feas.vrp"
        create_sample_vrp(10, 50, filename)
        instance = parse_vrp(filename)

        # Create a feasible solution
        route1 = CVRPRoute([2, 3], 30.0)
        route2 = CVRPRoute([4, 5], 40.0)
        feasible_sol = CVRPSolution([route1, route2])

        @test check_feasibility(feasible_sol, instance) == true

        # Create an infeasible solution (overloaded)
        route_bad = CVRPRoute([2, 3, 4], 60.0)  # Exceeds capacity
        infeasible_sol = CVRPSolution([route_bad])

        @test check_feasibility(infeasible_sol, instance) == false

        rm(filename)
    end

    @testset "Low-Level Heuristics" begin
        filename = "test_llh.vrp"
        create_sample_vrp(20, 100, filename)
        instance = parse_vrp(filename)
        domain = CVRP(instance)

        initial_solution = generate_initial_solution(domain)

        # Test each LLH
        for llh_id in domain.llh_ids
            new_solution = domain.llh_map[llh_id](initial_solution, 0.5)

            # All customers should still be served
            all_customers = vcat([route.customers for route in new_solution.routes]...)
            @test length(unique(all_customers)) <= instance.n_customers

            # Solution should be a new object
            @test new_solution !== initial_solution
        end

        rm(filename)
    end

    @testset "MSHH Solver Integration" begin
        filename = "test_solve.vrp"
        create_sample_vrp(25, 150, filename)
        instance = parse_vrp(filename)
        domain = CVRP(instance)

        # Quick solve with short time limit
        params = MSHHParameters(time_limit = 5.0)
        solver = MSHHSolver(domain, params)

        result = solve!(solver)

        @test result.best_objective > 0
        @test result.computation_time <= 6.0
        @test result.statistics.stages_executed > 0

        # Check solution validity
        all_customers = vcat([route.customers for route in result.best_solution.routes]...)
        @test length(unique(all_customers)) <= instance.n_customers

        println("Test solve result:")
        println("  Objective: $(result.best_objective)")
        println("  Time: $(result.computation_time)s")
        println("  Routes: $(length(result.best_solution.routes))")
        println("  Stages: $(result.statistics.stages_executed)")

        rm(filename)
    end

    @testset "Solution Saving" begin
        filename_vrp = "test_save.vrp"
        filename_sol = "test_solution.sol"

        create_sample_vrp(15, 100, filename_vrp)
        instance = parse_vrp(filename_vrp)

        route1 = CVRPRoute([2, 3, 4], 50.0)
        route2 = CVRPRoute([5, 6], 40.0)
        solution = CVRPSolution([route1, route2])
        calculate_total_distance(solution, instance)

        save_solution_vrp(filename_sol, solution, instance)

        @test isfile(filename_sol)

        rm(filename_vrp)
        rm(filename_sol)
    end

end

println("\n✓ CVRP tests completed")
