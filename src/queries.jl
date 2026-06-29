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

    linking, cur_dist, dn, dd = get_farthest_node(getchild(node, lc), linking,
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

    for n in path_children(node)
        _, _, dn, dd = get_farthest_node(n, node, deepest_node, deepest_dist, cur_dist)
        if dd > deepest_dist
            deepest_node = dn
            deepest_dist = dd
        end
    end

    linking, cur_dist, dn, dd = get_farthest_node(getchild(node, rc), linking,
        deepest_node, deepest_dist, cur_dist, reversed=reversed)
    if dd > deepest_dist
        deepest_node = dn
        deepest_dist = dd
    end

    return linking, cur_dist, deepest_node, deepest_dist
end

"BFS-like query on the represented tree returning the node farthest from `root` and its distance."
function get_farthest_node(root::Node)
    evert!(root)
    lc, rc = root.reversed ? (2, 1) : (1, 2)
    _, _, node, dist = get_farthest_node(getchild(root, rc), root, reversed=root.reversed)
    for n in path_children(root)
        _, _, fn, d = get_farthest_node(n, root)
        if d > dist
            dist = d
            node = fn
        end
    end
    return node, dist
end

"Diameter (in edges) of the represented tree containing `root`."
function get_diameter(root::Node)
    farthest_node, _ = get_farthest_node(root)
    _, diameter = get_farthest_node(farthest_node)
    evert!(root)
    return diameter
end
