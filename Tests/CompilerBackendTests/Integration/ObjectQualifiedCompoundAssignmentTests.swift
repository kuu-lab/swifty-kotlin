#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct ObjectQualifiedCompoundAssignmentTests {
    @Test(arguments: [0, 2])
    func compoundAssignmentPreservesWrites(optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = try diffCaseSource(
            "kuu_2934_object_qualified_compound_assign.kt",
            file: #filePath
        )
        try assertKotlinOutput(
            source,
            moduleName: "KUU2934ObjectQualifiedCompoundAssignment",
            expected: "OK\n",
            optLevel: optLevel
        )
    }
}
#endif
