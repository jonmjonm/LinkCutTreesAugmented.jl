# Larger randomized stress for all three augmentations.

@testset "stress" begin

    @testset "EmptyAug connectivity over a long op stream" begin
        rng = MersenneTwister(8001)
        n = 120
        t = LinkCutTree{Int, EmptyAug}(n)
        edges = drive_random!(t, n, 6000, rng)
        @test connectivity_matches(t, n, edges)
    end

    @testset "PathAug enumeration over a long op stream" begin
        rng = MersenneTwister(8002)
        n = 100
        t = LinkCutTree{Int}(n)
        edges = drive_random!(t, n, 5000, rng)
        for v in 1:n
            @test Set(cc(t[v])) == ref_component(edges, n, v)
        end
        @test connectivity_matches(t, n, edges)
    end

    @testset "PopAug subtree sums over a long op stream" begin
        rng = MersenneTwister(8003)
        n = 100
        vals = Float64.(rand(rng, 1:50, n))
        t = pop_link_cut_tree(Graphs.path_graph(n), Graphs.Edge[], vals)
        edges = drive_random!(t, n, 5000, rng)
        # check a sample of (root, vertex) subtree pops
        for _ in 1:200
            root = rand(rng, 1:n)
            evert!(t[root])
            ref = ref_subtree_pops(edges, n, root, vals)
            v = rand(collect(keys(ref)))
            @test subtree_pop(t[v]) ≈ ref[v]
        end
    end

    @testset "deterministic: identical seed ⇒ identical structure" begin
        n = 40; nops = 2000
        t1 = LinkCutTree{Int}(n); e1 = drive_random!(t1, n, nops, MersenneTwister(4321))
        t2 = LinkCutTree{Int}(n); e2 = drive_random!(t2, n, nops, MersenneTwister(4321))
        @test e1 == e2
        for v in 1:n
            @test find_root!(t1[v]).vertex == find_root!(t2[v]).vertex
            @test Set(cc(t1[v])) == Set(cc(t2[v]))
        end
    end
end
