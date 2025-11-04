"""
Abstract Domain Interface

Defines the interface that all problem domains must implement.
This follows the HyFlex-style domain barrier concept (Section 4 in paper).
"""

"""
    AbstractDomain

Base type for all problem domains. Each domain must implement:
- Low-level heuristics (LLHs)
- Solution representation
- Objective function
- Feasibility checking
"""
abstract type AbstractDomain end

"""
    AbstractSolution

Base type for solutions in any domain.
"""
abstract type AbstractSolution end

"""
    AbstractLLH

Base type for low-level heuristics.

HyFlex categorizes LLHs as:
- Mutational (MU): Modifies solution, no guarantee of improvement
- Ruin-and-Recreate (RR): Destroys and rebuilds parts of solution
- Hill-Climbing (HC): Local search, returns equal or better solution
- Crossover (XO): Combines two solutions (not used in single-point search)
"""
abstract type AbstractLLH end

# Low-level heuristic types (from HyFlex, Section 4)
abstract type MutationalLLH <: AbstractLLH end
abstract type RuinRecreateLLH <: AbstractLLH end
abstract type HillClimbingLLH <: AbstractLLH end
abstract type CrossoverLLH <: AbstractLLH end  # Not used in MSHH

"""
    get_objective_value(solution::AbstractSolution)::Float64

Calculate and return the objective value of a solution.
"""
function get_objective_value end

"""
    is_feasible(solution::AbstractSolution)::Bool

Check if a solution is feasible according to domain constraints.
"""
function is_feasible end

"""
    generate_initial_solution(domain::AbstractDomain)::AbstractSolution

Generate an initial feasible solution for the domain.
"""
function generate_initial_solution end

"""
    apply_llh(llh::AbstractLLH, solution::AbstractSolution, intensity::Float64=0.0)::AbstractSolution

Apply a low-level heuristic to a solution.

# Arguments
- `llh`: The low-level heuristic to apply
- `solution`: The input solution
- `intensity`: Parameter controlling heuristic behavior (0.0 to 1.0)

# Returns
- New solution after applying the heuristic
"""
function apply_llh end

"""
    get_llhs(domain::AbstractDomain)::Vector{AbstractLLH}

Get all available low-level heuristics for this domain.
"""
function get_llhs end

"""
    copy_solution(solution::AbstractSolution)::AbstractSolution

Create a deep copy of a solution.
"""
function copy_solution end

"""
    LLHInfo

Information about a low-level heuristic.
"""
struct LLHInfo
    id::String
    name::String
    type::Type{<:AbstractLLH}
    description::String
end

"""
    get_llh_info(llh::AbstractLLH)::LLHInfo

Get information about a low-level heuristic.
"""
function get_llh_info end
