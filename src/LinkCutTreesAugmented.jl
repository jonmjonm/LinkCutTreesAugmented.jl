"""
    LinkCutTreesAugmented

A standard [link-cut tree](https://dl.acm.org/doi/10.1145/3828.3835) data
structure with a small hook seam for *augmentations*.

The base tree (`aug = EmptyAug`) is a textbook link-cut forest supporting
`link!`, `cut!`, `evert!`, `expose!`, and `find_root!` in amortized `O(log n)`.
An augmentation is selected by the node's payload type `A` in `Node{T,A}` and is
maintained through hooks the core calls at its mutation points — chiefly
`on_path_parent_change!`, fired by the sole `pathParent` writer
[`set_path_parent!`](@ref).

The bundled `PathAug` augmentation maintains each node's path-children set,
enabling enumeration of the whole represented tree (`cc`, `nv_cc`,
`get_connected_edge_list`).
"""
module LinkCutTreesAugmented

import Graphs

export Node, LinkCutTree, EmptyAug, PathAug, PopAug,
       link_cut_tree, link!, cut!, evert!, set_root!, find_root!, expose!,
       path_children, first_path_child, next_path_sibling,
       cc, nv_cc, get_connected_edge_list,
       parents, findPath, get_farthest_node, get_diameter,
       pop_link_cut_tree, subtree_pop, set_pop!

include("node.jl")
include("splaytree.jl")
include("linkcuttree.jl")
include("queries.jl")
include("popaug.jl")

end # module
