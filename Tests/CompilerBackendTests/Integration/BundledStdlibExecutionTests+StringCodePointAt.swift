@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testStringCodePointAtSourceAndArtifact(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        // Expected values and exception types match Kotlin 2.3.10 on JDK 17.
        try compileAndRunKotlin(
            try diffCaseSource("string_code_point_at.kt", file: #filePath),
            expectedOutput: """
                65
                0
                769
                128512
                56832
                55296
                120
                56320
                1114111
                57343
                55296
                65536
                65535
                56320
                55296
                128512
                65
                128512
                66
                NoSuchElementException
                StringIndexOutOfBoundsException
                StringIndexOutOfBoundsException
                StringIndexOutOfBoundsException
                StringIndexOutOfBoundsException
                StringIndexOutOfBoundsException
                StringIndexOutOfBoundsException
                55357
                0
                """ + "\n",
            moduleName: "KUU2038StringCodePointAt",
            allowDefaultStdlibLibrary: useStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
