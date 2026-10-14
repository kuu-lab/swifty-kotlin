@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    // KUU-2044: pin defaults, range validation, and the persistent-vector calls
    // through both bundled source and imported metadata at O0 and O2.
    @Test(arguments: [false, true], [false, true])
    func testArrayFillRange(allowDefaultStdlibLibrary: Bool, optimized: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("array_fill_range.kt", file: #filePath),
            expectedOutput: """
            [a, null, c, d]
            [a, x, x, d]
            [a, x, null, null]
            [y, y, null, null]
            [y, y, null, null]
            [all, all, all, all]
            [null, null, null, null]
            [generic, in, c]
            [1, 9, 3]
            [1, 9, 3]
            []
            [tail, tail, null, null]
            [root, null, null]
            [null, indexed, null, null]
            [b, c]
            ok:0:0
            [a, b, c]
            ok:3:3
            [a, b, c]
            order:fromIndex(2) > toIndex(1)
            [a, b, c]
            bounds:Array index out of range: -1
            [a, b, c]
            bounds:Array index out of range: 4
            [a, b, c]
            bounds:Array index out of range: -1
            [a, b, c]
            bounds:Array index out of range: 4
            [a, b, c]
            order:fromIndex(-1) > toIndex(-2)
            [a, b, c]
            order:fromIndex(4) > toIndex(3)
            [a, b, c]

            """,
            moduleName: "KUU2044ArrayFillRange",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimized ? .O2 : .O0
        )
    }
}
