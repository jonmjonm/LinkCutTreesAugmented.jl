# Documentation-driven tests: each testset pins a specific claim made in a
# docstring, so the documented contract can't silently drift from the code.

@testset "docs" begin

    @testset "Node{T,A}(vertex) builds an isolated singleton (constructor docstring)" begin
        nd = Node{Int, EmptyAug}(7)
        @test nd.vertex == 7
        @test nd.parent === nothing          # no parent
        @test nd.pathParent === nothing      # no path-parent
        @test length(nd.children) == 2 && all(c === nothing for c in nd.children)
        @test nd.reversed == false           # no pending reversal
        @test nd.aug isa EmptyAug            # fresh payload from new_aug
    end

    @testset "Node(vertex) defaults to the PathAug augmentation (docstring)" begin
        nd = Node(9)
        @test nd.vertex == 9
        @test nd.aug isa PathAug{Int}
        # new_aug starts PathAug in its identity (empty) state
        @test nd.aug.firstChild === nothing
        @test first_path_child(nd) === nothing
    end

    @testset "link_cut_tree(g) reads edges parent → child (corrected docstring)" begin
        # Edges point from parent to child: for n→c, child c is linked under
        # parent n. So in the directed chain 1→2→3→4 vertex 1 is the root and 4
        # the deepest leaf (NOT the reverse).
        g = Graphs.SimpleDiGraph(4)
        Graphs.add_edge!(g, 1, 2)
        Graphs.add_edge!(g, 2, 3)
        Graphs.add_edge!(g, 3, 4)
        t = link_cut_tree(g)
        @test all(find_root!(t[v]).vertex == 1 for v in 1:4)   # source 1 is the root
        # parents() reconstructs the rooted structure: 1↤2↤3↤4
        @test parents(t) == [1, 1, 2, 3]

        # A directed out-star 1→{2,3,4}: center 1 is parent of every leaf.
        h = Graphs.SimpleDiGraph(4)
        Graphs.add_edge!(h, 1, 2)
        Graphs.add_edge!(h, 1, 3)
        Graphs.add_edge!(h, 1, 4)
        s = link_cut_tree(h)
        @test all(find_root!(s[v]).vertex == 1 for v in 1:4)
        @test parents(s) == [1, 1, 1, 1]
    end

    @testset "traverseSubtree honours the order argument (docstring)" begin
        # one preferred path 1-2-3-4-5 so the whole component is a single splay tree
        t = LinkCutTree{Int}(5)
        for i in 2:5
            link!(t[i], t[i-1])
        end
        evert!(t[1]); expose!(t[5])
        r = LCT.findSplayRoot(t[5])

        ino = LCT.traverseSubtree(r, "in-order")
        pre = LCT.traverseSubtree(r, "pre-order")
        pos = LCT.traverseSubtree(r, "post-order")

        # in-order honours lazy reversal and yields represented depth order
        @test [x.vertex for x in ino] == [1, 2, 3, 4, 5]
        @test LCT.traverseSubtree(r) == ino                   # default is in-order
        # every order visits exactly the same node set
        labels(v) = Set(x.vertex for x in v)
        @test labels(pre) == labels(ino) == labels(pos) == Set(1:5)
        @test length(pre) == length(pos) == 5
        # unknown order is rejected
        @test_throws ArgumentError LCT.traverseSubtree(r, "sideways")
    end

    @testset "findPath(i, t) returns the path's vertex labels (docstring)" begin
        t = LinkCutTree{Int}(5)
        for i in 2:5
            link!(t[i], t[i-1])
        end
        evert!(t[1]); expose!(t[5])
        @test findPath(5, t) == [nd.vertex for nd in findPath(t[5])]
        @test findPath(5, t) == [1, 2, 3, 4, 5]
    end
end
