
import Base.display

abstract type Environment end

mutable struct TikTakToe <: Environment
    current::Vector{Int}
    n_states::Int
    n_actions::Int
    function TikTakToe()
        this = new()
        this.current = fill(0, 9)
        this.n_states = 3^9
        this.n_actions = 9
        return this
    end
end

# TODO:  makro
function s_a_to_index(env::Environment, state::Vector{Int}, action::Int, player::Int)::Int
    branching_factor = 3
    scalar = 9
    index = action
    for s in state
        index += s * scalar
        scalar *= branching_factor
    end
    index += scalar * (player - 1)
    return index
end

function print_current(env::TikTakToe)
    symbols = ["0", "X", "O"]
    board = map(i -> symbols[i+1], env.current)
    for i in 1:3 # col
        for j in 1:3 # row
            print(board[i + 3 * (j - 1)], " ")
        end
        print("\n")
    end
end

function println_current(env::TikTakToe)
    print_current(env)
    println()
end

function valid_actions(env::TikTakToe, state::Vector{Int})::Base.Iterators.Filter
    return Base.Iterators.filter(a -> state[a] == 0, 1:env.n_actions)# findall(state .== 0)
end

function valid_actions(env::TikTakToe)::Base.Iterators.Filter
    return valid_actions(env, env.current)
end

function reset!(env::TikTakToe)
    env.current .= 0
end

function allsame(A::SubArray{Int})
    a_comp = A[1]
    for a in A
        if a != a_comp
            return false
        end
    end
    return true
end

function won(state::Vector{Int})::Int
    col = [1,2,3]
    row = [1,4,7]
    diag1 = [1,5,9]
    diag2 = [3,5,7]
    for i in 0:2
        p = state[col[1] + 3*i]
        if p != 0 && allsame(view(state, col .+ 3*i))
            return p
        end
        p = state[row[1] + i]
        if p != 0 && allsame(view(state, row .+ i))
            return p
        end
    end
    p = state[diag1[1]]
    if p != 0 && allsame(view(state, diag1))
        return p
    end
    p = state[diag2[1]]
    if p != 0 && allsame(view(state, diag2))
        return p
    end
    return 0
end


function step!(env::TikTakToe, action::Int, player::Int, foe::Bool)::Tuple{Float32, Bool, Int}
    env.current[action] = player
    p = won(env.current)

    next_player = player == 1 ? 2 : 1

    if p != 0 && !foe
        @assert p == player
        return 1f0, true, next_player # won
    elseif p != 0 && foe
        @assert p == player
        return -1f0, true, next_player # lost
    end
    if isempty(valid_actions(env))
        return 0f0, true, next_player # draw
    else
        return 0f0, false, next_player
    end

end


env = TikTakToe()

println_current(env)
step!(env, 5, 1)
println_current(env)
step!(env, 9, 2)
println_current(env)
step!(env, 4, 1)
println_current(env)
step!(env, 8, 2)
println_current(env)
step!(env, 6, 1)
println_current(env)
