include("MuBetaZero.jl")
include("ConnectFour.jl")

using Random
using Flux
using StatsBase


mutable struct MuBetaZeroNeural <: MuBetaZero

    policy_networks
    value_networks

    transition_buffer::Array{Vector{Transition}}
    γ::Float32
    ϵ::Float64
    c::Float32 # regularisation parameter
    opt

    tree::MCTSTree
    current_node::MCTSNode

    function MuBetaZeroNeural(policy_network_layout::Chain, value_network_layout::Chain;
                              γ=1.0f0, opt=RMSProp(), ϵ=0.1, c=0.001f0)
        this = new()
        this.policy_networks = [deepcopy(policy_network_layout), deepcopy(policy_network_layout)]
        this.value_networks = [deepcopy(value_network_layout), deepcopy(value_network_layout)]
        this.transition_buffer = [[], []]
        this.γ = γ
        this.opt = opt
        this.ϵ = ϵ
        this.c = c
        return this
    end
end

function flush_transition_buffer!(μβ0::MuBetaZeroNeural)
    μβ0.transition_buffer = [[], []]
end

function greedy_action(μβ0::MuBetaZeroNeural, env::Environment, state::Array{Float32}, player::Int)::Int
    x = reshape(state, size(state)..., 1)
    ps = μβ0.policy_networks[player](x)[:,1]
    a = argmax(ps)
    return a
end

function action(μβ0::MuBetaZeroNeural, env::Environment, state::Array{Float32}, player::Int)::Int
    x = reshape(state, size(state)..., 1)
    ps = μβ0.policy_networks[player](x)[:,1]
    a = sample(1:env.n_actions, Weights(ps))
    return a
end

function action_ps(μβ0::MuBetaZeroNeural, env::Environment, state::Array{Float32}, player::Int)::Vector{Float32}
    x = reshape(state, size(state)..., 1)
    ps = μβ0.policy_networks[player](x)[:,1]
    return ps
end

function value(μβ0::MuBetaZeroNeural, env::Environment, state::Array{Float32}, player::Int)::Float32
    x = reshape(state, size(state)..., 1)
    return μβ0.value_networks[player](x)[1]
end

function L2(x)
    return sum(abs2, x)
end

function policy_loss(μβ0::MuBetaZeroNeural, player::Int, c::Float32=0.001f0)
    m = μβ0.policy_networks[player]
    function loss(x,y)
        return Flux.crossentropy(m(x), y) + c * sum(L2, params(m))
    end
end

function value_loss(μβ0::MuBetaZeroNeural, player::Int, c::Float32=0.001f0)
    m = μβ0.value_networks[player]
    function loss(x,y)
        return Flux.mse(m(x), y) + c * sum(L2, params(m))
    end
end

function learn_transitions!(μβ0::MuBetaZeroNeural, env::Environment)
    ls = []
    for player in [1,2]
        n_trans = length(μβ0.transition_buffer[player])
        X = Array{Float32}(undef, size(env.current)..., n_trans)
        Y_ps = Array{Float32}(undef, env.n_actions, n_trans)
        Y_vs = Array{Float32}(undef, 1, n_trans)

        is = sample(1:n_trans, n_trans, replace=false)
        for (i,t) in zip(is, μβ0.transition_buffer[player])
            X[:,:,:,i] = t.s
            Y_ps[:,i] = t.ps
            Y_vs[1,i] = t.Q_est
        end

        policy_loss_f = policy_loss(μβ0, player, μβ0.c)
        value_loss_f = value_loss(μβ0, player, μβ0.c)

        p_loss = policy_loss_f(X, Y_ps)
        v_loss = value_loss_f(X, Y_vs)
        push!(ls, (p_loss, v_loss))

        Flux.Optimise.train!(policy_loss_f, params(μβ0.policy_networks[player]), [(X,Y_ps)], μβ0.opt)
        Flux.Optimise.train!(value_loss_f, params(μβ0.value_networks[player]), [(X, Y_vs)], μβ0.opt)
    end

    return ls
end


function play_game!(μβ0::MuBetaZeroNeural, env::Environment;
                    verbose=false, train=false, MCTS=false, N_MCTS=1000, MCTS_type=:rollout)
    reset!(env)
    if MCTS # reset tree
        reset_tree!(μβ0)
    end

    winner = 0
    done = false
    player = 1

    while !done
        t, winner, done, nextplayer = play!(μβ0, env, player, train=train, MCTS=MCTS, N_MCTS=N_MCTS, MCTS_type=MCTS_type)

        if train
            push!(μβ0.transition_buffer[t.player], t)
        end

        if verbose
            println("Decision Stats: player: $(t.player), action: $(t.a), Q_est: $(t.Q_est) vs Q: $(value(μβ0, env, t.s, player))")
            println(t.Q_ests)
            println(action_ps(μβ0, env, t.s, t.player))
            print_current(env)
            !done && println("State Stats: player: $nextplayer, Q = $(value(μβ0, env, env.current, nextplayer))")
            println()
        end

        player = nextplayer
    end

    return winner
end

function train!(μβ0::MuBetaZeroNeural, env::Environment,
                n_games::Int=10^5, batchsize=10;
                MCTS=false, N_MCTS=1000, MCTS_type=:rollout)

    winners = zeros(Int, n_games)
    p_loss_1 = []; v_loss_1 = []
    p_loss_2 = []; v_loss_2 = []

    ProgressMeter.@showprogress for n in 1:n_games
        winners[n] = play_game!(μβ0, env, train=true, MCTS=MCTS, N_MCTS=N_MCTS, MCTS_type=MCTS_type)
        if n % batchsize == 0
            losses = learn_transitions!(μβ0, env)
            flush_transition_buffer!(μβ0)

            push!(p_loss_1, losses[1][1]); push!(v_loss_1, losses[1][2]);
            push!(p_loss_2, losses[2][1]); push!(v_loss_2, losses[2][2]);
        end
    end

    return winners, p_loss_1, v_loss_1, p_loss_2, v_loss_2
end

env = ConnectFour()

Random.seed!(1)
policy_model = Chain(
    Conv((4,4), 2 => 8, sigmoid), # (3,4,8,:)
    Flux.flatten, # (96,:)
    Dense(96, 48, sigmoid),
    Dense(48, 7),
    Flux.softmax
)

value_model = Chain(
    Conv((4,4), 2 => 8, sigmoid), # (3,4,8,:)
    Flux.flatten, # (96,:)
    Dense(96, 48, relu),
    Dense(48, 1)
)

agent = MuBetaZeroNeural(policy_model, value_model)

winners, p_loss_1, v_loss_1, p_loss_2, v_loss_2 = train!(agent, env, 10^5, 10, MCTS=true, N_MCTS=100, MCTS_type=:value)

using Plots
plot(p_loss_1)
plot(v_loss_1)

s = reshape(reset!(env), size(env.current)..., 1)
ps = agent.policy_networks[1](s)
bar(ps)

m = agent.value_networks[2]
BSON.@save "value_nn_2.bson" m

Random.seed!(1)
play_game!(agent, env, verbose=true, train=false, MCTS=true, N_MCTS=100, MCTS_type=:value)

import BenchmarkTools

BenchmarkTools.@btime play_game!(agent, env, verbose=false, train=false, MCTS=false, N_MCTS=100, MCTS_type=:value)

play_against(agent, env, MCTS=true, MCTS_type=:value)

learn_transitions!(agent, env)
