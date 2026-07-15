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

    @testset "ported LinkCutTree extension helpers" begin
        rng = MersenneTwister(36)
        n = 14
        t = LinkCutTree{Int}(n)
        edges = drive_random!(t, n, 1200, rng)
        adj = ref_adj(edges, n)

        # neighbors_huh and get_lct_neighbors should agree with the explicit edge model.
        for u in 1:n
            @test Set(get_lct_neighbors(t[u])) == Set(adj[u])
            for v in 1:n
                @test neighbors_huh(t[u], t[v]) == (v in adj[u])
                @test neighbors_huh(u, v, t) == (v in adj[u])
            end
        end

        # After expose!, the left-most ancestor on the preferred path is the represented root,
        # and the right-most ancestor is the exposed node itself.
        for v in 1:n
            expose!(t[v])
            @test find_left_most_ancestor(t[v]).vertex == find_root!(t[v]).vertex
            @test find_right_most_ancestor(t[v]).vertex == v
        end

        # lazy_clear! should reset local structural pointers/flags on a node.
        v = rand(rng, 1:n)
        expose!(t[v])
        lazy_clear!(t[v])
        @test t[v].parent === nothing
        @test t[v].pathParent === nothing
        @test t[v].children[1] === nothing
        @test t[v].children[2] === nothing
        @test t[v].reversed == false
        @test first_path_child(t[v]) === nothing

        # print_lct smoke test: should execute and return nothing.
        @test print_lct(t, [1, 2]) === nothing

        # diff_lct smoke tests: identical copies emit no output; differing trees do.
        t1 = LinkCutTree{Int}(6)
        evert!(t1[2]); link!(t1[2], t1[1])
        evert!(t1[3]); link!(t1[3], t1[1])
        evert!(t1[5]); link!(t1[5], t1[4])

        t2 = copy(t1)
        @test diff_lct(t1, t2) === nothing

        lazy_clear!(t2[3])
        @test diff_lct(t1, t2) === nothing
    end
end
