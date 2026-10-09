#if canImport(Testing)
    @testable import CompilerBackend
    @testable import CompilerCore
    @testable import CompilerTestSupport
    import Foundation
    import Testing

    struct JsExportKklibMetadataTests {
        @Test
        func exportIntentAndOptInDiagnosticSurviveKklibImport() throws {
            let librarySource = """
            package jscontract

            @kotlin.OptIn(kotlin.js.ExperimentalJsExport::class)
            @kotlin.js.JsExport
            class ExportedBox(val value: Int = 7)
            """

            let sourceInjected = makeContextFromSource("""
            package jscontract

            @kotlin.OptIn(kotlin.js.ExperimentalJsExport::class)
            @kotlin.js.JsExport
            class ExportedBox(val value: Int = 7)

            fun accept(box: ExportedBox) {}
            """)
            try runSema(sourceInjected)
            let sourceInjectedOptInDiagnostics = sourceInjected.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-OPT-IN"
            }.map { ($0.code, $0.severity) }

            try withCompiledLibrary(source: librarySource, moduleName: "JsExportMetadata") { libraryPath in
                let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
                let records = MetadataDecoder().decode(metadataText)
                let exportedRecord = try #require(records.first { $0.fqName == "jscontract.ExportedBox" })
                #expect(exportedRecord.annotations.contains { $0.annotationFQName == "kotlin.js.JsExport" })
                #expect(!exportedRecord.annotations.contains { $0.annotationFQName == "kotlin.js.ExperimentalJsExport" })

                try withTemporaryFile(contents: """
                package client
                import jscontract.ExportedBox
                fun accept(box: ExportedBox) {}
                """) { appPath in
                    let imported = makeCompilationContext(
                        inputs: [appPath],
                        moduleName: "JsExportMetadataClient",
                        emit: .kirDump,
                        searchPaths: [libraryPath]
                    )
                    try runSema(imported)

                    let importedOptInDiagnostics = imported.diagnostics.diagnostics.filter {
                        $0.code == "KSWIFTK-SEMA-OPT-IN"
                    }.map { ($0.code, $0.severity) }
                    #expect(!imported.diagnostics.hasError, "\(imported.diagnostics.diagnostics)")
                    #expect(!importedOptInDiagnostics.isEmpty, "Expected imported @JsExport to retain its opt-in requirement")
                    #expect(importedOptInDiagnostics.map(\.0) == sourceInjectedOptInDiagnostics.map(\.0))
                    #expect(importedOptInDiagnostics.map(\.1) == sourceInjectedOptInDiagnostics.map(\.1))

                    let sema = try #require(imported.sema)
                    let importedBox = try #require(sema.symbols.lookup(fqName: ["jscontract", "ExportedBox"].map(imported.interner.intern)))
                    #expect(sema.symbols.annotations(for: importedBox).contains { $0.annotationFQName == "kotlin.js.JsExport" })
                }
            }
        }
    }
#endif
