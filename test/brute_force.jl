# Shared brute-force reference model used across the test files.
#
# The model is an explicit set of undirected edges that always forms a forest
# over vertices 1:n. Because every reference query is computed purely from the
# edge set (never from the link-cut tree), the same seeded op sequence yields the
# same edges regardless of the augmentation under test — which lets us check that
# all augmentations agree structurally.

edgekey(a, b) = (min(a, b), max(a, b))

function ref_adj(edges, n::Int)
    adj = [Int[] for _ in 1:n]
    for (a, b) in edges
        push!(adj[a], b); push!(adj[b], a)
    end
    adj
end

"Connected component (set of vertices) of `v` in the edge-set forest."
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

"Parent array of `v`'s component rooted at `root` (root's parent = root)."
function ref_parents(edges, n, root)
    adj = ref_adj(edges, n)
    parent = fill(0, n); parent[root] = root
    seen = falses(n); seen[root] = true; q = [root]
    while !isempty(q)
        u = popfirst!(q)
        for w in adj[u]
            seen[w] || (seen[w] = true; parent[w] = u; push!(q, w))
        end
    end
    return parent
end

"Vertices on the path root → v in the component (inclusive), in depth order."
function ref_path(edges, n, root, v)
    parent = ref_parents(edges, n, root)
    path = Int[v]
    while path[end] != root
        push!(path, parent[path[end]])
    end
    return reverse(path)         # root first
end

"BFS distances from `s` over the edge-set component."
function ref_dists(edges, n, s)
    adj = ref_adj(edges, n)
    dist = fill(-1, n); dist[s] = 0; q = [s]
    while !isempty(q)
        u = popfirst!(q)
        for w in adj[u]; dist[w] == -1 && (dist[w] = dist[u] + 1; push!(q, w)); end
    end
    return dist
end

"Diameter (in edges) of `v`'s component (double-BFS)."
function ref_diameter(edges, n, v)
    comp = collect(ref_component(edges, n, v))
    d1 = ref_dists(edges, n, v)
    a = comp[argmax([d1[u] for u in comp])]
    d2 = ref_dists(edges, n, a)
    return maximum(d2[u] for u in comp)
end

"Subtree population of every vertex when `root`-rooted, given per-vertex `vals`."
function ref_subtree_pops(edges, n, root, vals)
    parent = ref_parents(edges, n, root)
    comp = ref_component(edges, n, root)
    # order vertices by depth (BFS order) so we can fold leaves up
    order = Int[]; seen = falses(n); seen[root] = true; q = [root]
    adj = ref_adj(edges, n)
    while !isempty(q)
        u = popfirst!(q); push!(order, u)
        for w in adj[u]; seen[w] || (seen[w] = true; push!(q, w)); end
    end
    sub = Dict{Int,Float64}(u => Float64(vals[u]) for u in comp)
    for u in reverse(order)
        u == root && continue
        sub[parent[u]] += sub[u]
    end
    return sub
end

# Drive a random link/cut sequence on an LCT `t`, keeping the edge model in sync.
# Returns the final edge set. `record` (if given) is called as record(edges)
# after each op, for invariant checks.
function drive_random!(t, n, nops, rng; record=nothing)
    edges = Set{Tuple{Int,Int}}()
    for _ in 1:nops
        a = rand(rng, 1:n); b = rand(rng, 1:n); a == b && continue
        if rand(rng, Bool) && !isempty(edges)
            (x, y) = rand(rng, collect(edges)); delete!(edges, (x, y))
            evert!(t[x]); cut!(t[y])
        elseif !(b in ref_component(edges, n, a))
            push!(edges, edgekey(a, b)); evert!(t[a]); link!(t[a], t[b])
        end
        record === nothing || record(edges)
    end
    return edges
end

# Whole-component connectivity check of an LCT vs the edge model (uses find_root!,
# so it works for every augmentation including EmptyAug).
function connectivity_matches(t, n, edges)
    for a in 1:n, b in 1:n
        same_model = b in ref_component(edges, n, a)
        same_lct = find_root!(t[a]).vertex == find_root!(t[b]).vertex
        same_model == same_lct || return false
    end
    return true
end
