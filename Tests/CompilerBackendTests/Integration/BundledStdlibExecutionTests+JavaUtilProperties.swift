@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testPropertiesGetPropertyElvisDefaultMatchesJvm() throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu4451_properties_getproperty.kt", file: #filePath),
            expectedOutput: """
            d
            null
            v
            d
            inherited
            d
            empty
            fb

            """
        )
    }
}
