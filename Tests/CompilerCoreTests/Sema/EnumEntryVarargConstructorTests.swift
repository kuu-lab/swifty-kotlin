@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct EnumEntryVarargConstructorTests {
    private func context(for source: String) throws -> CompilationContext {
        TestStdlibCache.shared.prepare()
        _ = try #require(CompilerOptions.defaultStdlibLibraryPath)
        return makeContextFromSources([source], allowDefaultStdlibLibrary: true)
    }

    @Test(arguments: [
        "enum class E(vararg val xs: Int) { EMPTY, ONE(1), MANY(1, 2, 3) }",
        "enum class E(vararg val xs: String) { EMPTY, ONE(\"x\"), MANY(\"x\", \"y\") }",
        "enum class E(val label: String, vararg val xs: Int) { A(\"a\", 1, *intArrayOf(2)), B(xs = intArrayOf(1, 2), label = \"b\") }",
        "enum class E(vararg val xs: String) { A(*arrayOf(\"a\")), B(xs = arrayOf(\"b\")) }",
        "enum class E(vararg val xs: Int = intArrayOf(1)) { A, B(2, 3) }",
        "class C(vararg val xs: Int)\nfun build() = C(1, 2, 3)",
    ])
    func acceptsOrdinaryVarargArguments(source: String) throws {
        let ctx = try context(for: source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "enum class E(val x: Int) { BAD(1, 2) }",
        "enum class E { BAD(1) }",
        "enum class E(val x: Int) { BAD(x = 1, x = 2) }",
        "enum class E(vararg val xs: Int) { BAD(xs = intArrayOf(1), xs = intArrayOf(2)) }",
        "enum class E(vararg val xs: Int) { BAD(1, xs = intArrayOf(2)) }",
        "enum class E(vararg val xs: Int) { BAD(unknown = intArrayOf(1)) }",
        "enum class E(val x: Int) { BAD }",
        "enum class E(vararg val xs: Int, val tail: String) { BAD(1, \"tail\") }",
        "enum class E(vararg val xs: Int) { BAD(1, \"wrong\", 3) }",
        "enum class E(vararg val xs: Int) { BAD(xs = 1) }",
        "enum class E(vararg val xs: Int) { BAD(*arrayOf(1)) }",
        "enum class E(vararg val xs: String) { BAD(*intArrayOf(1)) }",
        "enum class E(vararg val xs: String) { BAD(xs = arrayOf(1)) }",
    ])
    func rejectsInvalidConstructorArguments(source: String) throws {
        let ctx = try context(for: source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected rejection: \(source)")
    }
}
