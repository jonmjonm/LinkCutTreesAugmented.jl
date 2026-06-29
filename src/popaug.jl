# ---------------------------------------------------------------------------
# PopAug — a maintained subtree-sum augmentation (Option B).
#
# Each node carries, besides the PathAug-style path-children set:
#   val  : this vertex's own weight (e.g. population)
#   sum  : total weight of this node's *represented subtree*, including the
#          subtrees that hang off via path-children (the "virtual" subtrees)
#   vir  : sum of the `sum`s of this node's virtual (path-) children
#
# Invariant maintained by the hooks:
#   x.sum == x.val + x.vir + (left splay child).sum + (right splay child).sum
#
# With this, the population of v's represented subtree (when the tree is rooted
# at the current root) is read in O(log n) by `subtree_pop`, replacing an O(n)
# whole-tree traversal + per-call Dict.
# ---------------------------------------------------------------------------

mutable struct PopAug{T}
    pathChildren::Set{Node{T, PopAug{T}}}
    val::Float64
    sum::Float64
    vir::Float64
end

new_aug(::Type{PopAug{T}}, ::Type{T}) where {T} =
    PopAug{T}(Set{Node{T, PopAug{T}}}(), 0.0, 0.0, 0.0)

# enumeration support (same as PathAug)
path_children(n::Node{T, PopAug{T}}) where {T} = n.aug.pathChildren

# set membership maintenance — fires everywhere (incl. rotations), like PathAug.
function on_path_parent_change!(child::Node{T, PopAug{T}},
                                old_parent::Union{Node, Nothing},
                                new_parent::Union{Node, Nothing}) where {T}
    old_parent isa Node && delete!(old_parent.aug.pathChildren, child)
    new_parent isa Node && push!(new_parent.aug.pathChildren, child)
    return nothing
end

# subtree-sum maintenance — fires ONLY at genuine virtual-edge changes.
@inline function on_virtual_attach!(parent::Node{T, PopAug{T}},
                                    child::Node{T, PopAug{T}}) where {T}
    parent.aug.vir += child.aug.sum
    return nothing
end
@inline function on_virtual_detach!(parent::Node{T, PopAug{T}},
                                    child::Node{T, PopAug{T}}) where {T}
    parent.aug.vir -= child.aug.sum
    return nothing
end
@inline function update_aug!(x::Node{T, PopAug{T}}) where {T}
    s = x.aug.val + x.aug.vir
    l = x.children[1]; l isa Node && (s += l.aug.sum)
    r = x.children[2]; r isa Node && (s += r.aug.sum)
    x.aug.sum = s
    return nothing
end

"""
    set_pop!(node, v)

Set a *singleton* node's weight to `v` (and its subtree sum accordingly). Intended
for initialization before any links are made.
"""
function set_pop!(n::Node{T, PopAug{T}}, v::Real) where {T}
    n.aug.val = Float64(v)
    n.aug.sum = n.aug.val + n.aug.vir
    return n
end

"""
    subtree_pop(v) -> Float64

Total weight of `v`'s represented subtree, relative to the tree's *current* root
(set the root with `evert!` first). O(log n) amortized.
"""
function subtree_pop(v::Node{T, PopAug{T}}) where {T}
    expose!(v)                 # v becomes deepest on its preferred path
    return v.aug.val + v.aug.vir   # ancestors sit in v's left splay child, excluded
end

"""
    pop_link_cut_tree(g, tree_edges, vals)

Build a `PopAug` link-cut tree on `nv(g)` vertices from an undirected edge list,
initializing vertex `i`'s weight from `vals[i]`. Weights are set on the singleton
nodes before linking, so the maintained subtree sums are correct from the start.
"""
function pop_link_cut_tree(g, tree_edges::Vector, vals::AbstractVector)
    n = Graphs.nv(g)
    tree = LinkCutTree{Int, PopAug{Int}}(n)
    for i in 1:n
        set_pop!(tree.nodes[i], vals[i])
    end
    for e in tree_edges
        evert!(tree.nodes[Graphs.src(e)])
        link!(tree.nodes[Graphs.src(e)], tree.nodes[Graphs.dst(e)])
    end
    return tree
end
