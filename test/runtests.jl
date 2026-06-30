using LinkCutTreesAugmented
using Test
using Random

const LCT = LinkCutTreesAugmented
import Graphs
import Graphs: src, dst

include("brute_force.jl")

@testset "LinkCutTreesAugmented" begin
    include("test_structure.jl")
    include("test_builders.jl")
    include("test_docs.jl")
    include("test_queries.jl")
    include("test_popaug.jl")
    include("test_inference.jl")
    include("test_stress.jl")
end
