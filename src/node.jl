# ---------------------------------------------------------------------------
# Node and the augmentation hook seam.
#
# A `Node{T,A}` is a splay-tree node used to represent a vertex of a link-cut
# tree. `T` is the vertex-label type. `A` is an *augmentation payload* whose
# type selects the behaviour of a small set of hook functions:
#
#   * `EmptyAug`     → a textbook link-cut tree, hooks are no-ops, zero overhead.
#   * `PathAug{T}`   → additionally maintains, on every node, the set of its
#                      path-children (the reverse of the `pathParent` pointer),
#                      enabling enumeration of the whole represented tree.
#
# The base never *reads* the augmentation for its own correctness; only
# represented-tree enumerators do. `pathParent` is therefore the single access
# pointer the base relies on, and it is written through exactly one choke point,
# `set_path_parent!`, which notifies the augmentation via `on_path_parent_change!`.
# ---------------------------------------------------------------------------

"Augmentation payload for a standard (un-augmented) link-cut tree. Zero size."
struct EmptyAug end

# `PathAug{T}` is defined after `Node` because it stores a `Set` of nodes.

"""
    Node{T,A}

Splay-tree node representing a vertex of a link-cut tree. Field `aug::A` holds
the augmentation payload; see [`EmptyAug`](@ref) and [`PathAug`](@ref).
"""
mutable struct Node{T,A}
    vertex::T
    parent::Union{Node{T,A}, Nothing}
    pathParent::Union{Node{T,A}, Nothing}
    children::Vector{Union{Node{T,A}, Nothing}}
    reversed::Bool
    aug::A
end

"Path-children augmentation: each node stores the set of its path-children."
mutable struct PathAug{T}
    pathChildren::Set{Node{T, PathAug{T}}}
end

# --- augmentation construction hook -----------------------------------------
new_aug(::Type{EmptyAug}, ::Type{T}) where {T} = EmptyAug()
new_aug(::Type{PathAug{T}}, ::Type{T}) where {T} =
    PathAug{T}(Set{Node{T, PathAug{T}}}())

function Node{T,A}(vertex::T) where {T,A}
    children = Union{Node{T,A}, Nothing}[nothing, nothing]
    return Node{T,A}(vertex, nothing, nothing, children, false, new_aug(A, T))
end

# Convenience: default to the path-children augmentation, which is what the
# represented-tree enumerators below require.
Node(vertex::T) where {T} = Node{T, PathAug{T}}(vertex)

# ---------------------------------------------------------------------------
# Plain getters / setters (no hook involvement)
# ---------------------------------------------------------------------------
function setParent!(n::Union{Node, Nothing}, p::Union{Node, Nothing})
    n === nothing && return nothing
    n.parent = p
end

function setChild!(n::Node, i::Int, c::Union{Node, Nothing})
    n.children[i] = c
    setParent!(c, n)
end

setLeft!(n::Node, l::Union{Node, Nothing}) = setChild!(n, 1, l)
setRight!(n::Node, r::Union{Node, Nothing}) = setChild!(n, 2, r)

# ---------------------------------------------------------------------------
# The path-parent choke point — the *only* writer of `pathParent`.
# ---------------------------------------------------------------------------
"""
    set_path_parent!(child, new_parent)

Sole writer of `child.pathParent`. Updates the pointer and then notifies the
augmentation through [`on_path_parent_change!`](@ref). Routing every
`pathParent` write through here keeps the augmentation's reverse index (e.g.
`PathAug`'s `pathChildren`) in lockstep with the forward pointer.
"""
@inline function set_path_parent!(child::Node, new_parent::Union{Node, Nothing})
    old_parent = child.pathParent
    child.pathParent = new_parent
    on_path_parent_change!(child, old_parent, new_parent)
    return child
end

"""
    on_path_parent_change!(child, old_parent, new_parent)

Augmentation hook fired by [`set_path_parent!`](@ref). Default: no-op (used by
`EmptyAug` and any payload that does not track path-children).
"""
@inline on_path_parent_change!(::Node, ::Union{Node, Nothing},
                               ::Union{Node, Nothing}) = nothing

# PathAug: maintain the reverse index. NOTE on determinism — callers that care
# about `Set` iteration order (e.g. RNG-coupled traversals downstream) must fire
# detach-before-attach so the delete/insert *sequence* matches the original
# hand-written code.
function on_path_parent_change!(child::Node{T, PathAug{T}},
                                old_parent::Union{Node, Nothing},
                                new_parent::Union{Node, Nothing}) where {T}
    old_parent isa Node && delete!(old_parent.aug.pathChildren, child)
    new_parent isa Node && push!(new_parent.aug.pathChildren, child)
    return nothing
end

"""
    path_children(n)

The path-children of `n`. Defined only for `PathAug` nodes — represented-tree
enumeration requires that augmentation.
"""
path_children(n::Node{T, PathAug{T}}) where {T} = n.aug.pathChildren

# ---------------------------------------------------------------------------
# Splay-tree utilities
# ---------------------------------------------------------------------------
function sameNode(n1::Union{Node, Nothing}, n2::Union{Node, Nothing})
    if n1 isa Node && n2 isa Node
        return n1.vertex == n2.vertex
    end
    return n1 === n2
end

"Index `n` has in its parent's children vector. Requires a real parent."
function childIndex(n::Node)
    c = n.parent.children
    return sameNode(n, c[1]) ? 1 : (sameNode(n, c[2]) ? 2 : nothing)
end

function findSplayRoot(n::Node)
    r = n
    while r.parent isa Node
        r = r.parent
    end
    return r
end

"Left- (largest=false) or right-most (largest=true) node in the splay tree of `n`."
function findExtreme(n::Node, largest::Bool)
    r = findSplayRoot(n)
    childIndex = largest ? 2 : 1
    while r.children[childIndex] isa Node
        r = r.children[childIndex]
    end
    return r
end
