#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct InheritedNestedClassConstructorTests {
    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], includeStdlib: false,
            stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [false, true])
    func inheritedConstructorsUseNormalOverloadAndShadowingRules(library: Bool) throws {
        let source = """
        class NumberArg
        class TextArg
        class CurrentArg
        class LocalArg

        open class Base {
            class Packet(val value: NumberArg) {
                constructor(value: TextArg) : this(NumberArg())
            }
        }

        class Child : Base() {
            fun fromNumber(): Packet = Packet(NumberArg())
            fun fromText(): Packet = Packet(TextArg())
            fun qualified(): Base.Packet = Base.Packet(NumberArg())
        }

        class CurrentShadow : Base() {
            class Packet(val value: CurrentArg)
            fun create(): Packet = Packet(CurrentArg())
        }

        class LocalShadow : Base() {
            fun create() {
                class Packet(val value: LocalArg)
                Packet(LocalArg())
            }
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func protectedInheritedNestedConstructorIsVisibleOnlyToSubclass() throws {
        let source = """
        open class Base {
            protected class Marker(val value: Int)
        }

        class Child : Base() {
            fun create(): Int = Marker(1).value
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unrelatedClassCannotCallProtectedInheritedNestedConstructor() throws {
        let source = """
        open class Base {
            protected class Marker(val value: Int)
        }

        class Unrelated {
            fun create(): Int = Marker(1).value
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    @Test
    func explicitProtectedNestedConstructorRemainsInaccessible() throws {
        let source = """
        open class Owner {
            data class Explicit protected constructor(val value: Int)
            fun fromOwner(): Int = Explicit(1).value
        }

        class OwnerChild : Owner() {
            fun fromSubclass(): Int = Owner.Explicit(2).value
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        let protectedErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0041"
        }
        #expect(protectedErrors.count == 2, "\(protectedErrors)")
    }
}
#endif
