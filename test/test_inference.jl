# Type-stability / concreteness checks. The whole point of the parametric
# Node{T,A} design is that augmentations don't reintroduce abstract fields.

@testset "inference" begin

    @testset "node fields are concrete" begin
        for A in (EmptyAug, PathAug{Int}, PopAug{Int})
            NT = Node{Int, A}
            @test isconcretetype(NT)
            ft = fieldtype(NT, :aug)
            @test isconcretetype(ft)
            # parent/pathParent are small Unions with Nothing (still inferable)
            @test fieldtype(NT, :parent) == Union{Nothing, NT}
        end
    end

    @testset "core ops are type stable" begin
        t = LinkCutTree{Int}(5)
        for v in 1:4; evert!(t[v]); link!(t[v], t[v+1]); end
        @test (@inferred find_root!(t[3])) isa Node
        @test (@inferred expose!(t[3])) === nothing
        @test (@inferred evert!(t[2]))                     # returns the reversed flag (true)
    end

    @testset "PopAug query is type stable and concrete Float64" begin
        t = pop_link_cut_tree(Graphs.path_graph(5), Graphs.Edge[], collect(1.0:5.0))
        for v in 1:4; evert!(t[v]); link!(t[v], t[v+1]); end
        @test (@inferred subtree_pop(t[3])) isa Float64
        @test fieldtype(typeof(t[1].aug), :sum) == Float64
    end

    @testset "EmptyAug hooks are genuine no-ops (zero alloc on a warm op)" begin
        t = LinkCutTree{Int, EmptyAug}(6)
        for v in 1:5; evert!(t[v]); link!(t[v], t[v+1]); end
        find_root!(t[1])                          # warm up
        a = @allocated find_root!(t[6])
        @test a == 0
    end
end
