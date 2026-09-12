#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMapDestinationEdgeCasesTests {

    @Test
    func testCodegenMapMapFamilyUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/stdlib_kotlin_collections_Map_map.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "MapMapFamilyDestination",
            expected:
                """
                mapTo identity=true value=[existing, A, null]
                mapNotNullTo identity=true value=[existing, A]
                mapKeysTo identity=true value={null=existing, a=A, b=null}
                mapValuesTo identity=true value={null=existing, a=A, b=null}
                duplicateKeys={existing=keep, same=S}
                exception=stop partial=[existing, A]
                """ + "\n"
        )
    }

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
