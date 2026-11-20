#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct CollectionHOFExpectedTypeBackpropTests {
    @Test(arguments: [false, true])
    func flatMapTransformInfersNestedGenericFromExpectedResult(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        class TQ(val v: String)
        class Ctx(val sa: TQ?)

        class Reg {
            fun <T> resolve(q: TQ, c: Ctx): T? = null
            fun <T> f(c: Ctx): T? = c.sa?.let { resolve(it, c) }
        }

        class Sc {
            fun <T> getAll(c: String): List<T> = listOf()
            fun <T> getAllIndexed(i: Int, c: String): List<T> = listOf()
            fun <T> all(l: List<String>): List<T> =
                listOf<T>() + l.flatMap { k -> getAll(k) }
            fun <T> direct(l: List<String>): List<T> =
                l.flatMap { k -> getAll(k) }
            fun <T> mid(l: List<String>): List<T> {
                val m: List<T> = l.flatMap { k -> getAll(k) }
                return m
            }
            fun <T> indexed(l: List<String>): List<T> =
                l.flatMapIndexed { i, k -> getAllIndexed(i, k) }
            fun <T> iterable(it: Iterable<String>): List<T> =
                it.flatMap { k -> getAll(k) }
            fun <T> seq(s: Sequence<String>): Sequence<T> =
                s.flatMap { k -> getAll(k) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected flatMap transform type arguments to back-propagate from the enclosing expected type, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test(arguments: [false, true])
    func firstNotNullTransformInfersNestedGenericFromExpectedResult(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        class Scope(val id: String = "") {
            val linkedScopes = ArrayList<Scope>()
        }

        fun <T> resolveFromContextOrNull(scope: Scope, lookupParent: Boolean = true): T? = null
        fun <T> resolveFromContext(scope: Scope, lookupParent: Boolean = true): T = TODO()
        fun flatten(scopes: List<Scope>): Set<Scope> = scopes.toSet()

        fun <T> findOrNull(scope: Scope): T? {
            val hasSingleLink = scope.linkedScopes.size == 1
            val parentScopes = if (!hasSingleLink && scope.linkedScopes.size > 1) flatten(scope.linkedScopes) else scope.linkedScopes
            return parentScopes.firstNotNullOfOrNull {
                resolveFromContextOrNull(it, lookupParent = hasSingleLink)
            }
        }

        fun <T> findNonNull(scope: Scope): T {
            val parentScopes = scope.linkedScopes
            return parentScopes.firstNotNullOf {
                resolveFromContext(it, lookupParent = true)
            }
        }

        fun findConcrete(scope: Scope): String? {
            return scope.linkedScopes.firstNotNullOfOrNull {
                resolveFromContextOrNull(it, lookupParent = true)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected firstNotNullOf/OrNull transform type arguments to back-propagate from the enclosing expected type, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test(arguments: [false, true])
    func unconstrainedFlatMapTransformStillRejects(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        class Sc {
            fun <T> getAll(c: String): List<T> = listOf()
            fun bad(l: List<String>) {
                val x = l.flatMap { k -> getAll(k) }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" },
                "Expected the unconstrained nested generic call to keep failing, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
#endif
