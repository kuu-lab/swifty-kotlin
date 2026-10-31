@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-3786: an unchecked cast into a generic superclass erases the
    /// type argument, so a `T`-bounded member used inside the callee can
    /// receive an object that violates the bound. Kotlin/JVM inserts
    /// `checkcast` on the member's declaring type for the erased receiver
    /// — without it the native vtable/itable lookup indexed a foreign
    /// layout and trapped with `Virtual dispatch failed`.
    /// Mirrors kotlin/testData/codegen/box/casts/uncheckedCast8.kt.
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
