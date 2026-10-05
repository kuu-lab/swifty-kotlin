#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CollectionContainsAllReceiverTests {
    @Test
    func iterableAndSequenceReceiversHaveNoContainsAll() throws {
        let ctx = makeContextFromSource("""
        fun sequenceParameter(values: Sequence<Int>): Boolean = values.containsAll(listOf(1))
        fun iterableParameter(values: Iterable<Int>): Boolean = values.containsAll(listOf(1))
        fun mutableIterableParameter(values: MutableIterable<Int>): Boolean = values.containsAll(listOf(1))
        fun nullableSequence(values: Sequence<Int>?): Boolean? = values?.containsAll(listOf(1))
        fun nullableIterable(values: Iterable<Int>?): Boolean? = values?.containsAll(listOf(1))
        fun <T : Iterable<Int>> boundedIterable(values: T): Boolean = values.containsAll(listOf(1))
        fun <T : Sequence<Int>> boundedSequence(values: T): Boolean = values.containsAll(listOf(1))
        fun main() {
            val sequence = sequenceOf(1, 2, 3)
            println(sequence.containsAll(listOf(1, 2)))
            println(sequence.containsAll(listOf(9)))
            println(sequence.containsAll(emptyList<Int>()))
            val iterable: Iterable<Int> = sequence.asIterable()
            println(iterable.containsAll(listOf(1, 2)))
            val widened: Iterable<Int> = listOf(1, 2, 3)
            println(widened.containsAll(listOf(1, 2)))
        }
        """)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(diagnostics.count == 12, "\(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" })
        let sema = try #require(ctx.sema)
        let calls = try containsAllCalls(in: ctx)
        #expect(calls.count == 12)
        #expect(calls.allSatisfy { sema.bindings.callBinding(for: $0) == nil })
    }

    @Test
    func collectionMembersAndExtensionsStillResolve() throws {
        let ctx = makeContextFromSource("""
        fun collection(values: Collection<Int>): Boolean = values.containsAll(listOf(1))
        fun list(values: List<Int>): Boolean = values.containsAll(listOf(1))
        fun set(values: Set<Int>): Boolean = values.containsAll(listOf(1))
        fun mutableCollection(values: MutableCollection<Int>): Boolean = values.containsAll(listOf(1))
        fun mutableList(values: MutableList<Int>): Boolean = values.containsAll(listOf(1))
        fun mutableSet(values: MutableSet<Int>): Boolean = values.containsAll(listOf(1))
        fun <T : Collection<Int>> bounded(values: T): Boolean = values.containsAll(listOf(1))
        fun nullable(values: Collection<Int>?): Boolean? = values?.containsAll(listOf(1))
        fun main() {
            println(listOf(1, 2).containsAll(listOf(1)))
            println(setOf(1, 2).containsAll(emptyList<Int>()))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let calls = try containsAllCalls(in: ctx)
        #expect(calls.count == 10)
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.returnType == sema.types.booleanType)
        }
    }

    @Test
    func userDefinedIterableAndSequenceExtensionsAndMembersStillResolve() throws {
        let ctx = makeContextFromSource("""
        fun Iterable<Int>.containsAll(elements: Collection<Int>): Boolean = true
        fun Sequence<Int>.containsAll(elements: Collection<Int>): Boolean = false
        class Items : Iterable<Int> {
            override fun iterator(): Iterator<Int> = listOf(1).iterator()
            fun containsAll(elements: Collection<Int>): Boolean = true
        }
        fun iterable(values: Iterable<Int>): Boolean = values.containsAll(listOf(1))
        fun sequence(values: Sequence<Int>): Boolean = values.containsAll(listOf(1))
        fun member(values: Items): Boolean = values.containsAll(listOf(1))
        fun main() {
            println(sequenceOf(1).containsAll(listOf(1)))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let calls = try containsAllCalls(in: ctx)
        #expect(calls.count == 4)
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(ctx.sourceManager.origin(of: fileID) == .user)
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }
    }

    private func containsAllCalls(in ctx: CompilationContext) throws -> [ExprID] {
        let ast = try #require(ctx.ast)
        return ast.arena.exprs.indices.compactMap { index in
            let id = ExprID(rawValue: Int32(index))
            let name: InternedString
            switch ast.arena.expr(id) {
            case let .memberCall(_, callee, _, _, _), let .safeMemberCall(_, callee, _, _, _):
                name = callee
            default:
                return nil
            }
            guard ctx.interner.resolve(name) == "containsAll",
                  let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else {
                return nil
            }
            return id
        }
    }
}
#endif
