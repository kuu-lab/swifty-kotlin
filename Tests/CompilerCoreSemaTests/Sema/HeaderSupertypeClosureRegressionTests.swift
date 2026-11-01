#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Regression coverage for KUU-4013: a nominal owner whose written supertype
/// clause contains several unresolvable names used to blow up
/// `unqualifiedFallbackNominals`'s inherited-nested-classifier probe. Every
/// unresolved clause name re-entered `declaredSupertypeInstanceTypes` for the
/// same owner, which resolved the clause again and multiplied the work by the
/// clause arity at every recursion level — the reaktive `FlatMapObserver`
/// shape (builder-lambda observer with `in` type parameters and an inner
/// class) hung `collectAllHeaders` for 25s+ on a single file.
///
/// The fix has three parts, all exercised below: the parent-ID set is only
/// computed when a same-named candidate can actually use it, a still-open
/// owner closure contributes nothing to a cyclic re-entry, and completed
/// closures are memoized keyed on context + symbol-table size.
@Suite
struct HeaderSupertypeClosureRegressionTests {
    private func context(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], includeStdlib: false,
            stdlibLibraryPath: nil, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    /// Three unresolved supertypes made the old code descend ~3^levels into
    /// the same closure enumeration; this input needed minutes before the
    /// fix and milliseconds after. The loose bound only distinguishes
    /// "completed" from "exploded" so a loaded runner cannot flake it.
    @Test
    func unresolvedSupertypeClauseDoesNotRecurseExponentially() throws {
        let ctx = try context("""
        package repro

        private class Obs<T>(
            private val mapper: (T) -> Unit
        ) : MissingBase(), MissingObserver<T>(), MissingCallback {
            fun f(cb: Callbacks<T>) {}
            fun g(cb: Callbacks<T>) {}
        }
        """)
        let start = Date()
        try runSema(ctx)
        let elapsed = Date().timeIntervalSince(start)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" },
            "expected unresolved-type diagnostics, got \(ctx.diagnostics.diagnostics)"
        )
        #expect(elapsed < 30, "header collection exploded again: \(elapsed)s")
    }

    /// Same shape, but every "missing" name exists as a nested classifier of
    /// an unrelated class: the candidate scan does find non-package parents,
    /// so the owner-closure computation really is demanded — the in-progress
    /// cycle guard is what terminates the descent here.
    @Test
    func sameNamedClassifierCycleDoesNotRecurseExponentially() throws {
        let ctx = try context("""
        package repro

        class Outer {
            class MissingBase
            class MissingObserver
            class MissingCallback
            class Callbacks
        }

        private class Obs<T>(
            private val mapper: (T) -> Unit
        ) : MissingBase(), MissingObserver<T>(), MissingCallback {
            fun f(cb: Callbacks<T>) {}
            fun g(cb: Callbacks<T>) {}
            fun h(cb: Callbacks<T>) {}
        }
        """)
        let start = Date()
        try runSema(ctx)
        let elapsed = Date().timeIntervalSince(start)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" },
            "expected unresolved-type diagnostics, got \(ctx.diagnostics.diagnostics)"
        )
        #expect(elapsed < 30, "inherited-nested-classifier probe exploded again: \(elapsed)s")
    }

    /// The memoized closures must still serve the legitimate KUU-3636/3637
    /// recovery: a bare nested classifier name inside a subtype resolves
    /// through the superclass chain across several member signatures.
    @Test
    func inheritedNestedClassifierStillResolvesAcrossMembers() throws {
        let ctx = try context("""
        open class Base { class Entry { fun get(): String = "x" } }
        class Child : Base() {
            fun first(): Entry? = null
            fun second(): Entry? = null
            fun third(): Entry? = null
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
