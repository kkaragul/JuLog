"""
Test Suite for Flow Shop Scheduling Domain

Tests Flow Shop functionality including:
- Instance parsing
- Solution generation
- Makespan calculation
- Low-level heuristics
- MSHH solver
"""

include("../src/MSHH.jl")
using .MSHH
using .MSHH.FlowShopDomain
using .MSHH.Parsers
using Test

@testset "FlowShop Tests" begin

    @testset "Sample Instance Creation" begin
        filename = "test_instance_fs.txt"
        create_sample_flowshop(10, 5, filename)

        @test isfile(filename)

        rm(filename)
    end

    @testset "FlowShop Instance Parsing" begin
        filename = "test_parse_fs.txt"
        create_sample_flowshop(12, 6, filename)

        instance = parse_flowshop(filename)

        @test instance.n_jobs == 12
        @test instance.n_machines == 6
        @test size(instance.processing_times) == (12, 6)

        # All processing times should be positive
        @test all(instance.processing_times .> 0)

        rm(filename)
    end

    @testset "FlowShop Domain Initialization" begin
        filename = "test_domain_fs.txt"
        create_sample_flowshop(8, 4, filename)
        instance = parse_flowshop(filename)

        domain = FlowShop(instance)

        @test length(domain.llh_ids) == 6
        @test haskey(domain.llh_map, "fs_swap")
        @test haskey(domain.llh_map, "fs_neh")
        @test haskey(domain.llh_map, "fs_2opt")

        rm(filename)
    end

    @testset "Initial Solution Generation (NEH)" begin
        filename = "test_init_fs.txt"
        create_sample_flowshop(10, 5, filename)
        instance = parse_flowshop(filename)
        domain = FlowShop(instance)

        solution = generate_initial_solution(domain)

        # Check that solution is a valid permutation
        @test length(solution.job_sequence) == instance.n_jobs
        @test length(unique(solution.job_sequence)) == instance.n_jobs
        @test all(1 .<= solution.job_sequence .<= instance.n_jobs)

        # Solution should be evaluated
        @test solution.is_evaluated == true
        @test solution.makespan > 0

        rm(filename)
    end

    @testset "Makespan Calculation" begin
        filename = "test_obj_fs.txt"
        create_sample_flowshop(5, 3, filename)
        instance = parse_flowshop(filename)
        domain = FlowShop(instance)

        # Create simple sequence: [1, 2, 3, 4, 5]
        solution = FlowShopSolution([1, 2, 3, 4, 5])
        makespan = calculate_makespan(solution, instance)

        @test makespan > 0
        @test solution.is_evaluated == true
        @test solution.makespan == makespan

        # Completion times matrix should be correct size
        @test size(solution.completion_times) == (5, 3)

        # Check that completion times are non-decreasing
        for i in 1:5
            for j in 1:(3-1)
                @test solution.completion_times[i, j] <= solution.completion_times[i, j+1]
            end
        end

        # Makespan should be last job's last machine completion time
        @test solution.makespan == solution.completion_times[5, 3]

        rm(filename)
    end

    @testset "Low-Level Heuristics" begin
        filename = "test_llh_fs.txt"
        create_sample_flowshop(15, 6, filename)
        instance = parse_flowshop(filename)
        domain = FlowShop(instance)

        initial_solution = generate_initial_solution(domain)

        # Test each LLH
        for llh_id in domain.llh_ids
            new_solution = domain.llh_map[llh_id](initial_solution, 0.5)

            # Check that solution is still a valid permutation
            @test length(new_solution.job_sequence) == instance.n_jobs
            @test length(unique(new_solution.job_sequence)) == instance.n_jobs
            @test all(1 .<= new_solution.job_sequence .<= instance.n_jobs)

            # Solution should be a new object
            @test new_solution !== initial_solution

            # Should be able to calculate makespan
            makespan = calculate_makespan(new_solution, instance)
            @test makespan > 0
        end

        rm(filename)
    end

    @testset "MSHH Solver Integration" begin
        filename = "test_solve_fs.txt"
        create_sample_flowshop(20, 8, filename)
        instance = parse_flowshop(filename)
        domain = FlowShop(instance)

        # Quick solve with short time limit
        params = MSHHParameters(time_limit = 5.0)
        solver = MSHHSolver(domain, params)

        result = solve!(solver)

        @test result.best_objective > 0
        @test result.computation_time <= 6.0  # Allow small overhead
        @test result.statistics.stages_executed > 0

        # Check solution validity
        @test length(result.best_solution.job_sequence) == instance.n_jobs
        @test length(unique(result.best_solution.job_sequence)) == instance.n_jobs

        println("Test solve result:")
        println("  Makespan: $(result.best_objective)")
        println("  Time: $(result.computation_time)s")
        println("  Stages: $(result.statistics.stages_executed)")

        rm(filename)
    end

    @testset "Swap Heuristic" begin
        filename = "test_swap_fs.txt"
        create_sample_flowshop(8, 4, filename)
        instance = parse_flowshop(filename)
        domain = FlowShop(instance)

        initial_solution = generate_initial_solution(domain)
        initial_sequence = copy(initial_solution.job_sequence)

        # Apply swap with low intensity (should swap once)
        new_solution = domain.llh_map["fs_swap"](initial_solution, 0.2)

        # Sequence should be different but still valid permutation
        @test new_solution.job_sequence != initial_sequence
        @test sort(new_solution.job_sequence) == sort(initial_sequence)

        rm(filename)
    end

    @testset "Insert Heuristic" begin
        filename = "test_insert_fs.txt"
        create_sample_flowshop(10, 5, filename)
        instance = parse_flowshop(filename)
        domain = FlowShop(instance)

        initial_solution = generate_initial_solution(domain)

        # Apply insert heuristic
        new_solution = domain.llh_map["fs_insert"](initial_solution, 0.5)

        # Should still be valid permutation
        @test length(new_solution.job_sequence) == instance.n_jobs
        @test sort(new_solution.job_sequence) == sort(1:instance.n_jobs)

        rm(filename)
    end

    @testset "NEH Improvement Heuristic" begin
        filename = "test_neh_imp_fs.txt"
        create_sample_flowshop(12, 6, filename)
        instance = parse_flowshop(filename)
        domain = FlowShop(instance)

        initial_solution = generate_initial_solution(domain)
        initial_makespan = calculate_makespan(initial_solution, instance)

        # Apply NEH improvement
        improved_solution = domain.llh_map["fs_neh"](initial_solution, 0.7)
        improved_makespan = calculate_makespan(improved_solution, instance)

        # Should be valid and hopefully improved (or at least not worse)
        @test length(improved_solution.job_sequence) == instance.n_jobs
        @test improved_makespan > 0

        rm(filename)
    end

    @testset "Completion Time Matrix" begin
        filename = "test_completion_fs.txt"
        create_sample_flowshop(6, 4, filename)
        instance = parse_flowshop(filename)

        solution = FlowShopSolution([1, 2, 3, 4, 5, 6])
        calculate_makespan(solution, instance)

        # Check completion time constraints
        n_jobs = 6
        n_machines = 4

        for i in 1:n_jobs
            for j in 1:n_machines
                if i > 1 && j > 1
                    # Must wait for both: previous job on this machine AND this job on previous machine
                    prev_job_this_machine = solution.completion_times[i-1, j]
                    this_job_prev_machine = solution.completion_times[i, j-1]

                    @test solution.completion_times[i, j] >= prev_job_this_machine
                    @test solution.completion_times[i, j] >= this_job_prev_machine
                end
            end
        end

        rm(filename)
    end

end

println("\n✓ FlowShop tests completed")
