#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendMutableMapJava8DefaultMethodsTests {
    @Test
    func java8DefaultMethodsMatchKotlinBehavior() throws {
        let source = try diffCaseSource("kuu_3123_mutable_map_java8_defaults.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "KUU3123MutableMapJava8DefaultMethods",
            expected: """
            11
            10
            3
            11
            12
            null
            12
            null
            5
            12
            null
            null
            true
            created
            created
            null
            false
            null
            fallback

            """,
            allowDefaultStdlibLibrary: true
        )
    }

    @Test
    func mutableMapComputeMatchesKotlinBehavior() throws {
        let source = try diffCaseSource("kuu_4040_mutable_map_compute.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "KUU4040MutableMapCompute",
            expected: """
            11
            7
            null
            false
            null
            0
            {}
            99
            6
            42
            null
            false
            {nullVal=99, present=6}
            2
            true
            true
            null
            null

            """,
            allowDefaultStdlibLibrary: true
        )
    }
}
#endif
