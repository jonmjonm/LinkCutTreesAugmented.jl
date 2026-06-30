# LinkCutTreesAugmented.jl

[![CI](https://github.com/jonmjonm/LinkCutTreesAugmented.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/jonmjonm/LinkCutTreesAugmented.jl/actions/workflows/ci.yml)

A [link-cut tree](https://dl.acm.org/doi/10.1145/3828.3835) in Julia with a small
**augmentation hook seam**. The base structure is a textbook link-cut forest;
augmentations (extra per-node data maintained incrementally) are opted into via
the node's payload type, without forking the core operations.

> Extracted from the link-cut tree used in
> [CycleWalk.jl](https://github.com/jonmjonm/CycleWalk.jl). The name
> `LinkCutTrees.jl` was taken, hence *Augmented*.

## Design

A node is `Node{T,A}`: `T` is the vertex-label type, `A` an augmentation payload.

- **`EmptyAug`** — zero-size payload; all hooks compile to no-ops. You get a
  standard link-cut tree.
- **`PathAug{T}`** — maintains, on every node, the set of its *path-children*
  (the reverse of the `pathParent` pointer). This makes the whole represented
  tree enumerable (`cc`, `nv_cc`, `get_connected_edge_list`).

The core only ever *writes* `pathParent` through a single choke point,
`set_path_parent!`, which notifies the augmentation via `on_path_parent_change!`
(a no-op by default). New augmentations implement that hook (and, for maintained
aggregates, `update_aug!` / a reversal pushdown) instead of editing the core.

## Operations

`link!`, `cut!`, `evert!` (`set_root!`), `expose!`, `find_root!`, plus the
`PathAug` enumerators `cc`, `nv_cc`, `get_connected_edge_list`, and graph
builders `link_cut_tree(g)` / `link_cut_tree(g, edges)`.

```julia
using LinkCutTreesAugmented
t = LinkCutTree{Int}(5)              # 5 singleton vertices, PathAug by default
for v in 1:4
    evert!(t[v]); link!(t[v], t[v+1])   # build the path 1-2-3-4-5
end
find_root!(t[1]).vertex              # shared root
sort(cc(t[3]))                       # [1, 2, 3, 4, 5]
evert!(t[1]); cut!(t[3])             # split into {1,2} and {3,4,5}
```

For a bare standard tree with no enumeration overhead, use `EmptyAug`:

```julia
t = LinkCutTree{Int, EmptyAug}(5)
```

## API reference

See [`functions_calls.md`](functions_calls.md) for a complete reference of all
public data types and functions — with full argument types — exported by the
package: the augmentation hierarchy (`EmptyAug`, `PathAug`, `PopAug`), the
`Node` / `LinkCutTree` types, structural operations, builders, enumerators,
queries, and the `PopAug` subtree-sum operations. It also documents the **hook
seam** (`set_path_parent!`, `on_path_parent_change!`, `update_aug!`,
`on_virtual_attach!` / `on_virtual_detach!`, `new_aug`) and how the payload
types use it, including how to add a new augmentation.

## Status

Early scaffold (v0.1.0). Base operations + `PathAug` enumeration are implemented
and tested against a brute-force reference. Maintained scalar aggregates (e.g.
subtree sums) are a planned follow-up behind the same hook interface.

## License

MIT.
