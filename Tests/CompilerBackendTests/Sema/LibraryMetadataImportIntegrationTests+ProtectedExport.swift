#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension LibraryMetadataImportIntegrationTests {
    @Test
    func testUserLibraryExportsProtectedMembersForDerivedClasses() throws {
        let librarySource = """
        package properties
        open class Holder {
            private var padding: Int = 99
            internal var hidden: Int = 7
            protected var stored: Int = 0
            protected fun increase(value: Int) { stored += value }
            fun paddingValue(): Int = padding
        }
        """
        try withCompiledLibrary(source: librarySource, moduleName: "ProtectedLibrary") { libraryPath in
            let data = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
            let metadata = try #require(IndexedMetadataFile(data: data))
            for name in ["stored", "increase"] {
                let record = try #require(metadata.entries.first {
                    $0.record.fqName == "properties.Holder.\(name)"
                }?.record)
                #expect(record.visibility == .protected)
            }
            #expect(!metadata.entries.contains { $0.record.fqName == "properties.Holder.padding" })
            #expect(!metadata.entries.contains { $0.record.fqName == "properties.Holder.hidden" })

            let consumerSource = """
            import properties.Holder
            class Derived : Holder() {
                fun read(): Int = stored
                fun write(value: Int) { stored = value }
                fun add(value: Int) { increase(value) }
            }
            fun main() {
                val holder = Derived()
                println(holder.read())
                holder.write(40)
                holder.add(2)
                println(holder.read())
                println(holder.paddingValue())
            }
            """
            try withTemporaryFile(contents: consumerSource) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let ctx = makeCompilationContext(
                    inputs: [path], moduleName: "ProtectedConsumer", emit: .executable,
                    outputPath: output, searchPaths: [libraryPath]
                )
                try runToKIR(ctx)
                try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
                try LoweringPhase().run(ctx)
                try CodegenPhase().run(ctx)
                try LinkPhase().run(ctx)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "0\n42\n99\n")
            }

            for access in ["holder.stored", "holder.increase(1)"] {
                let source = """
                import properties.Holder
                fun invalid(holder: Holder) { \(access) }
                """
                try withTemporaryFile(contents: source) { path in
                    let ctx = makeCompilationContext(
                        inputs: [path], moduleName: "UnrelatedConsumer", searchPaths: [libraryPath]
                    )
                    try runSema(ctx)
                    #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0041" },
                            "\(ctx.diagnostics.diagnostics)")
                }
            }
        }
    }
}
#endif
