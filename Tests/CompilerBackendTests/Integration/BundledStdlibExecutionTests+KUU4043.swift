import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testKUU4043VarargArrayToMap(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_4043_vararg_array_tomap.kt", file: #filePath),
            expectedOutput: """
                {a=1}
                {a=1, b=2}
                {}
                {x=3, y=4}
                {x=3, y=4}
                {z=5}
                {k=9}
                {l=8}
                {a=2}
                {x=3, y=4}
                {}
                true
                {seed=-1, x=3, y=4}
                {x=3, y=4}

                """,
            moduleName: "KUU4043VarargArrayToMap",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
