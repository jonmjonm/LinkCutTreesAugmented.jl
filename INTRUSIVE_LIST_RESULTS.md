# Intrusive sibling linked list for path-children — experiment results

Branch: `intrusive-pathchildren` (off `main`). Replaces `pathChildren::Set{Node}`
in `PathAug`/`PopAug` with an intrusive doubly-linked child list threaded through
the augmentation payloads (`firstChild`/`nextSib`/`prevSib`). `EmptyAug` is
untouched (still zero-size). Attach/detach are O(1) pointer splices; iteration is
a zero-allocation walk. Maintenance moved from `push!`/`delete!` on a `Set` to
`_list_attach!`/`_list_detach!`; the subtree-sum (`vir`) logic is unchanged.

## Correctness / reproducibility
- Package test suite: **passes** (~11.3k assertions; tests are order-insensitive).
- CycleWalk determinism fingerprint: **bit-identical** to the Set-based baseline
  (`identifier=-4904049048456373826 sum_n2d=301 hash_n2d=2833919996414137363
  roots=[7,35,52,54,59]`). The active chain does not depend on path-children
  iteration order, despite the new order being LIFO rather than hash-based.
- Full CycleWalk `runtests.jl`: **0 failures / 0 errors**.

## Library micro-benchmarks (determinism/bench_lct.jl) — Set → intrusive list
| n | aug | ns/op (Set → list) | B/op (Set → list) |
|---|-----|--------------------|-------------------|
| 1024  | EmptyAug | 50 → 52   | 0 → 0    |
|       | PathAug  | 123 → 62  | 29.7 → **0** |
|       | PopAug   | 148 → 82  | 29.7 → **0** |
| 4096  | PathAug  | 115 → 60  | 29.5 → **0** |
|       | PopAug   | 140 → 69  | 29.5 → **0** |
| 16384 | PathAug  | 172 → 78  | 29.5 → **0** |
|       | PopAug   | 177 → 98  | 29.5 → **0** |

→ **~1.8–2× faster `link`/`cut` ops and zero per-op allocation** for the
augmentations that track path-children. `subtree_pop` unchanged (~50 ns, 0 B).

## CycleWalk end-to-end impact
| map | Set | intrusive list |
|-----|-----|----------------|
| grid (66,667 steps) | 3.72 KiB/step, 80.5k steps/s | 3.72 KiB/step, **82.1k** steps/s |
| NC   (10,000 steps) | 18.78 KiB/step, 15.2k steps/s | 18.75 KiB/step, **15.4k** steps/s |

→ Only **~1.5–2% wall, negligible allocation change** end-to-end. CycleWalk's
per-step cost is dominated by non-LCT work (`_find_cross_district_edges!`,
`assign_district_map!`'s own `Set{Node}` BFS queue, `balance`,
`find_cuttable_edge_pairs`), and it performs relatively few link-cut ops per
step, so a 2× speedup of those ops barely moves the total.

## Takeaway
A clean, strictly-better library change (faster, zero-alloc, bit-identical, all
tests green) that benefits any consumer doing many link-cut ops — but it is **not**
a meaningful lever for CycleWalk wall-time. For CycleWalk, the bigger wins are the
Tier-3 CycleWalk-side allocators (vertex-indexed structures in
`assign_district_map!` / `_find_cross_district_edges!`).

Left on this branch per request; `main` is unchanged.
