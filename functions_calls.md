# API Reference — `LinkCutTreesAugmented.jl`

This document lists the public data types and functions exported by
`LinkCutTreesAugmented`, with full argument types. Everything in the
"exported" tables is part of the package's `export` list in
`src/LinkCutTreesAugmented.jl`. The [Augmentations & hooks](#augmentations--hooks)
section additionally documents the (non-exported) hook functions that form the
extension seam — these are what you implement to add a new augmentation.

```julia
using LinkCutTreesAugmented
```

Type-parameter conventions used throughout:

- `T` — the vertex-label type (`T <: Integer` for `LinkCutTree`).
- `A` — the augmentation payload type, selected per node as `Node{T,A}`.

---

## Data types

### Augmentation capability hierarchy

Augmentations are selected by a node's payload type `A` in `Node{T,A}`.
Capability is expressed through abstract supertypes used **only in `where`
clauses** to gate which functions apply to which payloads, so dispatch is
resolved at compile time with no runtime cost.

| Type | Kind | Description |
|------|------|-------------|
| `AbstractAug` | abstract | Root of the hierarchy. Any augmentation; all core link-cut operations work for these. |
| `PathCapable <: AbstractAug` | abstract | Can enumerate the represented tree (maintains path-children). |
| `SubtreeSumCapable <: PathCapable` | abstract | Additionally maintains a subtree aggregate (a scalar sum). |

### Concrete augmentation payloads

| Type | Supertype | Fields | Description |
|------|-----------|--------|-------------|
| `EmptyAug` | `AbstractAug` | *(none — zero size)* | Payload for a textbook (un-augmented) link-cut tree. All hooks compile to no-ops, zero overhead. |
| `PathAug{T}` | `PathCapable` | `firstChild`, `nextSib`, `prevSib` :: `Union{Node{T,PathAug{T}}, Nothing}` | Maintains each node's path-children as an **intrusive doubly linked list** threaded through the nodes, making the whole represented tree enumerable. |
| `PopAug{T}` | `SubtreeSumCapable` | `firstChild`, `nextSib`, `prevSib` (as `PathAug`); `val`, `sum`, `vir` :: `Float64` | Adds a per-node weight `val`, the represented-subtree sum `sum`, and `vir` (sum over virtual/path children), enabling `O(log n)` subtree-weight queries. |

`PathAug{T}` and `PopAug{T}` are parameterized by the **same** `T` as the node:
a `PathAug{T}` payload only ever lives in a `Node{T, PathAug{T}}`.

### Core structures

#### `Node{T,A}`

```julia
Node{T,A}(vertex::T)     # explicit augmentation payload type A
Node(vertex::T)          # convenience: A defaults to PathAug{T}
```

A splay-tree node representing one vertex of a link-cut tree. `T` is the
vertex-label type; `A` is the augmentation payload type. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `vertex` | `T` | The vertex label. |
| `parent` | `Union{Node{T,A}, Nothing}` | Splay-tree parent. |
| `pathParent` | `Union{Node{T,A}, Nothing}` | Path-parent pointer (the link-cut "virtual" edge). Written **only** through `set_path_parent!`. |
| `children` | `Vector{Union{Node{T,A}, Nothing}}` | Two-element splay-tree children (`[left, right]`). |
| `reversed` | `Bool` | Lazy-reversal flag. |
| `aug` | `A` | The augmentation payload. |

#### `LinkCutTree{T,A}` (`T <: Integer`)

```julia
LinkCutTree{T,A}(s::Integer)                                   # s singleton vertices 1:s
LinkCutTree{T,A}(nodes::Vector{Union{Node{T,A}, Nothing}})     # wrap an existing node vector
LinkCutTree{T}(s::Integer)                                     # A defaults to PathAug{T}
```

A forest of link-cut trees over vertices `1:n`; `nodes[i]` is the `Node` for
vertex `i`. `A` selects the augmentation (defaults to `PathAug`). Supports:

- `getindex(lct::LinkCutTree, i::Integer)` → `lct[i]`, the `Node` for vertex `i`.
- `length(lct::LinkCutTree)` → number of vertices.

---

## Functions (exported)

Each row gives the full signature including argument types and, where it is
constrained, the augmentation `where` clause.

### Structural operations

Work for **any** augmentation (`A <: AbstractAug`).

| Signature | Returns | Description |
|-----------|---------|-------------|
| `link!(u::Node, v::Node)` | — | Make represented-root `u` a child of `v` (must be in a different represented tree). Throws `ArgumentError` otherwise. |
| `cut!(u::Node)` | — | Detach `u` from its parent in the represented tree (`u` must not be the root). |
| `evert!(u::Node)` | — | Make `u` the root of its represented tree. |
| `set_root!(u::Node)` | — | Alias: `const set_root! = evert!`. |
| `find_root!(u::Node)` | `Node` | Return the root node of `u`'s represented tree. |
| `expose!(n::Node)` | — | Bring `n` to the root of its auxiliary structure so the preferred path runs from the represented root down to `n`. |

### Builders

| Signature | Returns | Description |
|-----------|---------|-------------|
| `link_cut_tree(g::AG; aug::Type=PathAug) where {U, AG<:Graphs.AbstractGraph{U}}` | `LinkCutTree{U,A}` | Build from a rooted, directed tree/forest `g`; an edge `c → n` links child `c` under parent `n`. `aug` selects the payload type. |
| `link_cut_tree(g, tree_edges::Vector; aug::Type=PathAug)` | `LinkCutTree{Int,A}` | Build on `nv(g)` vertices from an explicit undirected edge list, everting each source so each link is legal. |
| `pop_link_cut_tree(g, tree_edges::Vector, vals::AbstractVector)` | `LinkCutTree{Int,PopAug{Int}}` | Build a `PopAug` tree on `nv(g)` vertices; vertex `i`'s weight is initialized from `vals[i]` before linking. |

The `aug` keyword accepts either a `UnionAll` (`PathAug`) — resolved to
`PathAug{T}` for the graph's vertex type — or a concrete payload type
(`EmptyAug`).

### Path-children primitives (require `A <: PathCapable`)

| Signature | Returns | Description |
|-----------|---------|-------------|
| `path_children(n::Node{T,A}) where {T, A<:PathCapable}` | iterator | Zero-allocation iterator over `n`'s path-children. Usable in `for c in path_children(n)`. |
| `first_path_child(n::Node{T,A}) where {T, A<:PathCapable}` | `Union{Node, Nothing}` | First path-child of `n`. Pointer read — preferred on hot paths. |
| `next_path_sibling(n::Node{T,A}) where {T, A<:PathCapable}` | `Union{Node, Nothing}` | Next path-sibling of `n` in its parent's child list. |

The hot-path walk idiom:

```julia
c = first_path_child(node)
while c !== nothing
    # use c
    c = next_path_sibling(c)
end
```

### Represented-tree enumerators (require `A <: PathCapable`)

| Signature | Returns | Description |
|-----------|---------|-------------|
| `cc(node::Node{T,A}, start::Bool=true, vec::Vector{T}=T[]) where {T, A<:PathCapable}` | `Vector{T}` | Vertices in the represented tree containing `node`, as labels. (`start`/`vec` are recursion plumbing — call as `cc(node)`.) |
| `nv_cc(node::Node{T,A}, start::Bool=true) where {T, A<:PathCapable}` | `Int` | Number of vertices in the represented tree containing `node`. |
| `get_connected_edge_list(root::Node{T,A}) where {T, A<:PathCapable}` | `Vector{Graphs.Edge}` | Edge list of the represented tree (roots the tree at `root`). |

### Higher-level queries

| Signature | Returns | Description |
|-----------|---------|-------------|
| `parents(f::LinkCutTree{T,A}) where {T,A}` | `Vector{T}` | `p[i]` = represented-tree parent label of vertex `i` (a root maps to itself). |
| `findPath(n::Node)` | `Vector{Node}` | Nodes on the current preferred path/subtree containing `n`, in depth order. |
| `findPath(i::Integer, t::LinkCutTree)` | `Vector{T}` | As above but returns vertex labels for the tree containing vertex `i`. |
| `get_farthest_node(root::Node{T,A}) where {T, A<:PathCapable}` | `(Node, Int)` | The node farthest from `root` in its represented tree, and its distance. |
| `get_diameter(root::Node{T,A}) where {T, A<:PathCapable}` | `Int` | Diameter (in edges) of the represented tree containing `root`. |

### Subtree-sum operations (require `A <: SubtreeSumCapable`, e.g. `PopAug`)

| Signature | Returns | Description |
|-----------|---------|-------------|
| `set_pop!(n::Node{T,A}, v::Real) where {T, A<:SubtreeSumCapable}` | `Node` | Set a singleton node's weight to `v` (and its subtree sum). Intended for initialization before any links are made. |
| `subtree_pop(v::Node{T,A}) where {T, A<:SubtreeSumCapable}` | `Float64` | Total weight of `v`'s represented subtree, relative to the tree's current root (set the root with `evert!` first). `O(log n)` amortized. |

---

## Augmentations & hooks

An augmentation is **selected by a node's payload type** `A` and **maintained
through hooks** the core calls at its mutation points. The base link-cut tree
never *reads* the augmentation for its own correctness — only the
represented-tree enumerators do — so adding an augmentation never forks the core
operations. You write hook *methods* dispatched on your payload type; for
`EmptyAug` every hook resolves to a no-op and the compiler erases it.

### The choke point

`pathParent` — the single virtual-edge pointer the base relies on — is written
through exactly one function:

```julia
set_path_parent!(child::Node, new_parent::Union{Node, Nothing})
```

It updates `child.pathParent` and then fires `on_path_parent_change!`. Routing
every write through here keeps an augmentation's reverse index (e.g. `PathAug`'s
child list) in lockstep with the forward pointer.

### The hook functions

These are **not exported** (they're the internal extension seam), but they are
the complete set of methods an augmentation overrides. All have a default no-op
method on `::Node`, so a payload only implements the ones it needs.

| Hook | Signature | When it fires / what to do |
|------|-----------|----------------------------|
| `new_aug` | `new_aug(::Type{A}, ::Type{T})::A` | Construct a fresh payload for a singleton node. One method per payload type. |
| `on_path_parent_change!` | `on_path_parent_change!(child::Node, old_parent::Union{Node,Nothing}, new_parent::Union{Node,Nothing})` | Fired by `set_path_parent!` (including during splay rotations). Update any reverse index of the `pathParent` pointer. **Must not** change subtree aggregates — rotations preserve the total. |
| `update_aug!` | `update_aug!(x::Node)` | Recompute `x`'s aggregate from its splay children + own value + virtual contribution. Called after rotations and preferred-child swaps. |
| `on_virtual_attach!` | `on_virtual_attach!(parent::Node, child::Node)` | `child` just became a *virtual* (path-) child of `parent`. |
| `on_virtual_detach!` | `on_virtual_detach!(parent::Node, child::Node)` | `child` stopped being a virtual child of `parent` (joined the preferred path as a real child). |

`on_path_parent_change!` is deliberately distinct from the virtual-attach/detach
pair: the former fires during splay rotations (where the subtree total is
invariant and the aggregate must **not** change), so aggregate maintenance lives
in the latter, which fire **only** at genuine virtual-edge changes.

### How the bundled payloads use the hooks

- **`EmptyAug`** — implements `new_aug` only; every other hook uses the no-op
  default. Result: a textbook link-cut tree with zero augmentation overhead.

- **`PathAug{T}`** (`<: PathCapable`) — implements `on_path_parent_change!` to
  splice `child` out of `old_parent`'s intrusive list and into `new_parent`'s
  (detach-before-attach, for deterministic ordering). This is what makes
  `path_children` / `first_path_child` / `next_path_sibling` — and hence the
  enumerators `cc`, `nv_cc`, `get_connected_edge_list` and the queries
  `get_farthest_node`, `get_diameter` — available.

- **`PopAug{T}`** (`<: SubtreeSumCapable`, so also `PathCapable`) — *inherits*
  the child-list maintenance from the single `A <: PathCapable` method of
  `on_path_parent_change!`, and additionally implements
  `on_virtual_attach!` / `on_virtual_detach!` (adjust `vir` by the child's
  `sum`) and `update_aug!` (recompute `sum = val + vir + left.sum + right.sum`).
  Together these maintain the invariant
  `x.sum == x.val + x.vir + left.sum + right.sum`, which `subtree_pop` reads in
  `O(log n)`.

### Adding a new augmentation (sketch)

1. Define a payload type under the right capability supertype, e.g.
   `mutable struct MyAug{T} <: PathCapable … end` (or `<: SubtreeSumCapable` if
   you maintain a subtree aggregate; or `<: AbstractAug` for a pure no-op
   variant).
2. Add a `new_aug(::Type{MyAug{T}}, ::Type{T})` method returning an initialized
   payload.
3. Implement the hooks your augmentation needs (`on_path_parent_change!` for a
   reverse index; `update_aug!` + `on_virtual_attach!` / `on_virtual_detach!`
   for a maintained aggregate). Everything else stays default.
4. Construct nodes/trees with your payload: `LinkCutTree{T, MyAug{T}}(n)` or via
   `link_cut_tree(g; aug=MyAug)`.

The core operations (`link!`, `cut!`, `evert!`, `expose!`, `find_root!`) work
unchanged for any `A <: AbstractAug`.

---

## Example

```julia
using LinkCutTreesAugmented

t = LinkCutTree{Int}(5)                 # 5 singleton vertices, PathAug by default
for v in 1:4
    evert!(t[v]); link!(t[v], t[v+1])   # build the path 1-2-3-4-5
end

find_root!(t[1]).vertex                 # shared root
sort(cc(t[3]))                          # [1, 2, 3, 4, 5]
nv_cc(t[3])                             # 5

evert!(t[1]); cut!(t[3])                # split into {1,2} and {3,4,5}
```

A bare standard tree with no enumeration overhead uses `EmptyAug`:

```julia
t = LinkCutTree{Int, EmptyAug}(5)       # core ops only; cc/nv_cc unavailable
```

Maintained subtree sums with `PopAug`:

```julia
using Graphs
g = path_graph(5)
edges = collect(Graphs.edges(g))
t = pop_link_cut_tree(g, edges, [1.0, 2.0, 3.0, 4.0, 5.0])
evert!(t[1])
subtree_pop(t[3])                       # weight of subtree rooted at 3 under root 1
```
