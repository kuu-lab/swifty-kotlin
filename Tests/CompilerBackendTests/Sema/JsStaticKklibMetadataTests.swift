#if canImport(Testing)
    @testable import CompilerBackend
    @testable import CompilerCore
    @testable import CompilerTestSupport
    import Foundation
    import Testing

    struct JsStaticKklibMetadataTests {
        @Test
        func memberIntentAndOptInDiagnosticSurviveKklibImport() throws {
            let librarySource = """
            package jscontract

            @kotlin.OptIn(kotlin.js.ExperimentalJsStatic::class)
            class StaticHolder {
                companion object {
                    @kotlin.js.JsStatic
                    fun message(): String = "static"

                    @get:kotlin.js.JsStatic
                    val computed: Int get() = 7

                    @set:kotlin.js.JsStatic
                    var mutable: Int = 1
                }
            }
            """
            let sourceInjected = makeContextFromSource(librarySource + "\nfun use(): String = StaticHolder.message() + StaticHolder.computed")
            try runSema(sourceInjected)
            let sourceWarnings = sourceInjected.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-OPT-IN"
            }.map { "\($0.code):\($0.severity)" }.sorted()

            try withCompiledLibrary(source: librarySource, moduleName: "JsStaticMetadata") { libraryPath in
                let metadataText = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
                let records = MetadataDecoder().decode(metadataText)
                let functionRecord = try #require(records.first { $0.fqName.hasSuffix(".message") })
                #expect(functionRecord.annotations.contains { $0.annotationFQName == "kotlin.js.JsStatic" })
                let propertyRecord = try #require(records.first { $0.fqName.hasSuffix(".computed") })
                #expect(propertyRecord.annotations.contains {
                    $0.annotationFQName == "kotlin.js.JsStatic" && $0.useSiteTarget == "get"
                })
                let setterRecord = try #require(records.first { $0.fqName.hasSuffix(".mutable") })
                #expect(setterRecord.annotations.contains {
                    $0.annotationFQName == "kotlin.js.JsStatic" && $0.useSiteTarget == "set"
                })

                try withTemporaryFile(contents: """
                package client
                import jscontract.StaticHolder
                fun use(): String = StaticHolder.message() + StaticHolder.computed
                """) { appPath in
                    let imported = makeCompilationContext(
                        inputs: [appPath],
                        moduleName: "JsStaticMetadataClient",
                        emit: .kirDump,
                        searchPaths: [libraryPath]
                    )
                    try runSema(imported)

                    let importedWarnings = imported.diagnostics.diagnostics.filter {
                        $0.code == "KSWIFTK-SEMA-OPT-IN"
                    }.map { "\($0.code):\($0.severity)" }.sorted()
                    #expect(!imported.diagnostics.hasError, "\(imported.diagnostics.diagnostics)")
                    #expect(!sourceWarnings.isEmpty, "Expected the source-injected member calls to require opt-in")
                    #expect(importedWarnings == sourceWarnings)

                    let sema = try #require(imported.sema)
                    let holder = try #require(sema.symbols.lookup(
                        fqName: ["jscontract", "StaticHolder"].map(imported.interner.intern)
                    ))
                    let companion = try #require(sema.symbols.companionObjectSymbol(for: holder))
                    let companionFQName = try #require(sema.symbols.symbol(companion)?.fqName)
                    let message = try #require(sema.symbols.lookup(
                        fqName: companionFQName + [imported.interner.intern("message")]
                    ))
                    let computed = try #require(sema.symbols.lookup(
                        fqName: companionFQName + [imported.interner.intern("computed")]
                    ))
                    let mutable = try #require(sema.symbols.lookup(
                        fqName: companionFQName + [imported.interner.intern("mutable")]
                    ))
                    #expect(sema.symbols.annotations(for: message).contains {
                        $0.annotationFQName == "kotlin.js.JsStatic"
                    })
                    #expect(sema.symbols.annotations(for: computed).contains {
                        $0.annotationFQName == "kotlin.js.JsStatic" && $0.useSiteTarget == "get"
                    })
                    #expect(sema.symbols.annotations(for: mutable).contains {
                        $0.annotationFQName == "kotlin.js.JsStatic" && $0.useSiteTarget == "set"
                    })
                }
            }
        }
    }
#endif
