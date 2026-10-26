@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ConstructorDelegationNamedVarargArrayTests {
    @Test
    func acceptsNamedVarargArraysInObjectSuperCalls() throws {
        let source = """
        open class Base(vararg val xs: Int)
        object Named : Base(xs = intArrayOf(5, 6))
        fun anonymous() = object : Base(xs = intArrayOf(7, 8)) {}
        """
        TestStdlibCache.shared.prepare()
        _ = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let ctx = makeContextFromSources([source], allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
