"""
Stage One Hyper-Heuristic (S1HH)

Implements Algorithm 3 from the paper.
Uses roulette wheel selection with adaptive threshold move acceptance.
"""
module S1HH

using ..MoveAcceptance
using ..RelayHybridisation

export stage_one_hh, S1HHState

"""
    S1HHState

State maintained during S1HH execution.
"""
mutable struct S1HHState
    current_solution::Any
    best_stage_solution::Any
    best_overall_solution::Any
    best_stage_objective::Float64
    best_overall_objective::Float64
    time_best_stage_improved::Float64
    start_time::Float64
    last_improvement_time::Float64
end

"""
    roulette_wheel_selection(llh_ids::Vector{String}, scores::Dict{String, Float64})::String

Select a low-level heuristic using roulette wheel selection based on scores.

From paper Algorithm 3, line 3:
"hIndex ← rouletteWheelSelection(LLHall, scoreall)"

Probability of selecting LLHᵢ = scoreᵢ / Σⱼ(scoreⱼ)

# Arguments
- `llh_ids`: Vector of all available LLH IDs
- `scores`: Dictionary mapping LLH IDs to their scores

# Returns
- Selected LLH ID
"""
function roulette_wheel_selection(llh_ids::Vector{String}, scores::Dict{String, Float64})::String
    # Calculate total score
    total_score = sum(scores[id] for id in llh_ids)

    # If all scores are 0, select randomly
    if total_score ≈ 0.0
        return rand(llh_ids)
    end

    # Generate random number for roulette wheel
    r = rand() * total_score
    cumulative = 0.0

    # Spin the wheel
    for id in llh_ids
        cumulative += scores[id]
        if cumulative >= r
            return id
        end
    end

    # Fallback (should not reach here)
    return llh_ids[end]
end

"""
    stage_one_hh(
        domain,
        llh_ids::Vector{String},
        scores::Dict{String, Float64},
        input_solution,
        best_overall_solution,
        threshold,
        params,
        start_time::Float64
    )

Execute Stage One Hyper-Heuristic (Algorithm 3).

From paper Section 3.2.1:
"In stage one, the roulette wheel selection based hyper-heuristic chooses and
applies randomly a low level heuristic based on a score associated with each
low level heuristic."

# Algorithm 3 (S1HH) Key Steps:
1. Select heuristic using roulette wheel (line 3)
2. Check if restart needed (lines 4-8)
3. Apply selected heuristic for duration τ (lines 9-21)
4. Accept/reject using adaptive threshold (line 11-13)
5. Update best solutions (lines 14-20)

# Arguments
- `domain`: Problem domain
- `llh_ids`: All available LLH IDs (single + relay)
- `scores`: Current scores for each LLH
- `input_solution`: Starting solution for this stage
- `best_overall_solution`: Best solution found so far across all stages
- `threshold`: Adaptive threshold for move acceptance
- `params`: MSHH parameters (τ, d, s1, etc.)
- `start_time`: Time when overall algorithm started

# Returns
- Tuple of (current_solution, best_overall_solution, best_stage_solution, improvements_made)
"""
function stage_one_hh(
    domain,
    llh_ids::Vector{String},
    scores::Dict{String, Float64},
    input_solution,
    best_overall_solution,
    threshold,
    params,
    start_time::Float64
)
    # Initialize state
    state = S1HHState(
        copy_solution(domain, input_solution),
        copy_solution(domain, input_solution),
        copy_solution(domain, best_overall_solution),
        get_objective_value(domain, input_solution),
        get_objective_value(domain, best_overall_solution),
        time(),
        start_time,
        time()
    )

    stage_start_time = time()
    improvements_made = 0

    # Main loop: continue until termination criteria met
    while true
        # Check termination criteria
        if time() - start_time >= params.time_limit
            break  # Overall time limit exceeded
        end

        if time() - state.last_improvement_time >= params.s1
            break  # No improvement for s1 duration (Algorithm 3 termination criteria)
        end

        # Algorithm 3, lines 4-8: Check if restart needed
        if time() - state.time_best_stage_improved >= params.d
            # Restart from best stage solution
            state.current_solution = copy_solution(domain, state.best_stage_solution)
            update_epsilon(threshold, state.best_stage_objective)
            state.time_best_stage_improved = time()
        end

        # Algorithm 3, line 3: Select heuristic using roulette wheel
        selected_llh_id = roulette_wheel_selection(llh_ids, scores)

        # Algorithm 3, lines 9-21: Apply selected heuristic for duration τ
        heuristic_start = time()
        while time() - heuristic_start < params.τ
            # Apply heuristic
            intensity = get_intensity(domain)
            new_solution = apply_heuristic(domain, selected_llh_id, state.current_solution, intensity)
            new_objective = get_objective_value(domain, new_solution)

            # Algorithm 3, lines 11-13: Move acceptance
            if accept_move(
                new_objective,
                get_objective_value(domain, state.current_solution),
                state.best_stage_objective,
                threshold,
                is_minimization(domain)
            )
                state.current_solution = new_solution

                # Algorithm 3, lines 14-17: Update best stage solution
                if is_improvement(domain, new_objective, state.best_stage_objective)
                    state.best_stage_solution = copy_solution(domain, new_solution)
                    state.best_stage_objective = new_objective
                    state.time_best_stage_improved = time()
                    state.last_improvement_time = time()
                    improvements_made += 1
                end

                # Algorithm 3, lines 18-20: Update best overall solution
                if is_improvement(domain, new_objective, state.best_overall_objective)
                    state.best_overall_solution = copy_solution(domain, new_solution)
                    state.best_overall_objective = new_objective
                end
            end

            # Check time limits
            if time() - start_time >= params.time_limit
                break
            end
        end
    end

    return (
        state.current_solution,
        state.best_overall_solution,
        state.best_stage_solution,
        improvements_made
    )
end

"""Helper functions"""

function copy_solution(domain, solution)
    # This will be implemented per domain
    return deepcopy(solution)
end

function get_objective_value(domain, solution)
    # This will be implemented per domain
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

function get_intensity(domain)
    # Adaptive intensity: random if move doesn't improve
    return rand()
end

function apply_heuristic(domain, llh_id, solution, intensity)
    if is_relay_heuristic(llh_id)
        return apply_relay_heuristic(llh_id, solution, domain.llh_map, intensity)
    else
        return domain.llh_map[llh_id](solution, intensity)
    end
end

end # module
