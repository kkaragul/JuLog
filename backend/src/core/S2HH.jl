"""
Stage Two Hyper-Heuristic (S2HH)

Implements Algorithm 4 from the paper.
Uses greedy selection with dominance-based scoring to reduce the set of LLHs.
"""
module S2HH

using ..MoveAcceptance
using ..RelayHybridisation

export stage_two_hh, compute_scores_from_pareto

"""
    ParetoPoint

Represents a point in the Pareto archive.
From paper Section 3.2.2: Trade-off between improvement and number of steps.
"""
struct ParetoPoint
    llh_id::String
    objective_value::Float64
    step_number::Int
end

"""
    stage_two_hh(
        domain,
        llh_ids::Vector{String},
        input_solution,
        best_overall_solution,
        threshold,
        params,
        start_time::Float64
    )

Execute Stage Two Hyper-Heuristic (Algorithm 4).

From paper Section 3.2.2:
"The aim of this stage is to reduce the set of low level heuristics and adjust
their scores according to their 'performance' using the idea of the dominance-
based heuristic selection."

# Algorithm 4 (S2HH) Key Steps:
1. Update epsilon once at start (line 3)
2. Apply all LLHs in greedy fashion for s2 steps (lines 4-14)
3. At each step, take best solution from all LLHs (line 12)
4. Build Pareto archive tracking (step, improvement, heuristic) (line 13)
5. Compute new scores based on Pareto front dominance (post-processing)

# Arguments
- `domain`: Problem domain
- `llh_ids`: All available LLH IDs
- `input_solution`: Starting solution for this stage
- `best_overall_solution`: Best solution found so far
- `threshold`: Adaptive threshold
- `params`: MSHH parameters
- `start_time`: Overall algorithm start time

# Returns
- Tuple of (best_overall_solution, best_stage_solution, best_step_solution, pareto_archive)
"""
function stage_two_hh(
    domain,
    llh_ids::Vector{String},
    input_solution,
    best_overall_solution,
    threshold,
    params,
    start_time::Float64
)
    # Algorithm 4, line 2: Initialize
    best_stage_solution = copy_solution(domain, input_solution)
    best_stage_objective = get_objective_value(domain, input_solution)

    best_overall = copy_solution(domain, best_overall_solution)
    best_overall_objective = get_objective_value(domain, best_overall_solution)

    # Algorithm 4, line 3: Update epsilon once
    update_epsilon(threshold, best_stage_objective)

    # Pareto archive for tracking performance
    pareto_archive = Vector{ParetoPoint}()

    best_step_solution = copy_solution(domain, input_solution)

    # Algorithm 4, lines 4-14: Greedy loop for s2 steps
    for step in 1:params.s2
        # Check time limit
        if time() - start_time >= params.time_limit
            break
        end

        current_step_solution = copy_solution(domain, input_solution)

        # Variables to track best LLH in this step
        best_llh_this_step = nothing
        best_solution_this_step = nothing
        best_objective_this_step = Inf
        all_failed = true

        # Algorithm 4, lines 4-12: Try all LLHs
        for llh_id in llh_ids
            # Algorithm 4, line 5: Reset to input solution
            test_solution = copy_solution(domain, input_solution)

            # Algorithm 4, lines 6-10: Apply heuristic for duration τ
            heuristic_start = time()
            while time() - heuristic_start < params.τ
                intensity = rand()
                new_solution = apply_heuristic(domain, llh_id, test_solution, intensity)
                new_objective = get_objective_value(domain, new_solution)

                # Algorithm 4, lines 8-10: Accept move based on threshold
                if accept_move(
                    new_objective,
                    get_objective_value(domain, test_solution),
                    best_stage_objective,
                    threshold,
                    is_minimization(domain)
                )
                    test_solution = new_solution
                end

                # Check time limit
                if time() - start_time >= params.time_limit
                    break
                end
            end

            # Check if this LLH produced a different solution
            test_objective = get_objective_value(domain, test_solution)
            input_objective = get_objective_value(domain, input_solution)

            if !isapprox(test_objective, input_objective, rtol=1e-6)
                all_failed = false

                # Track if this is best in current step (greedy selection)
                if is_minimization(domain)
                    if test_objective < best_objective_this_step
                        best_objective_this_step = test_objective
                        best_solution_this_step = copy_solution(domain, test_solution)
                        best_llh_this_step = llh_id
                    end
                else
                    if test_objective > best_objective_this_step
                        best_objective_this_step = test_objective
                        best_solution_this_step = copy_solution(domain, test_solution)
                        best_llh_this_step = llh_id
                    end
                end
            end
        end

        # If all heuristics failed, assign worst possible value to all
        if all_failed
            for llh_id in llh_ids
                push!(pareto_archive, ParetoPoint(llh_id, Inf, step))
            end
        else
            # Algorithm 4, line 12: Update best values with greedy choice
            if !isnothing(best_solution_this_step)
                # Update stage best
                if is_improvement(domain, best_objective_this_step, best_stage_objective)
                    best_stage_solution = copy_solution(domain, best_solution_this_step)
                    best_stage_objective = best_objective_this_step
                end

                # Update overall best
                if is_improvement(domain, best_objective_this_step, best_overall_objective)
                    best_overall = copy_solution(domain, best_solution_this_step)
                    best_overall_objective = best_objective_this_step
                end

                # Update step best
                best_step_solution = copy_solution(domain, best_solution_this_step)

                # Algorithm 4, line 13: Update Pareto archive
                push!(pareto_archive, ParetoPoint(best_llh_this_step, best_objective_this_step, step))

                # Use best solution as input for next step (greedy approach)
                input_solution = copy_solution(domain, best_solution_this_step)
            end
        end
    end

    return (
        best_overall,
        best_stage_solution,
        best_step_solution,
        pareto_archive
    )
end

"""
    compute_scores_from_pareto(
        pareto_archive::Vector{ParetoPoint},
        llh_ids::Vector{String},
        is_minimization::Bool
    )::Dict{String, Float64}

Compute LLH scores based on Pareto dominance.

From paper Algorithm 2, line 27 and Section 3.2.2:
"The non-dominated solutions each associated with the low level heuristic that
generated it are determined from the archive. Then the score of each 'non-dominated'
low level heuristic is increased by 1."

A solution at step i dominates solution at step j if:
- step_i < step_j (achieved earlier)
- objective_i is better than objective_j

# Arguments
- `pareto_archive`: Archive of solutions with their generating LLH
- `llh_ids`: All LLH IDs
- `is_minimization`: Whether problem is minimization

# Returns
- Dictionary mapping LLH IDs to their new scores
"""
function compute_scores_from_pareto(
    pareto_archive::Vector{ParetoPoint},
    llh_ids::Vector{String},
    is_minimization::Bool
)::Dict{String, Float64}

    # Initialize all scores to 0
    scores = Dict{String, Float64}(id => 0.0 for id in llh_ids)

    # Find non-dominated points
    non_dominated = Vector{ParetoPoint}()

    for point in pareto_archive
        is_dominated = false

        for other in pareto_archive
            if other === point
                continue
            end

            # Check if 'other' dominates 'point'
            # Domination: earlier step AND better objective
            better_step = other.step_number < point.step_number

            better_objective = if is_minimization
                other.objective_value < point.objective_value
            else
                other.objective_value > point.objective_value
            end

            if better_step && better_objective
                is_dominated = true
                break
            end
        end

        if !is_dominated
            push!(non_dominated, point)
        end
    end

    # Increment score for each non-dominated LLH
    # Note: An LLH can appear multiple times in non-dominated set
    for point in non_dominated
        scores[point.llh_id] += 1.0
    end

    return scores
end

"""Helper functions"""

function copy_solution(domain, solution)
    return deepcopy(solution)
end

function get_objective_value(domain, solution)
    return domain.objective(solution)
end

function is_minimization(domain)
    return get(domain.properties, :minimization, true)
end

function is_improvement(domain, new_obj, current_obj)
    if is_minimization(domain)
        return new_obj < current_obj
    else
        return new_obj > current_obj
    end
end

function apply_heuristic(domain, llh_id, solution, intensity)
    if is_relay_heuristic(llh_id)
        return apply_relay_heuristic(llh_id, solution, domain.llh_map, intensity)
    else
        return domain.llh_map[llh_id](solution, intensity)
    end
end

function accept_move(new_obj, current_obj, best_stage_obj, threshold, is_min)
    return MoveAcceptance.accept_move(new_obj, current_obj, best_stage_obj, threshold, is_min)
end

function update_epsilon(threshold, best_obj)
    return MoveAcceptance.update_epsilon(threshold, best_obj)
end

end # module
