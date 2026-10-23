#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct KUU2960LocalClassCaptureExecutionTests {
    @Test(arguments: ["O0", "O2"])
    func localFunctionsForwardMutableCaptureCells(optimization: String) throws {
        try assertFixture(
            "kuu_2960_recapture_local_classes.kt",
            moduleName: "KUU2960RecaptureLocalClasses",
            optimization: optimization,
            expected: "OK\nOK\nOK\n"
        )
    }

    @Test(arguments: ["O0", "O2"])
    func inlineWithUsesReceiverAsInnerClassOuter(optimization: String) throws {
        try assertFixture(
            "kuu_2960_kt10835.kt",
            moduleName: "KUU2960Kt10835",
            optimization: optimization,
            expected: "OK\n"
        )
    }

    @Test(arguments: ["O0", "O2"])
    func genericWithUsesReceiverAsInnerClassOuter(optimization: String) throws {
        try assertFixture(
            "kuu_2960_kt10835a.kt",
            moduleName: "KUU2960Kt10835a",
            optimization: optimization,
            expected: "OK\n"
        )
    }

    private func assertFixture(
        _ fixture: String,
        moduleName: String,
        optimization: String,
        expected: String
    ) throws {
        let source = try diffCaseSource(fixture, file: #filePath)
        let optLevel: OptimizationLevel = optimization == "O2" ? .O2 : .O0
        try assertKotlinOutput(
            source,
            moduleName: moduleName,
            expected: expected,
            optLevel: optLevel
        )
    }
}
#endif
