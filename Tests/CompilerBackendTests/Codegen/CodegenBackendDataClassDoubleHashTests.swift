#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendDataClassDoubleHashTests {
    @Test
    func testSynthesizedDoubleHashPreservesSignedZeroAndCanonicalNaN() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = root.appendingPathComponent("Scripts/diff_cases/data_class_double_hash_signed_zero.kt")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("data-class-double-hash-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: output) }
        let ctx = try runCodegenPipeline(
            inputPath: source.path, moduleName: "DataClassDoubleHash", outputPath: output
        )
        try LinkPhase().run(ctx)
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.stdout == """
        0
        -2147483648
        true
        true
        1073217536
        -1073479680
        -2147483641
        2146959360
        true
        true
        3
        true
        true
        """ + "\n")
    }
}
#endif
