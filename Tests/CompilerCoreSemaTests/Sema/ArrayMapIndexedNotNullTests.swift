@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ArrayMapIndexedNotNullTests {
    @Test(arguments: [false, true])
    func testVarargArrayMapAcceptsProjectedReceiver(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        interface HasCode { val code: Int }
        fun codesOf(vararg items: HasCode): List<Int> = items.map { it.code }
        fun projectedCodes(items: Array<out HasCode>): List<Int> = items.map { it.code }
        fun literalCodes(): List<Int> = arrayOf(object : HasCode { override val code = 1 }).map { it.code }
        """
        let ctx = makeContextFromSource(
            source,
            emit: .kirDump,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected vararg's projected Array receiver to resolve map: \(errors)")
    }

    @Test(arguments: [false, true])
    func testArrayMapIndexedNotNullTypeBoundaries(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let sources = [
            """
            package accepted
            fun probe(values: Array<out String?>) {
                val result: List<Int> = values.mapIndexedNotNull { index, value ->
                    if (value != null) index else null
                }
                val empty: List<String> = emptyArray<Int>().mapIndexedNotNull { _, _ -> null }
            }
            """,
            """
            package primitive
            fun probe() = intArrayOf(1).mapIndexedNotNull { index, value -> index + value }
            """,
            """
            package wrongreceiver
            fun probe() = 1.mapIndexedNotNull { index, value -> index + value }
            """,
            """
            package nullablebound
            fun probe() = arrayOf(1).mapIndexedNotNull<Int, String?> { _, _ -> null }
            """,
            """
            package wrongresult
            fun probe() {
                val result: List<Int> = arrayOf(1).mapIndexedNotNull { _, _ -> "wrong" }
            }
            """,
            """
            package missingtransform
            fun probe() = arrayOf(1).mapIndexedNotNull()
            """,
            """
            package nullablereceiver
            fun probe(values: Array<Int>?) = values.mapIndexedNotNull { index, value -> index + value }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths, emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)

            let acceptedErrors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(acceptedErrors.isEmpty, "Expected projected arrays and non-null result inference to resolve: \(acceptedErrors)")

            for path in paths.dropFirst() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(!errors.isEmpty, "Expected invalid mapIndexedNotNull call to be rejected in \(path)")
            }
        }
    }
}
