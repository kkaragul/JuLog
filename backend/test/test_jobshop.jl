"""
Test Suite for Job Shop Scheduling Domain

Tests Job Shop functionality including:
- Instance parsing
- Solution generation
- Makespan calculation
- Low-level heuristics
- MSHH solver
"""

include("../src/MSHH.jl")
using .MSHH
using .MSHH.JobShopDomain
using .MSHH.Parsers
using Test

@testset "JobShop Tests" begin

    @testset "Sample Instance Creation" begin
        filename = "test_instance_js.txt"
        create_sample_jobshop(5, 4, filename)

        @test isfile(filename)

        rm(filename)
    end

    @testset "JobShop Instance Parsing" begin
        filename = "test_parse_js.txt"
        create_sample_jobshop(6, 5, filename)

        instance = parse_jobshop(filename)

        @test instance.n_jobs == 6
        @test instance.n_machines == 5
        @test length(instance.jobs) == 6

        # Each job should have operations on all machines
        for job in instance.jobs
            @test length(job.operations) == instance.n_machines
        end

        rm(filename)
    end

    @testset "JobShop Domain Initialization" begin
        filename = "test_domain_js.txt"
        create_sample_jobshop(5, 4, filename)
        instance = parse_jobshop(filename)

        domain = JobShop(instance)

        @test length(domain.llh_ids) == 8
        @test haskey(domain.llh_map, "js_swap_operations")
        @test haskey(domain.llh_map, "js_local_search")

        rm(filename)
    end

    @testset "Initial Solution Generation" begin
        filename = "test_init_js.txt"
        create_sample_jobshop(6, 4, filename)
        instance = parse_jobshop(filename)
        domain = JobShop(instance)

        solution = generate_initial_solution(domain)

        # Check that schedule exists for all machines
        @test length(solution.machine_schedules) == instance.n_machines

        # Check that all jobs are scheduled
        all_operations = []
        for schedule in solution.machine_schedules
            append!(all_operations, schedule)
        end

        # Each job should have all its operations scheduled
        for job in instance.jobs
            for op in job.operations
                # Check if operation exists in schedules
                found = false
                for scheduled_op in all_operations
                    if scheduled_op.job_id == op.job_id &&
                       scheduled_op.operation_id == op.operation_id
                        found = true
                        break
                    end
                end
                @test found
            end
        end

        rm(filename)
    end

    @testset "Makespan Calculation" begin
        filename = "test_obj_js.txt"
        create_sample_jobshop(4, 3, filename)
        instance = parse_jobshop(filename)
        domain = JobShop(instance)

        solution = generate_initial_solution(domain)
        makespan = calculate_makespan(solution, instance)

        @test makespan > 0
        @test solution.is_evaluated == true
        @test solution.makespan == makespan

        rm(filename)
    end

    @testset "Low-Level Heuristics" begin
        filename = "test_llh_js.txt"
        create_sample_jobshop(8, 5, filename)
        instance = parse_jobshop(filename)
        domain = JobShop(instance)

        initial_solution = generate_initial_solution(domain)

        # Test each LLH
        for llh_id in domain.llh_ids
            new_solution = domain.llh_map[llh_id](initial_solution, 0.5)

            # Check that schedules exist
            @test length(new_solution.machine_schedules) == instance.n_machines

            # Solution should be a new object
            @test new_solution !== initial_solution

            # Should be able to calculate makespan
            makespan = calculate_makespan(new_solution, instance)
            @test makespan > 0
        end

        rm(filename)
    end

    @testset "MSHH Solver Integration" begin
        filename = "test_solve_js.txt"
        create_sample_jobshop(10, 6, filename)
        instance = parse_jobshop(filename)
        domain = JobShop(instance)

        # Quick solve with short time limit
        params = MSHHParameters(time_limit = 5.0)
        solver = MSHHSolver(domain, params)

        result = solve!(solver)

        @test result.best_objective > 0
        @test result.computation_time <= 6.0  # Allow small overhead
        @test result.statistics.stages_executed > 0

        println("Test solve result:")
        println("  Makespan: $(result.best_objective)")
        println("  Time: $(result.computation_time)s")
        println("  Stages: $(result.statistics.stages_executed)")

        rm(filename)
    end

    @testset "Precedence Constraints" begin
        # Test that operations within same job respect precedence
        filename = "test_precedence_js.txt"
        create_sample_jobshop(4, 3, filename)
        instance = parse_jobshop(filename)
        domain = JobShop(instance)

        solution = generate_initial_solution(domain)
        calculate_makespan(solution, instance)

        # Check precedence: later operations start after earlier ones complete
        for job in instance.jobs
            for i in 1:(length(job.operations)-1)
                curr_op = job.operations[i]
                next_op = job.operations[i+1]

                curr_end = solution.operation_end_times[(curr_op.job_id, curr_op.operation_id)]
                next_start = solution.operation_start_times[(next_op.job_id, next_op.operation_id)]

                @test next_start >= curr_end
            end
        end

        rm(filename)
    end

end

println("\n✓ JobShop tests completed")
