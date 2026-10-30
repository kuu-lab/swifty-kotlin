@testable import CompilerCore
import Testing

@Suite(.serialized)
struct NullableReferenceBackedValueClassTests {
    @Test(arguments: [false, true], [0, 2])
    func nullableReferenceFieldReadsPreservePayload(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("value_class_nullable_reference_field.kt", file: #filePath),
            expectedOutput: "shared\ntrue\nfalse\nshared\ntrue\ntrue\nshared\ntrue\ntrue\ntrue\nnull\nfalse\ntrue\nshared\ntrue\n",
            moduleName: "NullableReferenceBackedValueClass",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
