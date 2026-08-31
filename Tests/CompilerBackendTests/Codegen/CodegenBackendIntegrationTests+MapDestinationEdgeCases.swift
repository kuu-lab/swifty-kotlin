#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMapDestinationEdgeCasesTests {

    @Test
    func testCodegenMapKeysToUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("map_mapkeysto.kt")

        try assertKotlinOutput(
            source,
            moduleName: "MapKeysToDestination",
            expected:
                """
                zero
                zero
                one
                two
                3
                """ + "\n"
        )
    }

    @Test
    func testCodegenMapValuesToUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("map_mapvaluesto.kt")

        try assertKotlinOutput(
            source,
            moduleName: "MapValuesToDestination",
            expected:
                """
                5
                5
                11
                21
                3
                """ + "\n"
        )
    }

}
#endif
