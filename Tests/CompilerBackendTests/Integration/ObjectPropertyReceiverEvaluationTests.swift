#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ObjectPropertyReceiverEvaluationTests {
    @Test(arguments: [0, 2])
    func explicitReceiverSideEffectsArePreserved(
        optimization: Int
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = try diffCaseSource("kuu_2307_object_property_receiver.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "KUU2307ObjectPropertyReceiver",
            expected: "OK",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: true
        )
    }
}
#endif
