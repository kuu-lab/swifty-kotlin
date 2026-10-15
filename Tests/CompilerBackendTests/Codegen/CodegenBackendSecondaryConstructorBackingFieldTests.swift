#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSecondaryConstructorBackingFieldTests {
    @Test
    func testSecondaryConstructorBackingFieldInKklibO0() throws {
        try assertKotlinOutput(
            try source(),
            moduleName: "SecondaryConstructorBackingFieldKklibO0",
            expected: "OK\nAK|BK|OK|OK|O|OSK|OSK|OK\n",
            optLevel: .O0,
            allowDefaultStdlibLibrary: true
        )
    }

    @Test
    func testSecondaryConstructorBackingFieldInKklibO2() throws {
        try assertKotlinOutput(
            try source(),
            moduleName: "SecondaryConstructorBackingFieldKklibO2",
            expected: "OK\nAK|BK|OK|OK|O|OSK|OSK|OK\n",
            optLevel: .O2,
            allowDefaultStdlibLibrary: true
        )
    }

    private func source() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerBackendTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repository root
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Scripts/diff_cases/kuu_2385_secondary_constructor_custom_getter_backing_field.kt"
        )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
#endif
