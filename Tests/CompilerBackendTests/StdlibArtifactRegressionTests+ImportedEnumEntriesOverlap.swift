@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testTypePositionStdlibEnumDoesNotWarnEntriesStubOverlap() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import java.nio.ByteOrder
        import java.time.Month

        fun pick(order: ByteOrder): ByteOrder = order
        fun month(value: Month): Month = value

        fun main() {
            val order = pick(ByteOrder.BIG_ENDIAN)
            println(order.name + " " + order.ordinal)
            println(ByteOrder.values().size)
            println(ByteOrder.valueOf("LITTLE_ENDIAN").ordinal)
            println(ByteOrder.entries.map { it.name })
            println(ByteOrder.nativeOrder())
            println(month(Month.MARCH).ordinal)
            println(Month.entries.size)
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "ImportedEnumEntriesOverlap",
                outputPath: output,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            #expect(context.diagnosticsWithCode("KSWIFTK-SEMA-0102").isEmpty, "\(context.diagnostics.diagnostics)")
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == """
            BIG_ENDIAN 0
            2
            1
            [BIG_ENDIAN, LITTLE_ENDIAN]
            LITTLE_ENDIAN
            2
            12

            """)
        }
    }
}
