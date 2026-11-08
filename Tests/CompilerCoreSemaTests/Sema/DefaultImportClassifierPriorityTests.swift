#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-4424: Kotlin ranks default imports (kotlin.* and friends) above user
/// star imports. `import java.util.function.*` must not make `Function`
/// resolve to the SAM interface `java.util.function.Function<T, R>`;
/// `kotlin.Function<R>` wins, so the two-type-argument use is rejected just
/// like kotlinc/JVM. An explicit single-type import still wins over the
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
