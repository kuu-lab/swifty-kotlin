#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KUU4735DependentBoundInferenceTests {
    @Test func nullableDestinationConstrainsDependentTypeParameterBeforeLambda() throws {
        let ctx = try semaContext(from: """
        interface Box<T>
        class BoxImpl<T> : Box<T>
        fun <R, M : Box<R>> foldLike(destination: M, initialValue: R, operation: (R) -> R): M = destination
        fun main() {
            val nullable: Box<Int?> = BoxImpl()
            foldLike(nullable, 7) { accumulator -> (accumulator ?: 50) + 1 }
        }
        """, includeStdlib: false)
        let sema = try #require(ctx.sema)
        let foldLike = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("foldLike")]))
        let binding = try #require(sema.bindings.callBindings.values.first { $0.chosenCallee == foldLike })
        let inferredValueType = try #require(binding.substitutedTypeArguments.first)
        #expect(inferredValueType == sema.types.makeNullable(sema.types.intType))
    }

    @Test func upperOnlyOwnerDoesNotWidenDependentLambdaInput() throws {
        let ctx = try semaContext(from: """
        interface Source<out T>
        interface Sink<in T>
        class SString : Source<String>
        class SAny : Source<Any>
        fun choose(value: String): Source<String> = SString()
        fun choose(value: Any): Source<Any> = SAny()
        fun <R, M : Source<R>> build(sink: Sink<M>, seed: R, make: (R) -> M): M = make(seed)
        fun main(sink: Sink<Source<Any>>) {
            val result: Source<String> = build(sink, "seed") { choose(it) }
        }
        """, includeStdlib: false)
        let sema = try #require(ctx.sema)
        let build = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("build")]))
        let binding = try #require(sema.bindings.callBindings.values.first { $0.chosenCallee == build })
        let inferredValueType = try #require(binding.substitutedTypeArguments.first)
        #expect(inferredValueType == sema.types.stringType)
    }
}
#endif
