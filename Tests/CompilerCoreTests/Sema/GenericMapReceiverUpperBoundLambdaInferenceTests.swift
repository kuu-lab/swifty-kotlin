@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericMapReceiverUpperBoundLambdaInferenceTests {
    private static let mapStubs = """
    interface MutableMap<K, V>
    open class MutableList<T> { open fun add(value: T): Boolean = true }
    class ArrayList<T> : MutableList<T>()
    class Iterable<T>

    fun <K, V> MutableMap<K, V>.getOrPut(key: K, defaultValue: () -> V): V = defaultValue()
    """

    private func check(_ source: String) throws -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let inputs = [
            directory.appendingPathComponent("MapStubs.kt").path,
            directory.appendingPathComponent("Probe.kt").path,
        ]
        let ctx = makeCompilationContext(
            inputs: inputs, includeStdlib: false, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: inputs[0], contents: Data(Self.mapStubs.utf8))
        _ = ctx.sourceManager.addFile(path: inputs[1], contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test
    func mapUpperBoundSubstitutesGetOrPutDefaultValueType() throws {
        let ctx = try check("""
        fun <T, K, M : MutableMap<in K, MutableList<T>>>
            Iterable<T>.groupTo(destination: M, key: (T) -> K, item: T): M {
            destination.getOrPut(key(item)) { ArrayList() }.add(item)
            return destination
        }

        fun <T, K, M : MutableMap<K, MutableList<T>>>
            Iterable<T>.groupToInvariant(destination: M, key: (T) -> K, item: T): M {
            destination.getOrPut(key(item)) { ArrayList() }.add(item)
            return destination
        }

        fun <T> concreteMap(destination: MutableMap<String, MutableList<T>>) {
            destination.getOrPut("key") { ArrayList() }
        }

        fun <T, K> typedDefault(
            destination: MutableMap<in K, MutableList<T>>,
            key: K,
            fallback: () -> MutableList<T>
        ) {
            destination.getOrPut(key) { fallback() }
        }
        """)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        """
        fun <T, K, M : MutableMap<K, MutableList<T>>> rejectKey(
            destination: M, key: Any
        ) {
            destination.getOrPut(key) { ArrayList() }
        }
        """,
        """
        fun <T, K, M : MutableMap<K, MutableList<T>>> rejectValue(
            destination: M, key: K
        ) {
            destination.getOrPut(key) { ArrayList<Any>() }
        }
        """,
    ])
    func incompatibleKeyOrValueRemainsRejected(_ declaration: String) throws {
        let ctx = try check(declaration)

        #expect(ctx.diagnostics.hasError, "Expected the incompatible Map type to be rejected")
    }
}
