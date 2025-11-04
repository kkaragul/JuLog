"""
Move Acceptance Methods

Implements the adaptive threshold-based move acceptance used in MSHH.
Referenced in Algorithm 3 (S1HH) line 11-13 and Algorithm 4 (S2HH) line 8-10.
"""
module MoveAcceptance

export accept_move, update_epsilon, AdaptiveThreshold

"""
    AdaptiveThreshold

Threshold-based move acceptance with adaptive epsilon value.

From paper Section 3.2.1:
"Move acceptance directly accepts improving moves, while non-improving moves
are accepted if the objective value of the candidate solution is better than
(1+ε) of the objective value of the best solution obtained in the relevant stage."
"""
mutable struct AdaptiveThreshold
    epsilon::Float64
    counter::Int
    C::Vector{Int}

    function AdaptiveThreshold(C::Vector{Int})
        new(0.0, 0, C)
    end
end

"""
    accept_move(
        new_obj::Float64,
        current_obj::Float64,
        best_stage_obj::Float64,
        threshold::AdaptiveThreshold,
        is_minimization::Bool=true
    )::Bool

Decide whether to accept a move based on adaptive threshold.

From paper Algorithm 3, line 11 and Algorithm 4, line 8:
- Accept if new solution is better than current
- Accept if new solution is better than (1+ε) * best_stage_objective

# Arguments
- `new_obj`: Objective value of new solution
- `current_obj`: Objective value of current solution
- `best_stage_obj`: Best objective value in current stage
- `threshold`: Adaptive threshold structure
- `is_minimization`: Whether this is a minimization problem

# Returns
- `true` if move should be accepted, `false` otherwise
"""
function accept_move(
    new_obj::Float64,
    current_obj::Float64,
    best_stage_obj::Float64,
    threshold::AdaptiveThreshold,
    is_minimization::Bool=true
)::Bool

    # Always accept improving moves
    if is_minimization
        if new_obj <= current_obj
            return true
        end

        # Accept if better than threshold
        threshold_value = (1.0 + threshold.epsilon) * best_stage_obj
        return new_obj < threshold_value
    else
        if new_obj >= current_obj
            return true
        end

        # Accept if better than threshold
        threshold_value = (1.0 - threshold.epsilon) * best_stage_obj
        return new_obj > threshold_value
    end
end

"""
    update_epsilon(
        threshold::AdaptiveThreshold,
        best_stage_obj::Float64
    )::Float64

Update epsilon value according to Equation 1 from paper.

From paper Equation 1:
ε = (⌊log(f(S_best_stage))⌋ + c_i) / f(S_best_stage)

where c_i ∈ C = {c_0, ..., c_k-1}

# Arguments
- `threshold`: Adaptive threshold structure
- `best_stage_obj`: Best objective value in current stage

# Returns
- Updated epsilon value
"""
function update_epsilon(
    threshold::AdaptiveThreshold,
    best_stage_obj::Float64
)::Float64

    # Handle edge case: objective value less than 1
    if best_stage_obj < 1.0
        threshold.epsilon = 0.0
        return 0.0
    end

    # Get current c_i value
    c_i = threshold.C[mod1(threshold.counter + 1, length(threshold.C))]

    # Calculate epsilon according to Equation 1
    log_value = floor(Int, log10(best_stage_obj))
    epsilon = (log_value + c_i) / best_stage_obj

    # Handle case where equation returns 0 (mentioned in paper Section 3.2.2)
    if epsilon ≈ 0.0
        epsilon = rand(threshold.C) / best_stage_obj
    end

    threshold.epsilon = max(0.0, epsilon)
    return threshold.epsilon
end

"""
    increment_counter!(threshold::AdaptiveThreshold)

Increment the counter for cycling through C values.
Counter is incremented when S1HH fails to improve and S2HH is applied.
"""
function increment_counter!(threshold::AdaptiveThreshold)
    threshold.counter += 1
end

"""
    reset_counter!(threshold::AdaptiveThreshold)

Reset counter to 0 when improvement is achieved.
"""
function reset_counter!(threshold::AdaptiveThreshold)
    threshold.counter = 0
end

end # module
