@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2016: preserve the exact reduced OSS consumer and exercise actual
    /// stream wrapping through both stdlib owners at both optimization levels.
    @Test func testJavaReaderConstructorsAcrossStdlibSurfaces() throws {
        let minimal = """
        import java.io.InputStreamReader
        import java.io.BufferedReader
        fun wrap(input: java.io.InputStream): BufferedReader = BufferedReader(InputStreamReader(input))
        fun main() { println("ok") }
        """
        let source = """
        import java.io.BufferedReader
        import java.io.InputStreamReader
        import java.io.IOException
        import java.io.SequenceInputStream

        fun closeFromInterface(reader: AutoCloseable) { reader.close() }

        fun main() {
            val stream = "!hello\\n日本語\\rα\\r\\nlast".byteInputStream()
            val decoder: java.io.Reader = InputStreamReader(stream)
            println(stream.read())
            val reader = BufferedReader(decoder)
            println(reader.readLine())
            println(reader.readLine())
            println(reader.readLine())
            println(reader.readLine())
            println(reader.readLine())
            reader.close()
            reader.close()

            val empty = BufferedReader(InputStreamReader("".byteInputStream()))
            println(empty.readLine())
            empty.close()

            val nested = BufferedReader(BufferedReader(InputStreamReader("ab\\ntail".byteInputStream())))
            println(nested.read())
            println(nested.readLine())
            println(nested.readText())
            nested.close()

            val control = "control\\n".byteInputStream().bufferedReader()
            println(control.readLine())
            println(control.readLine())
            control.close()
            println("control use\\n".byteInputStream().bufferedReader().use { it.readLine() })

            println(BufferedReader(InputStreamReader("use\\n".byteInputStream())).use { it.readLine() })
            closeFromInterface(InputStreamReader("unread".byteInputStream()))
            println("erased")
            try {
                BufferedReader(InputStreamReader("unread".byteInputStream())).use {
                    throw IllegalStateException("block")
                }
            } catch (_: IllegalStateException) {
                println("use exception")
            }

            val chained = BufferedReader(InputStreamReader(SequenceInputStream(
                "a".byteInputStream(), "b\\n日本語\\n".byteInputStream()
            )))
            println(chained.readLine())
            println(chained.readLine())
            println(chained.readLine())
            chained.close()

            val availability = SequenceInputStream("a".byteInputStream(), "bc".byteInputStream())
            availability.read()
            availability.read()
            println(availability.available())
            availability.close()

            // Keep the existing InputStream exception contract intact.
            try {
                "x".byteInputStream().reset()
            } catch (_: IOException) {
                println("IOException")
            }
        }
        """
        let artifact = try Self.buildStdlibArtifact()
        for library in [nil, artifact] as [String?] {
            for level in [OptimizationLevel.O0, .O2] {
                for (consumer, expected) in [
                    (minimal, "ok\n"),
                    (source, "33\nhello\n日本語\nα\nlast\nnull\nnull\n97\nb\ntail\ncontrol\nnull\ncontrol use\nuse\nerased\nuse exception\nab\n日本語\nnull\n1\nIOException\n"),
                ] {
                    try withTemporaryFile(contents: consumer) { path in
                        let output = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString).path
                        defer { try? FileManager.default.removeItem(atPath: output) }
                        let context = try runCodegenPipeline(
                            inputPath: path,
                            moduleName: "JavaReaderConstructors",
                            outputPath: output,
                            optLevel: level,
                            allowDefaultStdlibLibrary: false,
                            stdlibLibraryPath: library
                        )
                        try assertNoDiagnosticErrors(context)
                        let sema = try #require(context.sema)
                        for name in ["InputStreamReader", "BufferedReader"] {
                            let fqName = ["java", "io", name].map(context.interner.intern)
                            let owners = sema.symbols.lookupAll(fqName: fqName).filter {
                                sema.symbols.symbol($0)?.kind == .class
                            }
                            #expect(owners.count == 1)
                            let owner = try #require(owners.first)
                            #expect(sema.symbols.isSourceBackedSymbol(owner))
                            let constructors = sema.symbols.children(of: owner).filter {
                                sema.symbols.symbol($0)?.kind == .constructor
                            }
                            #expect(constructors.count == 1)
                            for constructor in constructors {
                                #expect(sema.symbols.isSourceBackedSymbol(constructor))
                            }
                            if name == "BufferedReader" {
                                let closeMembers = sema.symbols.children(of: owner).filter {
                                    guard let symbol = sema.symbols.symbol($0) else { return false }
                                    return symbol.kind == .function
                                        && context.interner.resolve(symbol.name) == "close"
                                }
                                #expect(closeMembers.count == 1)
                                #expect(closeMembers.allSatisfy(sema.symbols.isSourceBackedSymbol))
                            }
                        }
                        try LinkPhase().run(context)
                        let result = try CommandRunner.run(executable: output, arguments: [])
                        #expect(result.exitCode == 0)
                        #expect(result.stderr.isEmpty)
                        #expect(result.stdout == expected)
                    }
                }
            }
        }
    }
}
