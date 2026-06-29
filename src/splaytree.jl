# ---------------------------------------------------------------------------
# Splay-tree internals: lazy reversal, rotation, splay.
# ---------------------------------------------------------------------------

# internal worker for traverseSubtree
function traverseSubtree!(A::Vector, n::Node, order::Int, reverse::Bool)
    if order == 1
        push!(A, n)
    end
    for i in 0:1
        if i == 1 && order == 2
            push!(A, n)
        end
        c = n.children[(i ⊻ n.reversed ⊻ reverse) + 1]
        if c isa Node
            traverseSubtree!(A, c, order, n.reversed ⊻ reverse)
        end
    end
    if order == 3
        push!(A, n)
    end
end

"""
    traverseSubtree(n, order="in-order")

Return a vector with the requested traversal ("pre-order", "in-order", or
"post-order") of the splay subtree rooted at `n`, honouring lazy-reversal flags.
"""
function traverseSubtree(n::Node{T,A}, order::String="in-order") where {T,A}
    out = Vector{Node{T,A}}(undef, 0)
    code = order == "pre-order"  ? 1 :
           order == "in-order"   ? 2 :
           order == "post-order" ? 3 :
           throw(ArgumentError("unknown traversal order: $order"))
    traverseSubtree!(out, n, code, false)
    return out
end

"Rotate `n` up one level, maintaining BST order. Requires a real parent."
function rotateUp(n::Node)
    i = childIndex(n)
    p = n.parent
    g = p.parent

    setParent!(n, g)
    if g isa Node
        j = childIndex(p)
        setChild!(g, j, n)
    else
        # `n` becomes the new splay root and inherits `p`'s path-parent.
        # Fire detach-before-attach so the reverse-index (PathAug) delete/insert
        # sequence matches the original hand-written maintenance exactly.
        pp = p.pathParent
        set_path_parent!(p, nothing)   # detach p (delete p from pp's path-children)
        set_path_parent!(n, pp)        # attach n (push  n into pp's path-children)
    end

    # move n's inner child into n's old slot under p, then make p n's child
    setChild!(p, i, n.children[3 - i])
    setChild!(n, 3 - i, p)

    # recompute aggregates bottom-up: p (now n's child) then n (new local root).
    # The path-parent transfer above leaves the splay tree's total invariant, so
    # no virtual-aggregate change is needed there.
    update_aug!(p)
    update_aug!(n)
end

"Splay `n` to the root of its splay tree without disturbing the in-order sequence."
function splay!(n::Node)
    pushReversed!(n)
    while n.parent isa Node
        p = n.parent
        if p.parent === nothing             # zig
            rotateUp(n)
        elseif childIndex(n) == childIndex(p)  # zig-zig
            rotateUp(p)
            rotateUp(n)
        else                                # zig-zag
            rotateUp(n)
            rotateUp(n)
        end
    end
end

"Push down lazy-reversal flags along the path from the splay root to `n`."
function pushReversed!(n::Node)
    if n.parent isa Node
        pushReversed!(n.parent)
    end
    if n.reversed
        n.children[1], n.children[2] = n.children[2], n.children[1]
        for c in n.children
            if c isa Node
                c.reversed = !c.reversed
            end
        end
        n.reversed = false
    end
end
