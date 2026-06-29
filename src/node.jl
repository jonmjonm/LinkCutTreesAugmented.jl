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
    left::Union{Node{T,A}, Nothing}     # splay-tree children, stored inline (no
    right::Union{Node{T,A}, Nothing}    # per-node array). Index via getchild/setChild!.
    reversed::Bool
    aug::A
end

"Splay child `i` of `n` (1 = left, 2 = right)."
@inline getchild(n::Node, i::Int) = i == 1 ? n.left : n.right

"""
Path-children augmentation. The path-children are held as an **intrusive doubly
linked list** threaded through the nodes themselves: each node stores the head of
its own child list (`firstChild`) and its position in its parent's list
(`nextSib`/`prevSib`). Attach/detach are O(1) pointer splices with no allocation
and no hashing — the link-cut invariant that a node has exactly one `pathParent`
guarantees it sits in at most one list at a time.
"""
mutable struct PathAug{T}
    firstChild::Union{Node{T, PathAug{T}}, Nothing}
    nextSib::Union{Node{T, PathAug{T}}, Nothing}
    prevSib::Union{Node{T, PathAug{T}}, Nothing}
end

# --- augmentation construction hook -----------------------------------------
new_aug(::Type{EmptyAug}, ::Type{T}) where {T} = EmptyAug()
new_aug(::Type{PathAug{T}}, ::Type{T}) where {T} =
    PathAug{T}(nothing, nothing, nothing)

# --- intrusive child-list splice helpers (shared by PathAug and PopAug) ------
# These touch only `.aug.{firstChild,nextSib,prevSib}`, so they apply to any node
# whose payload carries those fields; they are never called on EmptyAug nodes.
@inline function _list_attach!(parent::Node, child::Node)
    h = parent.aug.firstChild
    child.aug.prevSib = nothing
    child.aug.nextSib = h
    h === nothing || (h.aug.prevSib = child)
    parent.aug.firstChild = child
    return nothing
end
@inline function _list_detach!(parent::Node, child::Node)
    p = child.aug.prevSib
    q = child.aug.nextSib
    p === nothing ? (parent.aug.firstChild = q) : (p.aug.nextSib = q)
    q === nothing || (q.aug.prevSib = p)
    child.aug.prevSib = nothing
    child.aug.nextSib = nothing
    return nothing
end

# Zero-allocation iterator over a node's intrusive child list.
struct PathChildren{N}
    head::Union{N, Nothing}
end
Base.IteratorSize(::Type{<:PathChildren}) = Base.SizeUnknown()
Base.eltype(::Type{PathChildren{N}}) where {N} = N
Base.iterate(pc::PathChildren) = pc.head === nothing ? nothing : (pc.head, pc.head)
function Base.iterate(::PathChildren, node)
    nxt = node.aug.nextSib
    return nxt === nothing ? nothing : (nxt, nxt)
end

function Node{T,A}(vertex::T) where {T,A}
    return Node{T,A}(vertex, nothing, nothing, nothing, nothing, false, new_aug(A, T))
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
    if i == 1
        n.left = c
    else
        n.right = c
    end
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
    old_parent isa Node && _list_detach!(old_parent, child)
    new_parent isa Node && _list_attach!(new_parent, child)
    return nothing
end

# --- subtree-aggregate hooks (no-ops by default) ----------------------------
# These fire only where the represented structure genuinely changes, so an
# aggregate augmentation (e.g. PopAug) can keep a maintained subtree sum.
#
#   update_aug!(x)               recompute x's aggregate from its splay children
#                                + own value + virtual-children contribution.
#                                Called after rotations and preferred-child swaps.
#   on_virtual_attach!(p, c)     c just became a *virtual* child of p (left the
#                                preferred path / was linked under p).
#   on_virtual_detach!(p, c)     c stopped being a virtual child of p (joined the
#                                preferred path as a real child).
#
# NB these are distinct from `on_path_parent_change!`: that one also fires during
# splay rotations (where the subtree total is invariant and the aggregate must
# NOT change), so aggregate maintenance lives here, only at genuine swap sites.
@inline update_aug!(::Node) = nothing
@inline on_virtual_attach!(::Node, ::Node) = nothing
@inline on_virtual_detach!(::Node, ::Node) = nothing

"""
    path_children(n)

Iterate the path-children of `n` (zero-allocation walk of its intrusive child
list). Defined only for augmentations that track path-children (`PathAug`,
`PopAug`) — represented-tree enumeration requires one of those.
"""
path_children(n::Node{T, PathAug{T}}) where {T} =
    PathChildren{Node{T, PathAug{T}}}(n.aug.firstChild)

# ---------------------------------------------------------------------------
# Splay-tree utilities
# ---------------------------------------------------------------------------
function sameNode(n1::Union{Node, Nothing}, n2::Union{Node, Nothing})
    if n1 isa Node && n2 isa Node
        return n1.vertex == n2.vertex
    end
    return n1 === n2
end

"Index `n` has among its parent's children (1 = left, 2 = right). Requires a real parent."
function childIndex(n::Node)
    p = n.parent
    return sameNode(n, p.left) ? 1 : (sameNode(n, p.right) ? 2 : nothing)
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
    while getchild(r, childIndex) isa Node
        r = getchild(r, childIndex)
    end
    return r
end
