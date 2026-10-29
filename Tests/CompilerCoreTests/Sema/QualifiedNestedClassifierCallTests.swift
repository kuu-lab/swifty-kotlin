#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// A qualified nested-classifier call (`Contract.Entry(...)`) dispatches the
/// trailing call on the nested classifier itself: a `fun interface` takes its
/// SAM-conversion argument, a classifier with a companion object calls its
/// `invoke`, and a nested `object` calls its own `invoke` — all without
/// requiring the unqualified inherited-classifier lookup (KUU-3662).
@Suite
struct QualifiedNestedClassifierCallTests {
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

    private func expectResolves(_ source: String) throws {
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    // MARK: - SAM construction through a qualified fun interface

    @Test
    func qualifiedFunInterfaceSamConstructorResolves() throws {
        try expectResolves("""
        interface Contract { fun interface Entry { fun get(): String } }
        fun value(): Contract.Entry = Contract.Entry { "sam" }
        """)
    }

    @Test
    func qualifiedFunInterfaceSamConstructorResolvesInSubtype() throws {
        // The qualified form is the Kotlin workaround for the inherited
        // interface nested classifier being unreachable by bare name.
        try expectResolves("""
        interface Contract { fun interface Entry { fun get(): String } }
        class Child : Contract { fun value(): Contract.Entry = Contract.Entry { "sam" } }
        """)
    }

    @Test
    func qualifiedFunInterfaceSamConstructorAcceptsCallableReference() throws {
        try expectResolves("""
        interface Contract { fun interface Entry { fun get(): String } }
        fun supply(): String = "ref"
        fun value(): Contract.Entry = Contract.Entry(::supply)
        """)
    }

    // MARK: - Companion invoke through a qualified nested classifier

    @Test
    func qualifiedCompanionInvokeResolves() throws {
        try expectResolves("""
        interface Contract {
            interface Entry {
                companion object { operator fun invoke(text: String): String = "invoke:" + text }
            }
        }
        fun value(): String = Contract.Entry("inner")
        """)
    }

    @Test
    func qualifiedCompanionInvokeResolvesInSubtype() throws {
        try expectResolves("""
        interface Contract {
            interface Entry {
                companion object { operator fun invoke(text: String): String = "invoke:" + text }
            }
        }
        class Child : Contract { fun value(): String = Contract.Entry("inner") }
        """)
    }

    @Test
    func qualifiedCompanionInvokeOnNestedClassResolves() throws {
        try expectResolves("""
        interface Contract {
            class Entry {
                companion object { operator fun invoke(text: String): Entry = Entry() }
            }
        }
        fun value(): Contract.Entry = Contract.Entry("inner")
        """)
    }

    @Test
    func qualifiedCompanionInvokeMemberResolves() throws {
        try expectResolves("""
        interface Contract {
            interface Entry {
                companion object { operator fun invoke(text: String): String = "invoke:" + text }
            }
        }
        fun value(): String = Contract.Entry.Companion.invoke("inner")
        """)
    }

    // MARK: - Nested object invoke

    @Test
    func qualifiedObjectInvokeResolves() throws {
        try expectResolves("""
        interface Contract {
            object Entry { operator fun invoke(text: String): String = "obj:" + text }
        }
        fun value(): String = Contract.Entry("inner")
        """)
    }

    @Test
    func qualifiedObjectZeroArgInvokeResolves() throws {
        // An explicit `()` on a nested `object` invokes `invoke`; it does not
        // read the object itself.
        try expectResolves("""
        interface Contract {
            object Entry { operator fun invoke(): String = "obj" }
        }
        fun value(): String = Contract.Entry()
        """)
    }

    // MARK: - Ordinary nested-class constructors keep working

    @Test
    func qualifiedNestedClassConstructorResolves() throws {
        try expectResolves("""
        interface Contract { class Entry { fun get(): String = "x" } }
        fun value(): Contract.Entry = Contract.Entry()
        """)
    }

    @Test
    func qualifiedNestedObjectReferenceResolves() throws {
        try expectResolves("""
        interface Contract { object Entry { fun get(): String = "x" } }
        fun value(): Contract.Entry = Contract.Entry
        """)
    }
}
#endif
