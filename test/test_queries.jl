# Represented-tree queries (PathAug): cc / nv_cc / parents / findPath /
# get_connected_edge_list / get_farthest_node / get_diameter, vs brute force.

@testset "queries" begin

    @testset "cc / nv_cc enumerate the component" begin
        rng = MersenneTwister(31)
        n = 18
        t = LinkCutTree{Int}(n)
        edges = drive_random!(t, n, 1200, rng)
        for v in 1:n
            comp = ref_component(edges, n, v)
            @test Set(cc(t[v])) == comp
            @test nv_cc(t[v]) == length(comp)
        end
    end

    @testset "parents() matches a brute-force rooted parent array" begin
        rng = MersenneTwister(32)
        n = 15
        t = LinkCutTree{Int}(n)
        edges = drive_random!(t, n, 1000, rng)
        # parents() roots each component at whatever node it currently is rooted
        # at; re-root every component deterministically first so we can compare.
        roots = Dict{Int,Int}()
        for v in 1:n
            r = find_root!(t[v]).vertex
            roots[r] = r
        end
        p = parents(t)
        for v in 1:n
            r = find_root!(t[v]).vertex
            ref = ref_parents(edges, n, r)
            @test p[v] == ref[v]
        end
    end

    @testset "findPath returns the root→v path after expose" begin
        rng = MersenneTwister(33)
        n = 16
        t = LinkCutTree{Int}(n)
        edges = drive_random!(t, n, 1000, rng)
        for v in 1:n
            comp = collect(ref_component(edges, n, v))
            length(comp) < 2 && continue
            root = first(comp)
            evert!(t[root]); expose!(t[v])
            got = [nd.vertex for nd in findPath(t[v])]
            @test got == ref_path(edges, n, root, v)
        end
    end

    @testset "get_connected_edge_list recovers component edges" begin
        rng = MersenneTwister(34)
        n = 16
        t = LinkCutTree{Int}(n)
        edges = drive_random!(t, n, 1000, rng)
        # for each component (by root) the edge list equals the model's edges
        roots = unique(find_root!(t[v]).vertex for v in 1:n)
        for r in roots
            es = get_connected_edge_list(t[r])
            got = Set(edgekey(src(e), dst(e)) for e in es)
            comp = ref_component(edges, n, r)
            want = Set(e for e in edges if e[1] in comp)
            @test got == want
        end
    end

    @testset "get_diameter / get_farthest_node match double-BFS" begin
        rng = MersenneTwister(35)
        n = 20
        t = LinkCutTree{Int}(n)
        edges = drive_random!(t, n, 1500, rng)
        for v in 1:n
            @test get_diameter(t[v]) == ref_diameter(edges, n, v)
            # farthest node distance from a fixed root equals BFS max distance
            evert!(t[v])
            _, d = get_farthest_node(t[v])
            comp = ref_component(edges, n, v)
            @test d == maximum(ref_dists(edges, n, v)[u] for u in comp)
        end
    end

    @testset "single-vertex component edge cases" begin
        t = LinkCutTree{Int}(3)                  # all singletons
        @test cc(t[1]) == [1]
        @test nv_cc(t[1]) == 1
        @test get_diameter(t[1]) == 0
        @test isempty(get_connected_edge_list(t[1]))
        @test [nd.vertex for nd in findPath(t[1])] == [1]
    end
end
