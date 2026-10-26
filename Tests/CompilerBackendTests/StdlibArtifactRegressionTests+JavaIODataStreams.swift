@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3077: the missing java.io reader/writer and data-stream classes resolve
    /// from both injected sources and a freshly built stdlib artifact.
    @Test func testJavaIOStringAndDataStreamsAcrossStdlibSurfaces() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.ByteArrayInputStream
        import java.io.ByteArrayOutputStream
        import java.io.DataInputStream
        import java.io.DataOutputStream
        import java.io.PrintWriter
        import java.io.StringReader
        import java.io.StringWriter

        fun main() {
            val reader = StringReader("abc")
            println(reader.ready())
            println(reader.read())
            println(reader.read())
            println(reader.read())
            println(reader.read())
            val writer = StringWriter()
            writer.write("x")
            println(writer)
            val buffered = BufferedWriter(writer)
            buffered.write("y")
            buffered.newLine()
            buffered.flush()
            val printer = PrintWriter(writer)
            printer.print("z")
            printer.println(42)
            printer.close()
            println(writer.toString())
            printer.print("ignored after close")
            println(printer.checkError())

            val bytes = ByteArrayOutputStream()
            val dataOutput = DataOutputStream(bytes)
            dataOutput.writeInt(5)
            dataOutput.writeShort(0x1234)
            dataOutput.writeBoolean(true)
            val dataInput = DataInputStream(ByteArrayInputStream(bytes.toByteArray()))
            println(dataInput.readInt())
            println(dataInput.readUnsignedShort())
            println(dataInput.readBoolean())
        }
        """
        let expected = """
        true
        97
        98
        99
        -1
        x
        xy
        z42

        true
        5
        4660
        true

        """
        let artifact = try Self.buildStdlibArtifact()
        for library in [nil, artifact] as [String?] {
            for level in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let outputPath = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: outputPath) }
                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "JavaIODataStreams",
                        outputPath: outputPath,
                        optLevel: level,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: library
                    )
                    try assertNoDiagnosticErrors(context)
                    let sema = try #require(context.sema)
                    for name in ["StringReader", "StringWriter", "BufferedWriter", "PrintWriter", "DataInputStream", "DataOutputStream"] {
                        let fqName = ["java", "io", name].map(context.interner.intern)
                        let owners = sema.symbols.lookupAll(fqName: fqName).filter {
                            sema.symbols.symbol($0)?.kind == .class
                        }
                        #expect(owners.count == 1)
                        if library == nil, let owner = owners.first {
                            if name == "BufferedWriter" {
                                let constructors = sema.symbols.children(of: owner).filter {
                                    sema.symbols.symbol($0)?.kind == .constructor
                                }
                                #expect(constructors.count == 2)
                                #expect(constructors.allSatisfy { sema.symbols.isSourceBackedSymbol($0) })
                            } else {
                                let isSourceBacked = sema.symbols.isSourceBackedSymbol(owner)
                                #expect(isSourceBacked, "\(name) must resolve to bundled Kotlin source")
                            }
                        }
                    }
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: outputPath, arguments: [])
                    #expect(result.exitCode == 0)
                    #expect(result.stderr.isEmpty)
                    #expect(result.stdout == expected)
                }
            }
        }
    }
}
