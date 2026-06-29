# PopAug maintained subtree-sum augmentation.

@testset "popaug" begin

    @testset "set_pop! / singleton sums" begin
        t = pop_link_cut_tree(Graphs.path_graph(4), Graphs.Edge[], [2.0, 3.0, 5.0, 7.0])
        for (i, v) in enumerate((2.0, 3.0, 5.0, 7.0))
            @test subtree_pop(t[i]) == v          # isolated node: subtree = itself
        end
        set_pop!(t[1], 10.0)
        @test subtree_pop(t[1]) == 10.0
    end

    @testset "subtree_pop at root equals component total" begin
        rng = MersenneTwister(51)
        n = 16
        vals = Float64.(rand(rng, 1:20, n))
        t = pop_link_cut_tree(Graphs.path_graph(n), Graphs.Edge[], vals)
        edges = drive_random!(t, n, 1200, rng)
        for v in 1:n
            evert!(t[v])
            comp = ref_component(edges, n, v)
            @test subtree_pop(t[v]) ≈ sum(vals[u] for u in comp)
        end
    end

    @testset "subtree_pop matches brute force for every (root, vertex)" begin
        rng = MersenneTwister(52)
        n = 18
        vals = Float64.(rand(rng, 1:9, n))
        t = pop_link_cut_tree(Graphs.path_graph(n), Graphs.Edge[], vals)
        edges = drive_random!(t, n, 1500, rng)
        # spot-check several roots
        for root in 1:n
            evert!(t[root])
            ref = ref_subtree_pops(edges, n, root, vals)
            for v in keys(ref)
                @test subtree_pop(t[v]) ≈ ref[v]
            end
        end
    end

    @testset "builder with an explicit edge list initializes sums correctly" begin
        # path 1-2-3-4-5 built via edges; subtree pop rooted at 1 is a suffix sum
        vals = [1.0, 2.0, 3.0, 4.0, 5.0]
        g = Graphs.path_graph(5)
        t = pop_link_cut_tree(g, collect(Graphs.edges(g)), vals)
        evert!(t[1])
        @test subtree_pop(t[1]) == 15.0
        @test subtree_pop(t[2]) == 14.0
        @test subtree_pop(t[3]) == 12.0
        @test subtree_pop(t[5]) == 5.0
    end

    @testset "sums stay correct through interleaved link/cut/evert" begin
        rng = MersenneTwister(53)
        n = 14
        vals = Float64.(rand(rng, 1:7, n))
        t = pop_link_cut_tree(Graphs.path_graph(n), Graphs.Edge[], vals)
        # after every op, root a random component and verify one subtree pop
        function check(edges)
            isempty(edges) && return
            v = rand(rng, 1:n)
            evert!(t[v])
            ref = ref_subtree_pops(edges, n, v, vals)
            u = rand(collect(keys(ref)))
            @test subtree_pop(t[u]) ≈ ref[u]
        end
        drive_random!(t, n, 1500, rng; record = check)
    end
end
