#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-2180: an Elvis fallback with an empty vararg call can use the non-null
/// left-hand type to infer a still-unbound generic constructor argument.
@Suite
struct GenericConstructorElvisVarargInferenceTests {
    @Test
    func infersEmptyVarargFallbackFromElvisLeftHandType() throws {
        let ctx = try makeContext("""
        class List<out E>
        fun <E> listOf(vararg elements: E): List<E> = null as List<E>
        class Box<T>(val value: T?)
        fun <T> result(dv: List<T>?): Box<List<T>> = Box(dv ?: listOf())
        fun <T> explicitTypeArgument(dv: List<T>?): Box<List<T>> = Box(dv ?: listOf<T>())
        fun <T> withoutElvis(dv: List<T>?): Box<List<T>> = Box(listOf())
        fun strings(): List<String> = listOf("x")
        fun <T> concreteFallback(dv: List<T>?) = Box(dv ?: strings())
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    private func makeContext(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
