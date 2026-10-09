#if canImport(Testing)
    @testable import CompilerBackend
    @testable import CompilerCore
    @testable import CompilerTestSupport
    import Foundation
    import Testing

    struct JsFileNameKklibMetadataTests {
        @Test
        func declarationMetadataAndOptInDiagnosticsSurviveKklibImport() throws {
            let librarySource = """
            @file:kotlin.js.JsFileName("LibraryOutput")
            package jscontract

            @kotlin.js.ExperimentalJsFileName
            class ExperimentalApi
            """
            let sourceInjected = makeContextFromSource("""
            package jscontract

            @kotlin.js.ExperimentalJsFileName
            class ExperimentalApi
            fun use(value: ExperimentalApi) {}
            """)
            try runSema(sourceInjected)
            let sourceOptInDiagnostics = sourceInjected.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-OPT-IN"
            }.map { ($0.code, $0.severity) }
            #expect(!sourceInjected.diagnostics.hasError, "\(sourceInjected.diagnostics.diagnostics)")
            #expect(!sourceOptInDiagnostics.isEmpty, "Expected marker use to require opt-in")

            let sourceSema = try #require(sourceInjected.sema)
            let sourceApi = try #require(sourceSema.symbols.lookup(fqName: ["jscontract", "ExperimentalApi"].map(sourceInjected.interner.intern)))
            let sourceApiMarkerAnnotations = sourceSema.symbols.annotations(for: sourceApi).filter {
                $0.annotationFQName == "kotlin.js.ExperimentalJsFileName"
            }
            #expect(!sourceApiMarkerAnnotations.isEmpty)

            let sourceMarker = try #require(sourceSema.symbols.lookup(fqName: ["kotlin", "js", "ExperimentalJsFileName"].map(sourceInjected.interner.intern)))
            #expect(sourceSema.symbols.annotations(for: sourceMarker).contains {
                $0.annotationFQName == "RequiresOptIn" && $0.arguments.contains { $0.contains("WARNING") }
            })
            #expect(sourceSema.symbols.annotations(for: sourceMarker).contains {
                $0.annotationFQName == "Retention" && $0.arguments.contains { $0.contains("BINARY") }
            })

            let sourceFileName = try #require(sourceSema.symbols.lookup(fqName: ["kotlin", "js", "JsFileName"].map(sourceInjected.interner.intern)))
            #expect(sourceSema.symbols.annotations(for: sourceFileName).contains {
                $0.annotationFQName == "Target" && $0.arguments.contains { $0.contains("FILE") }
            })
            #expect(sourceSema.symbols.annotations(for: sourceFileName).contains {
                $0.annotationFQName == "Retention" && $0.arguments.contains { $0.contains("SOURCE") }
            })

            try withCompiledLibrary(source: librarySource, moduleName: "JsFileNameMetadata") { libraryPath in
                let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
                let records = MetadataDecoder().decode(metadataText)
                let apiRecord = try #require(records.first { $0.fqName == "jscontract.ExperimentalApi" })
                #expect(apiRecord.annotations.filter { $0.annotationFQName == "kotlin.js.ExperimentalJsFileName" } == sourceApiMarkerAnnotations)
                let packageRecord = records.first { $0.fqName == "jscontract" && $0.kind == .package }
                #expect(!(packageRecord?.annotations.contains { $0.annotationFQName == "kotlin.js.JsFileName" } ?? false))

                try withTemporaryFile(contents: """
                package client
                import jscontract.ExperimentalApi
                fun use(value: ExperimentalApi) {}
                """) { appPath in
                    let imported = makeCompilationContext(
                        inputs: [appPath],
                        moduleName: "JsFileNameMetadataClient",
                        emit: .kirDump,
                        searchPaths: [libraryPath]
                    )
                    try runSema(imported)

                    let importedOptInDiagnostics = imported.diagnostics.diagnostics.filter {
                        $0.code == "KSWIFTK-SEMA-OPT-IN"
                    }.map { ($0.code, $0.severity) }
                    #expect(!imported.diagnostics.hasError, "\(imported.diagnostics.diagnostics)")
                    #expect(importedOptInDiagnostics.map(\.0) == sourceOptInDiagnostics.map(\.0))
                    #expect(importedOptInDiagnostics.map(\.1) == sourceOptInDiagnostics.map(\.1))

                    let sema = try #require(imported.sema)
                    let importedApi = try #require(sema.symbols.lookup(fqName: ["jscontract", "ExperimentalApi"].map(imported.interner.intern)))
                    #expect(sema.symbols.annotations(for: importedApi).filter {
                        $0.annotationFQName == "kotlin.js.ExperimentalJsFileName"
                    } == sourceApiMarkerAnnotations)
                }
            }
        }
    }
#endif
