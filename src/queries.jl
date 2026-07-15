# ---------------------------------------------------------------------------
# Higher-level read-only queries over the represented trees (require PathAug,
# since they enumerate whole represented trees).
# ---------------------------------------------------------------------------

"""
    parents(f::LinkCutTree) -> Vector

Vector `p` where `p[i]` is the represented-tree parent label of vertex `i`
(a root maps to itself).
"""
function parents(f::LinkCutTree{T,A}) where {T,A}
    nodes = copy(f.nodes)
    p = Vector{T}(undef, length(f.nodes))
    visited = falses(length(nodes))

    pos = 1
    while pos <= length(nodes)
        while pos <= length(nodes) && visited[pos]
            pos += 1
        end
        pos > length(nodes) && break
        r = findSplayRoot(nodes[pos])
        s = traverseSubtree(r)
        if r.pathParent isa Node
            p[s[1].vertex] = r.pathParent.vertex
        else
            p[s[1].vertex] = s[1].vertex
        end
        for i in 2:lastindex(s)
            p[s[i].vertex] = s[i-1].vertex
        end
        for n in s
            visited[n.vertex] = true
        end
    end
    return p
end

"Vector of nodes on the current preferred path/subtree containing `n`, in depth order."
findPath(n::Node) = traverseSubtree(findSplayRoot(n))

"As [`findPath`](@ref) but returns vertex labels, for the tree containing vertex `i`."
function findPath(i::Integer, t::LinkCutTree)
    A = traverseSubtree(findSplayRoot(t.nodes[i]))
    return [a.vertex for a in A]
end

# internal worker for get_farthest_node
function get_farthest_node(node::Union{Node, Nothing}, linking::Node,
                           deepest_node::Node=linking, deepest_dist::Int64=0,
                           cur_dist::Int64=0; reversed::Bool=false)
    if node === nothing
        return linking, cur_dist, deepest_node, deepest_dist
    end
    reversed ⊻= node.reversed
    lc, rc = reversed ? (2, 1) : (1, 2)

    linking, cur_dist, dn, dd = get_farthest_node(node.children[lc], linking,
        deepest_node, deepest_dist, cur_dist, reversed=reversed)
    cur_dist += 1
    linking = node
    if cur_dist > deepest_dist
        deepest_node = node
        deepest_dist = cur_dist
    end
    if dd > deepest_dist
        deepest_node = dn
        deepest_dist = dd
    end

    n = first_path_child(node)
    while n !== nothing
        _, _, dn, dd = get_farthest_node(n, node, deepest_node, deepest_dist, cur_dist)
        if dd > deepest_dist
            deepest_node = dn
            deepest_dist = dd
        end
        n = next_path_sibling(n)
    end

    linking, cur_dist, dn, dd = get_farthest_node(node.children[rc], linking,
        deepest_node, deepest_dist, cur_dist, reversed=reversed)
    if dd > deepest_dist
        deepest_node = dn
        deepest_dist = dd
    end

    return linking, cur_dist, deepest_node, deepest_dist
end

"""
    get_farthest_node(root) -> (node, distance)

Root the represented tree at `root` (via `evert!`) and return the node farthest
from it (in edges) together with that distance, found by a depth-first walk of the
whole represented tree. Used as one endpoint sweep of [`get_diameter`](@ref).
"""
function get_farthest_node(root::Node{T,A}) where {T, A<:PathCapable}
    evert!(root)
    lc, rc = root.reversed ? (2, 1) : (1, 2)
    _, _, node, dist = get_farthest_node(root.children[rc], root, reversed=root.reversed)
    n = first_path_child(root)
    while n !== nothing
        _, _, fn, d = get_farthest_node(n, root)
        if d > dist
            dist = d
            node = fn
        end
        n = next_path_sibling(n)
    end
    return node, dist
end

"Diameter (in edges) of the represented tree containing `root`."
function get_diameter(root::Node{T,A}) where {T, A<:PathCapable}
    farthest_node, _ = get_farthest_node(root)
    _, diameter = get_farthest_node(farthest_node)
    evert!(root)
    return diameter
end

"""
    lazy_clear!(node)

Dangerous local-only reset helper used by some downstream algorithms that
re-link a detached subgraph immediately afterward. This clears structural
pointers on `node` without repairing global consistency.
"""
function lazy_clear!(node::Union{Node, Nothing})
    node === nothing && return nothing
    node.parent = nothing
    node.children[1] = nothing
    node.children[2] = nothing
    node.reversed = false
    node.pathParent = nothing
    if hasproperty(node.aug, :firstChild)
        node.aug.firstChild = nothing
    end
    if hasproperty(node.aug, :nextSib)
        node.aug.nextSib = nothing
    end
    if hasproperty(node.aug, :prevSib)
        node.aug.prevSib = nothing
    end
    return nothing
end

"Right-most represented-path ancestor reachable through splay right edges."
function find_right_most_ancestor(node::Node, reversed::Bool=false)
    reversed ⊻= node.reversed
    lc, rc = reversed ? (2, 1) : (1, 2)
    if node.children[rc] === nothing
        return node
    end
    return find_right_most_ancestor(node.children[rc], reversed)
end

"Left-most represented-path ancestor reachable through splay left edges."
function find_left_most_ancestor(node::Node, reversed::Bool=false)
    reversed ⊻= node.reversed
    lc, rc = reversed ? (2, 1) : (1, 2)
    if node.children[lc] === nothing
        return node
    end
    return find_left_most_ancestor(node.children[lc], reversed)
end

"Return represented-tree neighbors of `node` as vertex labels."
function get_lct_neighbors(node::Node{T,A}) where {T, A<:PathCapable}
    neighbors = Vector{T}(undef, 0)
    expose!(node)

    lc, rc = node.reversed ? (2, 1) : (1, 2)
    if node.children[lc] !== nothing
        shallow_ngbr = find_right_most_ancestor(node.children[lc], node.reversed)
        push!(neighbors, shallow_ngbr.vertex)
    elseif node.pathParent !== nothing
        push!(neighbors, node.pathParent.vertex)
    end

    if node.children[rc] !== nothing
        deep_ngbr = find_left_most_ancestor(node.children[rc], node.reversed)
        push!(neighbors, deep_ngbr.vertex)
    end

    n = first_path_child(node)
    while n !== nothing
        path_ngbr = find_left_most_ancestor(n)
        push!(neighbors, path_ngbr.vertex)
        n = next_path_sibling(n)
    end

    return neighbors
end

"Whether `u` and `v` are represented-tree neighbors in the same component."
function neighbors_huh(u::Node{T,A}, v::Node{T,A})::Bool where {T, A<:PathCapable}
    expose!(u)
    lc, rc = u.reversed ? (2, 1) : (1, 2)

    if u.children[lc] !== nothing
        shallow_ngbr = find_right_most_ancestor(u.children[lc], u.reversed)
        shallow_ngbr == v && return true
    elseif u.pathParent !== nothing
        u.pathParent == v && return true
    end

    if u.children[rc] !== nothing
        deep_ngbr = find_left_most_ancestor(u.children[rc], u.reversed)
        deep_ngbr == v && return true
    end

    n = first_path_child(u)
    while n !== nothing
        path_ngbr = find_left_most_ancestor(n)
        path_ngbr == v && return true
        n = next_path_sibling(n)
    end
    return false
end

@inline function neighbors_huh(u::T, v::T, lct::LinkCutTree{T,A})::Bool where {T<:Integer, A<:PathCapable}
    return neighbors_huh(lct.nodes[u], lct.nodes[v])
end

@inline function _fmt_node_ref(n::Union{Node, Nothing})
    return n === nothing ? "n" : n.vertex
end

"Print compact structural state for each requested node index in an LCT."
function print_lct(lct::LinkCutTree{T,A}, nodes_to_print::AbstractVector{<:Integer}=collect(1:length(lct.nodes))) where {T, A<:PathCapable}
    for ii in nodes_to_print
        node = lct.nodes[ii]
        lc, rc = node.reversed ? (2, 1) : (1, 2)
        lc_node = node.children[lc]
        rc_node = node.children[rc]
        pp = node.pathParent
        p = node.parent
        pc = T[]
        n = first_path_child(node)
        while n !== nothing
            push!(pc, n.vertex)
            n = next_path_sibling(n)
        end

        println(node.vertex, " ", node.reversed, " (l, r, p): ", _fmt_node_ref(lc_node), " ",
                _fmt_node_ref(rc_node), " ", _fmt_node_ref(p), " path p/c: ",
                _fmt_node_ref(pp), " ", pc)
    end
    return nothing
end

"Print per-node differences between two link-cut forests with the same size." 
function diff_lct(lct1::LinkCutTree{T,A}, lct2::LinkCutTree{T,A}) where {T, A<:PathCapable}
    if length(lct1.nodes) != length(lct2.nodes)
        println("LCTs have different number of nodes: ", length(lct1.nodes), " vs ", length(lct2.nodes))
        return nothing
    end

    for ii in 1:length(lct1.nodes)
        node1 = lct1.nodes[ii]
        node2 = lct2.nodes[ii]

        lc, rc = node1.reversed ? (2, 1) : (1, 2)
        lc1 = _fmt_node_ref(node1.children[lc])
        rc1 = _fmt_node_ref(node1.children[rc])
        pp1 = _fmt_node_ref(node1.pathParent)
        p1 = _fmt_node_ref(node1.parent)
        pc1 = T[]
        n1 = first_path_child(node1)
        while n1 !== nothing
            push!(pc1, n1.vertex)
            n1 = next_path_sibling(n1)
        end

        lc, rc = node2.reversed ? (2, 1) : (1, 2)
        lc2 = _fmt_node_ref(node2.children[lc])
        rc2 = _fmt_node_ref(node2.children[rc])
        pp2 = _fmt_node_ref(node2.pathParent)
        p2 = _fmt_node_ref(node2.parent)
        pc2 = T[]
        n2 = first_path_child(node2)
        while n2 !== nothing
            push!(pc2, n2.vertex)
            n2 = next_path_sibling(n2)
        end

        sort!(pc1)
        sort!(pc2)
        if lc1 == lc2 && rc1 == rc2 && p1 == p2 && pp1 == pp2 && pc1 == pc2
            continue
        end

        println(node1.vertex, " ", node1.reversed, " (l, r, p): ", lc1, " ", rc1, " ", p1,
                " path p/c: ", pp1, " ", pc1)
        println(node2.vertex, " ", node2.reversed, " (l, r, p): ", lc2, " ", rc2, " ", p2,
                " path p/c: ", pp2, " ", pc2)
        println()
    end
    return nothing
end
