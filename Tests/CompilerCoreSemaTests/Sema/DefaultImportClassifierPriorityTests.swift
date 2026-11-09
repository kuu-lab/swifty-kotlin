#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-4424/KUU-4509: Kotlin ranks its builtin types above user star imports,
/// but ordinary default imports below them. `import java.util.function.*`
/// must not make `Function` resolve to the SAM interface
/// `java.util.function.Function<T, R>`; `kotlin.Function<R>` wins, so the
/// two-type-argument use is rejected just like kotlinc/JVM. The same rule
/// does not lift `kotlin.collections.ArrayDeque` — under `import java.util.*`
/// the star-imported `java.util.ArrayDeque` wins, so its `poll`/`peek`
/// members resolve. An explicit single-type import still wins over the
/// default-imported classifier.
@Suite
struct DefaultImportClassifierPriorityTests {
    @Test
    func starImportDoesNotShadowKotlinFunction() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import java.util.function.*
        fun probe(): Int {
            val f: Function<Int, Int> = Function { it * 2 }
            return f.apply(3)
        }
        fun main() { println(probe()) }
        """, emit: .executable, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "expected kotlin.Function to win over java.util.function.*: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func starImportWinsOverOrdinaryDefaultClassifier() throws {
        // KUU-4509: `kotlin.collections.ArrayDeque` is an ordinary default
        // import, not a builtin type, so `import java.util.*` binds
        // `ArrayDeque` to `java.util.ArrayDeque` — its `poll`/`peek`
        // members must resolve.
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import java.util.*
        fun probe(): Int? {
            val d = ArrayDeque<Int>()
            d.addLast(1)
            d.peek()
            return d.poll()
        }
        fun main() { println(probe()) }
        """, emit: .executable, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "expected java.util.ArrayDeque to win over the default import: \(errors)")
    }

    @Test
    func explicitImportStillWinsOverDefaultClassifier() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import java.util.function.Function
        fun probe(): Int {
            val f: Function<Int, Int> = Function { it * 2 }
            return f.apply(3)
        }
        fun main() { println(probe()) }
        """, emit: .executable, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
#endif
