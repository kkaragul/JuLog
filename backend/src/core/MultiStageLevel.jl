"""
Multi-Stage Level

Implements Algorithm 2 (MultiStageLevel) from the paper.
Coordinates the execution of S1HH and S2HH stages.
"""
module MultiStageLevel

using ..MoveAcceptance
using ..RelayHybridisation
using ..S1HH: stage_one_hh
using ..S2HH: stage_two_hh, compute_scores_from_pareto

export multi_stage_level, MSHHStatistics

"""
    MSHHStatistics

Statistics collected during MSHH execution.
"""
mutable struct MSHHStatistics
    stages_executed::Int
    s1hh_executions::Int
    s2hh_executions::Int
    total_improvements::Int
    llh_usage::Dict{String, Int}
    stage_transitions::Vector{Tuple{String, Float64, Float64}}  # (stage_type, time, objective)

    function MSHHStatistics()
        new(0, 0, 0, 0, Dict{String, Int}(), Vector{Tuple{String, Float64, Float64}}())
    end
end

"""
    multi_stage_level(
        domain,
        initial_solution,
        params
    )

Implement Algorithm 2 (MultiStageLevel) from the paper.

From paper Section 3.1:
"This work describes an iterated multilevel search framework which allows the
use of multiple interacting hyper-heuristics cyclically during the search process."

# Algorithm 2 Key Steps:
1. Initialize all LLHs (single + relay combinations) with scores (lines 1-6)
2. Main loop until termination (line 8)
3. Execute S1HH (roulette wheel selection) (lines 9-11)
4. Check if S2HH should be invoked (line 15)
5. If yes: run S2HH (greedy/dominance) and update scores (lines 20-28)
6. If no: reset scores to initial values (line 30)

# Stage Transition Logic (from paper Section 3.2):
- S1HH → S2HH: Probabilistic (PS2HH) if no improvement
- S2HH → S1HH: Deterministic (always)

# Arguments
- `domain`: Problem domain implementing AbstractDomain interface
- `initial_solution`: Initial solution
- `params`: MSHHParameters

# Returns
- MSHHResult with best solution and statistics
"""
function multi_stage_level(
    domain,
    initial_solution,
    params
)
    start_time = time()
    stats = MSHHStatistics()

    # Algorithm 2, line 1: Get all base LLHs
    base_llh_ids = get_llh_ids(domain)
    n = length(base_llh_ids)

    # Algorithm 2, line 1: Create relay heuristics (n + n²total)
    all_llh_ids = create_relay_heuristics(base_llh_ids)

    # Algorithm 2, line 6: Initialize scores
    # Single heuristics start with score 1, relay heuristics start with score 0
    scores = Dict{String, Float64}()
    for id in all_llh_ids
        scores[id] = is_relay_heuristic(id) ? 0.0 : 1.0
    end

    # Algorithm 2, lines 2-5: Initialize solutions
    current_solution = copy_solution(domain, initial_solution)
    input_stage1 = copy_solution(domain, initial_solution)
    input_stage2 = copy_solution(domain, initial_solution)
    best_overall = copy_solution(domain, initial_solution)
    best_stage = copy_solution(domain, initial_solution)

    # Algorithm 2, line 7: Initialize threshold values
    threshold = AdaptiveThreshold(params.C)
    counter = 0
    time_best_stage_improved = time()

    # Track objectives
    best_overall_objective = get_objective_value(domain, best_overall)
    best_stage_objective = get_objective_value(domain, best_stage)

    # Algorithm 2, line 8: Main loop
    while time() - start_time < params.time_limit
        stats.stages_executed += 1

        # =================================================================
        # STAGE 1: Roulette Wheel Selection (Algorithm 2, lines 9-11)
        # =================================================================
        stats.s1hh_executions += 1

        push!(stats.stage_transitions,
              ("S1HH", time() - start_time, best_overall_objective))

        (current_solution, best_overall, best_stage, improvements) = stage_one_hh(
            domain,
            all_llh_ids,
            scores,
            input_stage1,
            best_overall,
            threshold,
            params,
            start_time
        )

        stats.total_improvements += improvements

        # Algorithm 2, lines 12-14: Check if counter should be reset or incremented
        current_best_stage_obj = get_objective_value(domain, best_stage)

        if counter == length(params.C) - 1
            # Algorithm 2, line 13: Reset if at end of C list
            best_stage = copy_solution(domain, current_solution)
            best_stage_objective = get_objective_value(domain, best_stage)
            counter = 0
        end

        # =================================================================
        # DECISION: Should we invoke S2HH? (Algorithm 2, line 15)
        # =================================================================
        should_invoke_s2hh = rand() < params.PS2HH

        if should_invoke_s2hh
            # Algorithm 2, lines 16-19: Pre-processing for S2HH
            if get_objective_value(domain, best_stage) >= get_objective_value(domain, input_stage2)
                input_stage2 = copy_solution(domain, best_stage)
                counter += 1
            else
                # No improvement, increment counter
                MoveAcceptance.increment_counter!(threshold)
            end

            counter = 0
            input_stage2 = copy_solution(domain, best_stage)

            # =================================================================
            # STAGE 2: Greedy/Dominance-based Selection (Algorithm 2, lines 20-23)
            # =================================================================
            stats.s2hh_executions += 1

            push!(stats.stage_transitions,
                  ("S2HH", time() - start_time, best_overall_objective))

            (best_overall, best_stage, best_step, pareto_archive) = stage_two_hh(
                domain,
                all_llh_ids,
                input_stage2,
                best_overall,
                threshold,
                params,
                start_time
            )

            input_stage2 = copy_solution(domain, best_step)

            # Algorithm 2, lines 24-28: Post-processing of S2HH
            # Compute new scores based on Pareto dominance
            scores = compute_scores_from_pareto(
                pareto_archive,
                all_llh_ids,
                is_minimization(domain)
            )

            # Update counter based on improvement
            best_overall_objective = get_objective_value(domain, best_overall)
        else
            # Algorithm 2, line 30: Reset scores if S2HH not invoked
            for id in all_llh_ids
                scores[id] = is_relay_heuristic(id) ? 0.0 : 1.0
            end

            # Update epsilon
            update_epsilon(threshold, get_objective_value(domain, best_stage))
        end

        # Algorithm 2, line 32: Update input for next S1HH stage
        input_stage1 = copy_solution(domain, best_stage)

        # Update statistics
        best_overall_objective = get_objective_value(domain, best_overall)

        # Track LLH usage (for reporting)
        for (llh_id, score) in scores
            if score > 0.0
                stats.llh_usage[llh_id] = get(stats.llh_usage, llh_id, 0) + 1
            end
        end
    end

    # Algorithm 2, line 34: Return best solution
    computation_time = time() - start_time

    return MSHHResult(
        domain,
        best_overall,
        best_overall_objective,
        computation_time,
        stats
    )
end

"""
    MSHHResult

Result returned by multi_stage_level.
"""
struct MSHHResult
    domain::Any
    best_solution::Any
    best_objective::Float64
    computation_time::Float64
    statistics::MSHHStatistics
end

"""Helper functions"""

function get_llh_ids(domain)
    return domain.llh_ids
end

function copy_solution(domain, solution)
    return deepcopy(solution)
end

function get_objective_value(domain, solution)
    return domain.objective(solution)
end

function is_minimization(domain)
    return get(domain.properties, :minimization, true)
end

function update_epsilon(threshold, best_obj)
    return MoveAcceptance.update_epsilon(threshold, best_obj)
end

end # module
