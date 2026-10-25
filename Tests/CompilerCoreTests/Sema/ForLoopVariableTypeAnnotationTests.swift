#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-3138: an explicit type on a for-loop variable must accept the
/// iterator element type; kotlinc reports an initializer type mismatch.
@Suite
struct ForLoopVariableTypeAnnotationTests {
    private func semaContext(for source: String) throws -> CompilationContext {
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        return ctx
    }

    @Test(arguments: [
        "fun main() { for (c: Int in \"abc\") println(c) }",
        "fun main() { for (c: Double in \"abc\") println(c) }",
        "fun main() { for (x: String in listOf(1, 2)) println(x) }",
        "fun main() { for (c: CharSequence in \"abc\") println(c) }",
    ])
    func mismatchedLoopVariableTypeIsRejected(_ source: String) throws {
        let ctx = try semaContext(for: source)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test(arguments: [
        "fun main() { for (c: Char in \"abc\") println(c) }",
        "fun main() { for (c: Any in \"abc\") println(c) }",
        "fun main() { for (c in \"abc\") println(c) }",
        "fun main() { for (x: Number in listOf(1, 2)) println(x) }",
        "fun main() { for (i: Int in 1..3) println(i) }",
    ])
    func matchingOrSupertypeLoopVariableTypeIsAccepted(_ source: String) throws {
        let ctx = try semaContext(for: source)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }
}
#endif
