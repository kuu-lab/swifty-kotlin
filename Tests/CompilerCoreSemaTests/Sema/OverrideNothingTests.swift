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
        // The alias is retained in the supertype argument while the member
        // signature resolves it to the real nominal type.
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

    @Test
    func rejectsOverrideWithNoInheritedNamesake() throws {
        let source = """
        class NoParent { override fun f() = 1 }

        open class EmptyParent
        class Child : EmptyParent() { override fun g() = 2 }

        class PropertyChild { override val x = 3 }
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

        let messages = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error
                && $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING"
        }.map(\.message).sorted()
        #expect(
            messages == ["'f' overrides nothing.", "'g' overrides nothing.", "'x' overrides nothing."],
            "Got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func reportsOverrideNothingAtOverrideKeyword() throws {
        // kotlinc underlines the `override` modifier token, not the
        // declaration head (e.g. `abstract override` reports at the
        // `override` column).
        let source = """
        class A { override fun f() {} }
        abstract class B {
            abstract override fun g(): Int
        }
        class C { final override fun h() = 1 }
        class D { override val x = 3 }
        class E { protected override fun y() {} }
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

        let positions = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error
                && $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING"
        }.compactMap { diagnostic -> (line: Int, column: Int)? in
            diagnostic.primaryRange.map {
                let location = ctx.sourceManager.lineColumn(of: $0.start)
                return (location.line, location.column)
            }
        }.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
        #expect(
            positions.map(\.line) == [1, 3, 5, 6, 7],
            "Got: \(ctx.diagnostics.diagnostics)"
        )
        #expect(
            positions.map(\.column) == [11, 14, 17, 11, 21],
            "Got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func acceptsImplicitAnyOverrides() throws {
        let source = """
        class AnyOverrides {
            override fun toString() = "x"
            override fun equals(other: Any?) = false
            override fun hashCode() = 0
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
