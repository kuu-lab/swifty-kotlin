@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    // KUU-4451: `Properties.getProperty(key)` is a platform-typed (`String!`)
    // java.util return. Using it as the elvis LHS under a non-null expected
    // type must not emit a null assertion before the branch — a missing key
    // has to reach the fallback, matching the JVM.
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
