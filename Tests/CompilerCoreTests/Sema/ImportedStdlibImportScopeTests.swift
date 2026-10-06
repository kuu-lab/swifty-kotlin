#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

/// KUU-1205: the precompiled stdlib `.kklib` synthesises `.package` records
/// for every FQ-name prefix of an imported declaration, including paths that
/// name a class (`kotlin.coroutines.CoroutineContext`). A non-wildcard import
/// of such a path must stay a declaration import: before the fix it behaved
/// like a package import and leaked the interface's nested members
/// (`Element`, `Key`, ...) into unqualified lookup, so a user-declared
/// `Element` lost to `CoroutineContext.Element` in supertype binding and the
/// `get(Key)` return-type inference.
@Suite
struct ImportedStdlibImportScopeTests {
    private let shadowingSource = """
    import kotlin.coroutines.CoroutineContext
    object Key : CoroutineContext.Key<Element>
    open class Element : CoroutineContext.Element {
        override val key: CoroutineContext.Key<*> = Key
    }
    class Derived : Element()
    fun lookup(context: CoroutineContext): Element? = context.get(Key)
    fun main() { println("ok") }
    """

    @Test
    func userElementShadowsImportedNestedMemberUnderPrecompiledStdlib() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource(
            shadowingSource,
            emit: .executable,
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        #expect(ctx.options.stdlibLibraryPath != nil)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let derived = try #require(
            sema.symbols.lookupAll(fqName: [interner.intern("Derived")]).first {
                sema.symbols.symbol($0)?.kind == .class
            }
        )
        let userElement = try #require(
            sema.symbols.lookupAll(fqName: [interner.intern("Element")]).first {
                sema.symbols.symbol($0)?.kind == .class
            }
        )
        #expect(sema.symbols.directSupertypes(for: derived).contains(userElement))

        let coroutineContextElement = [
            "kotlin", "coroutines", "CoroutineContext", "Element"
        ].map(interner.intern)
        if let importedElement = sema.symbols.lookupAll(fqName: coroutineContextElement).first(where: {
            sema.symbols.symbol($0)?.kind == .interface
        }) {
            #expect(!sema.symbols.directSupertypes(for: derived).contains(importedElement))
        }
    }

    /// A non-wildcard `import <package>` still contributes that package's
    /// top-level declarations; the fix only tightens paths that resolve to a
    /// declaration, not the package-only quirk other code relies on.
    @Test
    func packageOnlyImportStillContributesMembers() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.coroutines
        fun context(): CoroutineContext = EmptyCoroutineContext
        fun main() { println(context()) }
        """, emit: .executable, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    /// `import kotlin.coroutines.*` genuinely is a wildcard import and keeps
    /// exposing package members for bare-name resolution.
    @Test
    func wildcardImportStillContributesMembers() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.*
        fun context(): CoroutineContext = EmptyCoroutineContext
        fun main() { println(context()) }
        """, emit: .executable, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
#endif
