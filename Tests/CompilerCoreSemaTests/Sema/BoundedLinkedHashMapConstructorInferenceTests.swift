#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct BoundedLinkedHashMapConstructorInferenceTests {
    @Test func nestedMapUpperBoundInfersLinkedHashMapTypeArguments() throws {
        let ctx = makeContextFromSource("""
        fun <T, K, M : MutableMap<in K, MutableList<T>>>
            Iterable<T>.tryGroupByTo(destination: M, key: (T) -> K): M = destination

        class InferenceResult<out V, out E>(val value: V)

        fun <T, K, E, M : MutableMap<in K, MutableList<T>>> Iterable<T>.tryGroupByToWrapped(
            destination: M,
            key: (T) -> InferenceResult<K, E>
        ): InferenceResult<M, E> = InferenceResult(destination)

        fun <T, K, V, E, M : MutableMap<in K, MutableList<V>>> Iterable<T>.tryGroupByToWrapped(
            destination: M,
            key: (T) -> InferenceResult<K, E>,
            value: (T) -> InferenceResult<V, E>
        ): InferenceResult<M, E> = InferenceResult(destination)

        fun <T, K, E> Iterable<T>.wrappedTryGroupBy(
            key: (T) -> InferenceResult<K, E>
        ): InferenceResult<Map<K, List<T>>, E> =
            tryGroupByToWrapped(LinkedHashMap(), key)

        fun <T, K, V, E> Iterable<T>.wrappedTryGroupBy(
            key: (T) -> InferenceResult<K, E>,
            value: (T) -> InferenceResult<V, E>
        ): InferenceResult<Map<K, List<V>>, E> =
            tryGroupByToWrapped(LinkedHashMap(), key, value)

        fun <T, K> Iterable<T>.tryGroupBy(key: (T) -> K) =
            tryGroupByTo(LinkedHashMap(), key)

        fun <T, K> Iterable<T>.tryGroupByWithExplicitConstructorArguments(key: (T) -> K) =
            tryGroupByTo(LinkedHashMap<K, MutableList<T>>(), key)

        fun <T, K> Iterable<T>.tryGroupByWithExplicitHelperArguments(key: (T) -> K) =
            tryGroupByTo<T, K, LinkedHashMap<K, MutableList<T>>>(LinkedHashMap(), key)

        fun <T, K> Iterable<T>.invalidTryGroupBy(key: (T) -> K) =
            tryGroupByTo(LinkedHashMap<K, String>(), key)

        fun <T, C : MutableCollection<in T>> Iterable<T>.consumeCollection(destination: C): C = destination
        fun <T> Iterable<T>.arrayListControl() = consumeCollection(ArrayList())
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        let sema = try #require(ctx.sema)
        #expect(errors.count == 1, "Expected only the incompatible value type to fail: \(errors)")

        let tryGroupBy = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("tryGroupBy")]))
        let signature = try #require(sema.symbols.functionSignature(for: tryGroupBy))
        guard case let .classType(inferredMapType) = sema.types.kind(of: signature.returnType) else {
            Issue.record("Expected tryGroupBy to infer a LinkedHashMap return type")
            return
        }
        let linkedHashMapFQName = ["kotlin", "collections", "LinkedHashMap"].map(ctx.interner.intern)
        let mutableListFQName = ["kotlin", "collections", "MutableList"].map(ctx.interner.intern)
        #expect(sema.symbols.symbol(inferredMapType.classSymbol)?.fqName == linkedHashMapFQName)
        guard inferredMapType.args.count == 2,
              case let .invariant(inferredValueType) = inferredMapType.args[1],
              case let .classType(inferredListType) = sema.types.kind(of: inferredValueType)
        else {
            Issue.record("Expected LinkedHashMap<K, MutableList<T>>")
            return
        }
        #expect(sema.symbols.symbol(inferredListType.classSymbol)?.fqName == mutableListFQName)
    }
}
#endif
