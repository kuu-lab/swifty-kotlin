#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct GenericBasePropertyGetterErasedABITests {
    private func source(_ filename: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Scripts/diff_cases/\(filename).kt"),
            encoding: .utf8
        )
    }

    @Test(arguments: [0, 2], [true, false])
    func publicFixtureMinimalReproAndControlsPreserveGetterABI(
        optimization: Int,
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            source("kuu_2311_generic_base_property_getter"),
            moduleName: "KUU2311GetterABI",
            expected: "OK|OK|generic|non-generic",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
