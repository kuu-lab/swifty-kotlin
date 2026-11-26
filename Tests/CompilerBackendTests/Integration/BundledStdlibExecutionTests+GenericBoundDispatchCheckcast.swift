@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func genericBoundMemberDispatchCheckcast(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource(
            "kuu_3786_generic_superclass_bound_dispatch.kt",
            file: #filePath
        )
        try compileAndRunKotlin(
            source,
            expectedOutput: """
            iface-get OK
            iface-set OK
            class-bound OK
            contra-bound OK
            safe-bound OK
            42
            7
            9

            """,
            moduleName: "GenericBoundMemberDispatchCheckcast",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

}
