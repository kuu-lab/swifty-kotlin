@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite
struct ForLoopTopLevelExtensionResolutionTests {
    @Test
    func acceptsTopLevelExtensionIteratorOperator() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource(
            """
            class Values(val value: String)
            operator fun Values.iterator(): Iterator<String> = object : Iterator<String> {
                var count = 0
                override fun hasNext(): Boolean = count < 2
                override fun next(): String { count++; return value }
            }
            fun test(values: Values) {
                for (value in values) { println(value) }
            }
            """,
            allowDefaultStdlibLibrary: true
        )

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
