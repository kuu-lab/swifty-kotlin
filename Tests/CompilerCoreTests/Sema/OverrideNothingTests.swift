#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct OverrideNothingTests {
    @Test
    func rejectsMismatchedOverrideAndAcceptsValidOverloads() throws {
        let source = """
        open class P { open fun f(x: Int) = 1 }
        class Mismatched : P() { override fun f(x: Long) = 2 }

        open class Overloaded {
            open fun f(x: Int) = 1
            open fun f(x: Long) = 2
        }
        class ValidOverload : Overloaded() { override fun f(x: Long) = 3 }

        open class GenericParent<T> { open fun g(x: T) = 1 }
        class SpecializedChild : GenericParent<Int>() { override fun g(x: Int) = 2 }
        """
        let inputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [inputPath],
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: inputPath, contents: Data(source.utf8))
        try runSema(ctx)

        let overrideNothingDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error
                && $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING"
        }
        #expect(overrideNothingDiagnostics.count == 1, "Got: \(ctx.diagnostics.diagnostics)")
        #expect(overrideNothingDiagnostics.first?.message == "'f' overrides nothing.")
    }

    @Test
    func acceptsOverrideThroughTypeAliasedSupertypeArgument() throws {
        // `Sub : Base<Node>` lifts the supertype argument with the alias
        // symbol intact while the member signature resolves `Node` to
        // `Target`; the override check must compare the real nominals.
        let source = """
        class Target

        open class Base<in T> {
            open fun complete(affected: T, failure: Any?) {}
        }

        private typealias Node = Target

        class Sub : Base<Node>() {
            override fun complete(affected: Node, failure: Any?) {}
        }
        """
        let inputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [inputPath],
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: inputPath, contents: Data(source.utf8))
        try runSema(ctx)

        let overrideNothingDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error
                && $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING"
        }
        #expect(overrideNothingDiagnostics.isEmpty, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
