using LinkCutTreesAugmented
using Test
using Random

const LCT = LinkCutTreesAugmented
import Graphs
import Graphs: src, dst

# Brute-force reference: an explicit set of undirected edges that always forms a
# forest over vertices 1:n. Connectivity is computed by BFS over the edge set.
edgekey(a, b) = (min(a, b), max(a, b))

function ref_adj(edges::Set{Tuple{Int,Int}}, n::Int)
    adj = [Int[] for _ in 1:n]
    for (a, b) in edges
        push!(adj[a], b); push!(adj[b], a)
    end
    adj
end

function ref_component(edges, n, v)
    adj = ref_adj(edges, n)
    seen = Set{Int}(); stack = [v]
    while !isempty(stack)
        u = pop!(stack); u in seen && continue
        push!(seen, u)
        for w in adj[u]; w in seen || push!(stack, w); end
    end
    seen
end

@testset "LinkCutTreesAugmented" begin

    @testset "EmptyAug is a zero-size payload (standard LCT)" begin
        n = Node{Int, EmptyAug}(7)
        @test n.vertex == 7
        @test n.aug isa EmptyAug
        @test sizeof(EmptyAug) == 0
    end

    @testset "basic link / find_root / cut / enumerate" begin
        t = LinkCutTree{Int}(5)            # defaults to PathAug
        for v in 1:4
            evert!(t[v]); link!(t[v], t[v+1])     # path 1-2-3-4-5
        end
        r = find_root!(t[1]).vertex
        @test all(find_root!(t[v]).vertex == r for v in 1:5)
        @test sort(cc(t[1])) == collect(1:5)
        @test nv_cc(t[3]) == 5

        evert!(t[1]); cut!(t[3])           # split edge 2-3
        @test sort(cc(t[1])) == [1, 2]
        @test sort(cc(t[3])) == [3, 4, 5]
        @test find_root!(t[1]).vertex != find_root!(t[5]).vertex
    end

    @testset "evert re-roots the represented tree" begin
        t = LinkCutTree{Int}(4)
        for v in 1:3
            evert!(t[v]); link!(t[v], t[v+1])
        end
        evert!(t[1]); @test find_root!(t[4]).vertex == 1
        evert!(t[4]); @test find_root!(t[1]).vertex == 4
    end

    @testset "get_connected_edge_list recovers the tree edges" begin
        t = LinkCutTree{Int}(5)
        for v in 1:4
            evert!(t[v]); link!(t[v], t[v+1])
        end
        es = get_connected_edge_list(t[1])
        got = Set(edgekey(src(e), dst(e)) for e in es)
        @test got == Set([(1,2), (2,3), (3,4), (4,5)])
    end

    @testset "parents / findPath / diameter on a known path" begin
        t = LinkCutTree{Int}(5)
        for v in 1:4
            evert!(t[v]); link!(t[v], t[v+1])    # path 1-2-3-4-5, rooted last evert at 4
        end
        evert!(t[1])                              # root at 1
        p = parents(t)
        @test p[1] == 1                           # root maps to itself
        @test p[2] == 1 && p[3] == 2 && p[4] == 3 && p[5] == 4
        @test sort([n.vertex for n in findPath(t[5])]) == collect(1:5)
        @test get_diameter(t[1]) == 4             # 4 edges across the path
    end

    @testset "PopAug subtree_pop matches brute force under random link/cut/evert" begin
        rng = MersenneTwister(424242)
        n = 14
        vals = Float64.(rand(rng, 1:9, n))
        g = Graphs.path_graph(n)            # only used for nv in the builder
        t = pop_link_cut_tree(g, Graphs.Edge[], vals)   # start as n singletons
        edges = Set{Tuple{Int,Int}}()

        # brute-force subtree pop of v when the component is rooted at `root`
        function bf_subtree(edges, n, root, v)
            adj = ref_adj(edges, n)
            # parent via BFS from root
            parent = fill(0, n); order = Int[]; seen = falses(n)
            q = [root]; seen[root] = true
            while !isempty(q)
                u = popfirst!(q); push!(order, u)
                for w in adj[u]; seen[w] || (seen[w]=true; parent[w]=u; push!(q,w)); end
            end
            sub = copy(vals)
            for u in reverse(order)           # leaves first
                parent[u] != 0 && (sub[parent[u]] += sub[u])
            end
            return sub[v]
        end

        for _ in 1:1200
            a = rand(rng, 1:n); b = rand(rng, 1:n); a == b && continue
            if rand(rng, Bool) && !isempty(edges)
                (x, y) = rand(rng, collect(edges)); delete!(edges, (x, y))
                evert!(t[x]); cut!(t[y])
            elseif !(b in ref_component(edges, n, a))
                push!(edges, edgekey(a, b)); evert!(t[a]); link!(t[a], t[b])
            end
            # query: pick a vertex and a root in its component, compare
            root = rand(rng, 1:n)
            evert!(t[root])
            for v in collect(ref_component(edges, n, root))
                @test subtree_pop(t[v]) ≈ bf_subtree(edges, n, root, v)
            end
        end
    end

    @testset "random ops match brute-force reference; PathAug invariant holds" begin
        rng = MersenneTwister(20260628)
        n = 16
        t = LinkCutTree{Int}(n)
        edges = Set{Tuple{Int,Int}}()

        check_invariant() = for c in 1:n
            pp = t[c].pathParent
            pp isa Node && @test t[c] in LCT.path_children(pp)
            for ch in LCT.path_children(t[c])
                @test ch.pathParent === t[c]
            end
        end

        for _ in 1:1500
            a = rand(rng, 1:n); b = rand(rng, 1:n)
            a == b && continue
            if rand(rng, Bool) && !isempty(edges)
                # CUT a random existing edge
                (x, y) = rand(rng, collect(edges))
                delete!(edges, (x, y))
                evert!(t[x]); cut!(t[y])          # after rooting at x, y is x's child
            else
                # LINK if a and b are in different components
                if !(b in ref_component(edges, n, a))
                    push!(edges, edgekey(a, b))
                    evert!(t[a]); link!(t[a], t[b])
                end
            end
            @test (b in ref_component(edges, n, a)) ==
                  (find_root!(t[a]).vertex == find_root!(t[b]).vertex)
        end
        check_invariant()

        # full component enumeration cross-check
        for v in 1:n
            @test Set(cc(t[v])) == ref_component(edges, n, v)
            @test nv_cc(t[v]) == length(ref_component(edges, n, v))
        end
    end
end
