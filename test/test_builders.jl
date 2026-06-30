# Graph builders: link_cut_tree(g) (rooted directed-tree form) and
# link_cut_tree(g, tree_edges) (explicit undirected edge list), checked for
# connectivity / enumeration against a brute-force model of the same edges.

@testset "builders" begin

    @testset "link_cut_tree(g) from a directed rooted forest" begin
        # two components: chain 1→2→3 (root 3) and chain 4→5 (root 5).
        g = Graphs.SimpleDiGraph(5)
        Graphs.add_edge!(g, 1, 2); Graphs.add_edge!(g, 2, 3)
        Graphs.add_edge!(g, 4, 5)
        edges = [edgekey(1, 2), edgekey(2, 3), edgekey(4, 5)]
        t = link_cut_tree(g)
        @test connectivity_matches(t, 5, Set(edges))
        @test Set(cc(t[1])) == Set([1, 2, 3])
        @test Set(cc(t[4])) == Set([4, 5])
        @test nv_cc(t[2]) == 3
    end

    @testset "link_cut_tree(g, tree_edges) matches the edge model" begin
        # build a star: center 1 linked to 2,3,4,5
        g = Graphs.star_graph(6)            # vertex 1 is the hub of 6 vertices
        es = collect(Graphs.edges(g))
        t = link_cut_tree(g, es)
        edges = Set(edgekey(src(e), dst(e)) for e in es)
        @test connectivity_matches(t, 6, edges)
        for v in 1:6
            @test Set(cc(t[v])) == ref_component(edges, 6, v)
        end
        # the recovered edge list of the single component equals the model edges
        r = find_root!(t[1]).vertex
        got = Set(edgekey(src(e), dst(e)) for e in get_connected_edge_list(t[r]))
        @test got == edges
    end

    @testset "builders accept EmptyAug via the aug kwarg" begin
        g = Graphs.path_graph(4)
        es = collect(Graphs.edges(g))
        t = link_cut_tree(g, es; aug = EmptyAug)
        @test eltype(t.nodes) == Union{Nothing, Node{Int, EmptyAug}}
        # connectivity still correct without the PathAug enumeration machinery
        @test connectivity_matches(t, 4, Set(edgekey(src(e), dst(e)) for e in es))
    end

    @testset "builders stay consistent after further link/cut/evert" begin
        rng = MersenneTwister(71)
        n = 14
        g = Graphs.path_graph(n)
        es = collect(Graphs.edges(g))
        t = link_cut_tree(g, es)
        # seed the model with the spanning path, then drive more random ops
        edges = Set(edgekey(src(e), dst(e)) for e in es)
        for _ in 1:800
            a = rand(rng, 1:n); b = rand(rng, 1:n); a == b && continue
            if rand(rng, Bool) && !isempty(edges)
                (x, y) = rand(rng, collect(edges)); delete!(edges, (x, y))
                evert!(t[x]); cut!(t[y])
            elseif !(b in ref_component(edges, n, a))
                push!(edges, edgekey(a, b)); evert!(t[a]); link!(t[a], t[b])
            end
        end
        @test connectivity_matches(t, n, edges)
        for v in 1:n
            @test Set(cc(t[v])) == ref_component(edges, n, v)
        end
    end
end
