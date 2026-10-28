#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// Kotlin exposes an inherited nested classifier by simple name only through
/// the superclass chain: a classifier nested in an interface supertype is
/// unresolved when named bare inside a subtype, and remains so even when the
/// interface is reached transitively through a superclass. Qualified
/// references (`Contract.Entry`) stay valid because they name the declaring
/// classifier's member directly (KUU-3637, KUU-3636).
@Suite
struct InheritedInterfaceNestedClassifierTests {
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

    private func expectReject(_ source: String, codes: Set<String>) throws {
        let ctx = try context(source, library: false)
        try runSema(ctx)
        let emitted = Set(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code))
        #expect(
            !emitted.isDisjoint(with: codes),
            "expected one of \(codes), got \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - SAM construction (KUU-3637)

    @Test
    func interfaceInheritedSamConstructorIsUnresolved() throws {
        try expectReject("""
        interface Contract { fun interface Entry { fun get(): String } }
        class Child : Contract { fun value(): Contract.Entry = Entry { "sam" } }
        """, codes: ["KSWIFTK-SEMA-0023"])
    }

    @Test
    func classInheritedSamConstructorResolves() throws {
        let ctx = try context("""
        open class Base { fun interface Entry { fun get(): String } }
        class Child : Base() { fun value(): Base.Entry = Entry { "sam" } }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func qualifiedInterfaceSamConstructorResolves() throws {
        // The qualified form is the Kotlin workaround and must keep working.
        let ctx = try context("""
        interface Contract { fun interface Entry { fun get(): String } }
        class Child : Contract { fun value(): Contract.Entry = Contract.Entry { "sam" } }
        """, library: false)
        try runSema(ctx)
        // Qualified SAM-construction calls (`Contract.Entry { ... }`) are not
        // dispatched yet — a pre-existing gap that also rejects the same shape
        // at top level, unrelated to inherited-classifier lookup.
        withKnownIssue("qualified fun-interface calls do not reach SAM construction") {
            #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
        }
    }

    // MARK: - Companion invoke through a nested interface (KUU-3636)

    @Test
    func interfaceInheritedCompanionInvokeIsUnresolved() throws {
        try expectReject("""
        interface Contract {
            interface Entry {
                companion object { operator fun invoke(text: String): String = "invoke:" + text }
            }
        }
        class Child : Contract { fun value(): String = Entry("inner") }
        """, codes: ["KSWIFTK-SEMA-0023"])
    }

    @Test
    func classInheritedCompanionInvokeResolves() throws {
        let ctx = try context("""
        open class Base {
            interface Entry {
                companion object { operator fun invoke(text: String): String = "invoke:" + text }
            }
        }
        class Child : Base() { fun value(): String = Entry("inner") }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func qualifiedInterfaceCompanionInvokeResolves() throws {
        let ctx = try context("""
        interface Contract {
            interface Entry {
                companion object { operator fun invoke(text: String): String = "invoke:" + text }
            }
        }
        class Child : Contract { fun value(): String = Contract.Entry("inner") }
        """, library: false)
        try runSema(ctx)
        // Qualified companion `invoke` calls (`Contract.Entry("inner")`) are
        // not dispatched yet — a pre-existing gap that also rejects the same
        // shape at top level, unrelated to inherited-classifier lookup.
        withKnownIssue("qualified companion-invoke calls are not dispatched") {
            #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
        }
    }

    // MARK: - Ordinary nested-class constructors

    @Test
    func interfaceInheritedNestedConstructorIsUnresolved() throws {
        try expectReject("""
        interface Contract { class Entry { fun get(): String = "x" } }
        class Child : Contract { fun value(): Contract.Entry = Entry() }
        """, codes: ["KSWIFTK-SEMA-0023"])
    }

    @Test
    func classInheritedNestedConstructorResolves() throws {
        let ctx = try context("""
        open class Base { class Entry { fun get(): String = "x" } }
        class Child : Base() { fun value(): Base.Entry = Entry() }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func deepClassChainInheritsNestedConstructor() throws {
        let ctx = try context("""
        open class GrandBase { class Entry { fun get(): String = "deep" } }
        open class Base : GrandBase()
        class Child : Base() { fun value(): GrandBase.Entry = Entry() }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    // MARK: - Type-position references

    @Test
    func interfaceInheritedNestedTypeIsUnresolved() throws {
        try expectReject("""
        interface Contract { class Entry }
        class Child : Contract { fun value(): Entry? = null }
        """, codes: ["KSWIFTK-SEMA-0025"])
    }

    @Test
    func classInheritedNestedTypeResolves() throws {
        let ctx = try context("""
        open class Base { class Entry }
        class Child : Base() { fun value(): Entry? = null }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func transitiveInterfaceThroughClassIsUnresolved() throws {
        // `Base : Contract` pulls Contract's members into Base's member scope
        // for calls and properties, but not its nested classifiers.
        try expectReject("""
        interface Contract { class Entry }
        open class Base : Contract
        class Child : Base() { fun value(): Contract.Entry? = null as Entry? }
        """, codes: ["KSWIFTK-SEMA-0025"])
    }

    @Test
    func interfaceToInterfaceNestedTypeIsUnresolved() throws {
        try expectReject("""
        interface Outer { class Entry }
        interface Inner : Outer
        class Child : Inner { fun value(): Inner.Entry? = null as Entry? }
        """, codes: ["KSWIFTK-SEMA-0025"])
    }

    // MARK: - Value / reference positions

    @Test
    func interfaceInheritedNestedObjectIsUnresolved() throws {
        try expectReject("""
        interface Contract { object Entry }
        class Child : Contract { fun value(): Contract.Entry = Entry }
        """, codes: ["KSWIFTK-SEMA-0022"])
    }

    @Test
    func interfaceInheritedClassLiteralIsUnresolved() throws {
        try expectReject("""
        interface Contract { class Entry }
        class Child : Contract { fun value() = Entry::class }
        """, codes: ["KSWIFTK-SEMA-0022"])
    }

    @Test
    func unrelatedNestedClassifierIsUnresolvedByBareName() throws {
        try expectReject("""
        class Other { class Entry }
        class Unrelated { fun value(): Other.Entry? = null as Entry? }
        """, codes: ["KSWIFTK-SEMA-0025"])
    }

    // MARK: - Lexical visibility is preserved

    @Test
    func lexicalNestedClassifierResolves() throws {
        let ctx = try context("""
        class Outer {
            class Entry { fun get(): String = "ok" }
            fun value(): Entry = Entry()
        }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func qualifiedInterfaceNestedTypeResolves() throws {
        let ctx = try context("""
        interface Contract { class Entry }
        class Child : Contract { fun value(): Contract.Entry? = null }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    /// An explicitly imported nested classifier stays resolvable by simple
    /// name in type-parameter bounds: `import test.Ctx.Element` exposes
    /// `Element` to `Base<B : Element, E : B>` even though the global
    /// short-name fallback no longer re-binds nested classifiers. Header
    /// bound resolution must therefore honor the file's imports (this is
    /// what bundled `CoroutineContextImpl.AbstractCoroutineContextKey`
    /// relies on).
    @Test
    func explicitlyImportedNestedClassifierResolvesInBounds() throws {
        let ctx = try context("""
        package test
        import test.Ctx.Element
        interface Ctx { interface Element : Ctx }
        abstract class Base<B : Element, E : B>(private val f: (Element) -> E?)
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
