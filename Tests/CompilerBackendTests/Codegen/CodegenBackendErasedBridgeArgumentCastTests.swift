#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendErasedBridgeArgumentCastTests {
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
    func uncheckedGenericArgumentThrowsClassCastException(
        optimization: Int,
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            source("unchecked_generic_argument_bridge"),
            moduleName: "UncheckedGenericArgumentBridge",
            expected: "OK\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [0, 2], [true, false])
    func erasedReferenceArgumentChecksPreserveValidCallsAndRejectBeforeBody(
        optimization: Int,
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            source("erased_reference_argument_bridge_controls"),
            moduleName: "ErasedReferenceArgumentBridgeControls",
            expected: "bounded CCE\n3\nchained CCE\n1\n2\nfirst CCE\nsecond CCE\n2\nstring CCE\nOK\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [0, 2], [true, false])
    func collectionContainsBridgeReturnsFalseForIncompatibleErasedArguments(
        optimization: Int,
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            source("kuu_2918_contains_any_abstract_set"),
            moduleName: "KUU2918ContainsAnyAbstractSet",
            expected: "false\nfalse\ntrue\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
