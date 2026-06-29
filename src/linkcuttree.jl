# ---------------------------------------------------------------------------
# Link-cut tree: container, structural operations, builders, and (PathAug-only)
# represented-tree enumerators.
# ---------------------------------------------------------------------------

"""
    LinkCutTree{T,A}

A forest of link-cut trees over vertices `1:n`. `nodes[i]` is the `Node` for
vertex `i`. `A` selects the augmentation (default [`PathAug`](@ref)).
"""
struct LinkCutTree{T<:Integer, A}
    nodes::Vector{Union{Node{T,A}, Nothing}}

    function LinkCutTree{T,A}(s::Integer) where {T<:Integer, A}
        nodes = Vector{Union{Node{T,A}, Nothing}}(undef, s)
        for i in 1:s
            nodes[i] = Node{T,A}(convert(T, i))
        end
        return new{T,A}(nodes)
    end

    LinkCutTree{T,A}(nodes::Vector{Union{Node{T,A}, Nothing}}) where {T<:Integer, A} =
        new{T,A}(nodes)
end

LinkCutTree{T}(s::Integer) where {T<:Integer} = LinkCutTree{T, PathAug{T}}(s)

Base.getindex(lct::LinkCutTree, i::Integer) = lct.nodes[i]
Base.length(lct::LinkCutTree) = length(lct.nodes)

# ---------------------------------------------------------------------------
# Structural operations
# ---------------------------------------------------------------------------

"""
    replaceRightSubtree!(n, r=nothing)

Replace the right (deeper-on-preferred-path) splay child of `n` with `r`. The
displaced child becomes a path-child of `n`; `r` (if given) stops being one.
All `pathParent` writes go through [`set_path_parent!`](@ref).
"""
function replaceRightSubtree!(n::Node, r::Union{Node, Nothing}=nothing)
    c = n.children[2]
    if c isa Node
        c.parent = nothing
        set_path_parent!(c, n)        # detach c into the virtual tree under n
        on_virtual_attach!(n, c)      # c is now a virtual child of n
    end
    setRight!(n, r)
    if r isa Node
        set_path_parent!(r, nothing)  # r's old pathParent === n ⇒ removed from n's set
        on_virtual_detach!(n, r)      # r left the virtual tree (now real child)
    end
    update_aug!(n)                    # n's children/virtual contribution changed
end

"""
    expose!(n)

Bring `n` to the root of its tree's auxiliary structure so the preferred path
runs from the represented root down to `n`, with `n` deepest.
"""
function expose!(n::Node)
    splay!(n)
    replaceRightSubtree!(n)
    while n.pathParent isa Node
        p = n.pathParent
        splay!(p)
        replaceRightSubtree!(p, n)
        splay!(n)
    end
end

"""
    link!(u, v)

Make represented-root `u` a child of `v` (in a different represented tree).
"""
function link!(u::Node, v::Node)
    expose!(u)
    if u.children[1] isa Node
        throw(ArgumentError("u must be the root of its represented tree to link."))
    end
    expose!(v)
    if u.parent isa Node || u.pathParent isa Node
        throw(ArgumentError("Can't link two nodes in the same represented tree"))
    end
    set_path_parent!(u, v)
    on_virtual_attach!(v, u)          # u becomes a virtual child of v
    update_aug!(v)
end

"""
    cut!(u)

Detach `u` from its parent in the represented tree. `u` must not be the root.
"""
function cut!(u::Node)
    expose!(u)
    if !(u.children[1] isa Node)
        throw(ArgumentError("can't cut the root of the represented tree."))
    end
    v = u.children[1]
    v.parent = nothing
    setLeft!(u, nothing)
    update_aug!(u)                    # u lost its left (ancestor) subtree
end

"Make `u` the root of its represented tree."
function evert!(u::Node)
    expose!(u)
    u.reversed = true
end

const set_root! = evert!

"Return the root node of `u`'s represented tree."
function find_root!(u::Node)
    expose!(u)
    while u.children[1] !== nothing
        u = u.children[1]
    end
    return u
end

# ---------------------------------------------------------------------------
# Builders from Graphs.jl graphs
# ---------------------------------------------------------------------------

# Resolve a user-supplied augmentation argument to a concrete payload type for
# vertex-label type `T`. `PathAug` (the UnionAll) becomes `PathAug{T}`; concrete
# payloads (e.g. `EmptyAug`) are passed through.
_resolve_aug(::Type{T}, ::Type{PathAug}) where {T} = PathAug{T}
_resolve_aug(::Type{T}, ::Type{A}) where {T,A} = A

"""
    link_cut_tree(g; aug=PathAug)

Build a link-cut tree from a rooted, directed tree/forest `g`: an edge `c → n`
(i.e. `n ∈ neighbors(g, ...)` with `c` its in-neighbour here) links child `c`
under parent `n`.
"""
function link_cut_tree(g::AG; aug::Type=PathAug) where {U, AG<:Graphs.AbstractGraph{U}}
    A = _resolve_aug(U, aug)
    tree = LinkCutTree{U, A}(Graphs.nv(g))
    for n in Graphs.vertices(g)
        for c in Graphs.neighbors(g, n)
            link!(tree.nodes[c], tree.nodes[n])
        end
    end
    return tree
end

"""
    link_cut_tree(g, tree_edges; aug=PathAug)

Build a link-cut tree on `nv(g)` vertices from an explicit undirected edge list,
everting each source so the link is always legal.
"""
function link_cut_tree(g, tree_edges::Vector; aug::Type=PathAug)
    A = _resolve_aug(Int, aug)
    tree = LinkCutTree{Int, A}(Graphs.nv(g))
    for e in tree_edges
        evert!(tree.nodes[Graphs.src(e)])
        link!(tree.nodes[Graphs.src(e)], tree.nodes[Graphs.dst(e)])
    end
    return tree
end

# ---------------------------------------------------------------------------
# Represented-tree enumerators (require PathAug)
# ---------------------------------------------------------------------------

"Number of vertices in the represented tree containing `node`."
function nv_cc(node::Node, start::Bool=true)
    start && expose!(node)
    count = 1
    for ii in 1:2
        c = node.children[ii]
        c !== nothing && (count += nv_cc(c, false))
    end
    for n in path_children(node)
        count += nv_cc(n, false)
    end
    return count
end

"Vertices in the represented tree containing `node`, as a vector of labels."
function cc(node::Node{T,A}, start::Bool=true,
            vec::Vector{T}=Vector{T}(undef, 0)) where {T,A}
    start && expose!(node)
    push!(vec, node.vertex)
    for ii in 1:2
        c = node.children[ii]
        c !== nothing && cc(c, false, vec)
    end
    for n in path_children(node)
        cc(n, false, vec)
    end
    return vec
end

# internal worker for get_connected_edge_list
function get_connected_edge_list!(edges::Vector{<:Graphs.AbstractEdge},
                                  node::Union{Node, Nothing},
                                  linking::Node, reversed::Bool=false)
    node === nothing && return linking
    reversed ⊻= node.reversed
    lc, rc = reversed ? (2, 1) : (1, 2)
    linking = get_connected_edge_list!(edges, node.children[lc], linking, reversed)
    push!(edges, Graphs.Edge(node.vertex, linking.vertex))
    linking = node
    linking = get_connected_edge_list!(edges, node.children[rc], linking, reversed)
    for n in path_children(node)
        get_connected_edge_list!(edges, n, node)
    end
    return linking
end

"Edge list of the represented tree rooted at `root` (roots the tree at `root`)."
function get_connected_edge_list(root::Node)
    edges = Vector{Graphs.Edge}(undef, 0)
    evert!(root)
    lc, rc = root.reversed ? (2, 1) : (1, 2)
    get_connected_edge_list!(edges, root.children[rc], root, root.reversed)
    for n in path_children(root)
        get_connected_edge_list!(edges, n, root)
    end
    return edges
end
