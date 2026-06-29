# Structural correctness of the core link-cut operations, across all three
# augmentations, plus edge cases and error conditions.

@testset "structure" begin

    @testset "augmentation capability hierarchy + enforcement" begin
        @test EmptyAug <: AbstractAug
        @test PathAug{Int} <: PathCapable
        @test PopAug{Int} <: SubtreeSumCapable <: PathCapable   # pop implies path
        @test !(EmptyAug <: PathCapable)
        te = LinkCutTree{Int, EmptyAug}(3)
        tp = LinkCutTree{Int}(3)                                # PathAug
        tq = pop_link_cut_tree(Graphs.path_graph(3), Graphs.Edge[], [1.0,2.0,3.0])
        # capability-gated functions reject insufficient augmentations at dispatch
        @test_throws MethodError path_children(te[1])           # needs PathCapable
        @test_throws MethodError get_diameter(te[1])
        @test_throws MethodError subtree_pop(tp[1])             # needs SubtreeSumCapable
        # and accept sufficient ones (PopAug inherits the PathCapable methods)
        @test path_children(tp[1]) isa Any
        @test path_children(tq[1]) isa Any
        @test subtree_pop(tq[1]) == 1.0
    end

    @testset "EmptyAug payload is zero size and standard" begin
        nd = Node{Int, EmptyAug}(7)
        @test nd.vertex == 7
        @test nd.aug isa EmptyAug
        @test sizeof(EmptyAug) == 0
        t = LinkCutTree{Int, EmptyAug}(3)
        @test eltype(t.nodes) == Union{Nothing, Node{Int, EmptyAug}}
        for i in 1:3
            @test find_root!(t[i]).vertex == i      # singletons are their own roots
        end
    end

    @testset "isolated nodes are their own roots (each aug)" begin
        for build in (() -> LinkCutTree{Int, EmptyAug}(5),
                      () -> LinkCutTree{Int}(5),
                      () -> pop_link_cut_tree(Graphs.path_graph(5), Graphs.Edge[], ones(5)))
            t = build()
            for i in 1:5
                @test find_root!(t[i]).vertex == i
            end
        end
    end

    @testset "link/cut/evert on a known chain" begin
        t = LinkCutTree{Int}(4)
        link!(t[2], t[1]); link!(t[3], t[2]); link!(t[4], t[3])   # 1←2←3←4, root 1
        @test all(find_root!(t[v]).vertex == 1 for v in 1:4)
        evert!(t[4])                                              # re-root at 4
        @test all(find_root!(t[v]).vertex == 4 for v in 1:4)
        evert!(t[1]); cut!(t[3])                                  # split edge 2-3
        @test Set(cc(t[1])) == Set([1, 2])
        @test Set(cc(t[3])) == Set([3, 4])
        @test find_root!(t[1]).vertex != find_root!(t[4]).vertex
    end

    @testset "set_root! is evert!; evert! is idempotent for connectivity" begin
        t = LinkCutTree{Int}(3)
        link!(t[2], t[1]); link!(t[3], t[2])
        @test set_root! === evert!
        evert!(t[2]); r1 = find_root!(t[3]).vertex
        evert!(t[2]); r2 = find_root!(t[3]).vertex
        @test r1 == r2 == 2
    end

    @testset "error conditions" begin
        t = LinkCutTree{Int}(3)
        link!(t[2], t[1])
        @test_throws ArgumentError cut!(t[1])              # cutting a root
        @test_throws ArgumentError link!(t[2], t[3])       # linking a non-root
        link!(t[3], t[1])
        @test_throws ArgumentError link!(t[2], t[3])       # same represented tree
    end

    @testset "find_root! is stable under re-exposing different nodes" begin
        rng = MersenneTwister(11)
        t = LinkCutTree{Int}(12)
        edges = drive_random!(t, 12, 400, rng)
        for v in 1:12
            r = find_root!(t[v]).vertex
            # exposing other nodes must not change v's root
            for u in 1:12; find_root!(t[u]); end
            @test find_root!(t[v]).vertex == r
        end
        @test connectivity_matches(t, 12, edges)
    end

    @testset "all augmentations agree structurally on the same op stream" begin
        n = 20; nops = 1500; seed = 9090
        te = LinkCutTree{Int, EmptyAug}(n)
        tp = LinkCutTree{Int}(n)                                   # PathAug
        tq = pop_link_cut_tree(Graphs.path_graph(n), Graphs.Edge[], collect(1.0:n))
        ee = drive_random!(te, n, nops, MersenneTwister(seed))
        ep = drive_random!(tp, n, nops, MersenneTwister(seed))
        eq = drive_random!(tq, n, nops, MersenneTwister(seed))
        @test ee == ep == eq                                       # identical edge models
        for v in 1:n
            @test find_root!(te[v]).vertex == find_root!(tp[v]).vertex ==
                  find_root!(tq[v]).vertex
        end
        @test connectivity_matches(te, n, ee)
        @test connectivity_matches(tp, n, ep)
        @test connectivity_matches(tq, n, eq)
    end

    @testset "PathAug pathParent <-> pathChildren stay in sync" begin
        rng = MersenneTwister(7)
        n = 16
        t = LinkCutTree{Int}(n)
        function invariant(_)
            for c in 1:n
                pp = t[c].pathParent
                pp isa Node && @test t[c] in path_children(pp)
                for ch in path_children(t[c])
                    @test ch.pathParent === t[c]
                end
            end
        end
        drive_random!(t, n, 1200, rng; record = invariant)
    end
end
