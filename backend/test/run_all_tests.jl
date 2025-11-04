"""
MSHH Framework - Master Test Suite

Runs comprehensive tests for all 8 problem domains:
1. TSP (Traveling Salesman Problem)
2. CVRP (Capacitated Vehicle Routing Problem)
3. CVRPTW (CVRP with Time Windows)
4. EVRP (Electric Vehicle Routing Problem)
5. CO2VRP (Green Vehicle Routing Problem)
6. BinPacking (Bin Packing Problem)
7. JobShop (Job Shop Scheduling)
8. FlowShop (Flow Shop Scheduling)

Usage:
    julia run_all_tests.jl
"""

using Test

println("="^80)
println("MSHH FRAMEWORK - COMPREHENSIVE TEST SUITE")
println("="^80)
println()

# Track overall results
total_tests = 0
passed_tests = 0
failed_tests = 0
test_results = Dict{String, Bool}()

"""
Run a test file and capture results
"""
function run_test_file(test_name::String, test_file::String)
    global total_tests, passed_tests, failed_tests

    println("\n" * "─"^80)
    println("Running: $test_name")
    println("─"^80)

    try
        include(test_file)
        test_results[test_name] = true
        passed_tests += 1
        println("✓ $test_name PASSED")
        return true
    catch e
        test_results[test_name] = false
        failed_tests += 1
        println("✗ $test_name FAILED")
        println("Error: $e")
        return false
    end
end

# Start timing
start_time = time()

# Run all domain tests
println("\n📦 Testing Core MSHH Framework...")
println()

test_files = [
    ("TSP Domain", "test_tsp.jl"),
    ("CVRP Domain", "test_cvrp.jl"),
    ("CVRPTW Domain", "test_cvrptw.jl"),
    ("EVRP Domain", "test_evrp.jl"),
    ("CO2VRP Domain", "test_co2vrp.jl"),
    ("BinPacking Domain", "test_binpacking.jl"),
    ("JobShop Domain", "test_jobshop.jl"),
    ("FlowShop Domain", "test_flowshop.jl")
]

for (test_name, test_file) in test_files
    total_tests += 1
    run_test_file(test_name, test_file)
end

# Calculate elapsed time
elapsed_time = time() - start_time

# Print summary
println("\n" * "="^80)
println("TEST SUITE SUMMARY")
println("="^80)
println()

for (test_name, passed) in sort(collect(test_results), by=x->x[1])
    status = passed ? "✓ PASS" : "✗ FAIL"
    println("  $status  $test_name")
end

println()
println("─"^80)
println("Total Tests:   $total_tests")
println("Passed:        $passed_tests")
println("Failed:        $failed_tests")
println("Success Rate:  $(round(passed_tests/total_tests * 100, digits=1))%")
println("Elapsed Time:  $(round(elapsed_time, digits=2))s")
println("─"^80)
println()

if failed_tests == 0
    println("🎉 ALL TESTS PASSED! Framework is ready for production.")
    println()
    exit(0)
else
    println("⚠️  Some tests failed. Please review the errors above.")
    println()
    exit(1)
end
