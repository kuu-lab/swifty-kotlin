#if canImport(Testing)
    @testable import CompilerCore
    import Testing

    struct JsExportAnnotationTests {
        @Test
        func sourceBackedDeclarationsPreserveExportIntentAndOptInMetadata() throws {
            let ctx = makeContextFromSource("""
            package jscontract

            @kotlin.OptIn(kotlin.js.ExperimentalJsExport::class)
            @kotlin.js.JsExport
            class ExportedBox(val value: Int = 7)
            """)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-JS-EXPORT-WRONG-DECLARATION" })
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-JS-EXPORT-NON-EXPORTABLE-TYPE" })

            let sema = try #require(ctx.sema)
            let exportedBox = try #require(sema.symbols.lookup(fqName: ["jscontract", "ExportedBox"].map(ctx.interner.intern)))
            #expect(sema.symbols.annotations(for: exportedBox).contains { $0.annotationFQName == "kotlin.js.JsExport" })

            let jsExport = try #require(sema.symbols.lookupAll(fqName: ["kotlin", "js", "JsExport"].map(ctx.interner.intern)).first {
                sema.symbols.symbol($0)?.kind == .annotationClass
            })
            #expect(sema.symbols.annotations(for: jsExport).contains { $0.annotationFQName == "kotlin.js.ExperimentalJsExport" })

            let marker = try #require(sema.symbols.lookupAll(fqName: ["kotlin", "js", "ExperimentalJsExport"].map(ctx.interner.intern)).first {
                sema.symbols.symbol($0)?.kind == .annotationClass
            })
            #expect(sema.symbols.annotations(for: marker).contains {
                $0.annotationFQName == "kotlin.RequiresOptIn" && $0.arguments.contains { $0.contains("WARNING") }
            })
            #expect(sema.symbols.annotations(for: marker).contains {
                $0.annotationFQName == "kotlin.annotation.Retention" && $0.arguments.contains { $0.contains("BINARY") }
            })
        }

        @Test
        func markerUsageAndExportAnnotationHaveSeparateEffects() throws {
            let ctx = makeContextFromSource("""
            package jscontract

            @kotlin.js.ExperimentalJsExport
            class MarkerOnly

            @kotlin.js.JsExport
            class ExportedWithoutOptIn

            fun useExported(value: ExportedWithoutOptIn) {}
            """)
            try runSema(ctx)

            let optInWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
            }
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(!optInWarnings.isEmpty, "Expected an @JsExport type use to require ExperimentalJsExport opt-in")

            let sema = try #require(ctx.sema)
            let markerOnly = try #require(sema.symbols.lookup(fqName: ["jscontract", "MarkerOnly"].map(ctx.interner.intern)))
            let exportedWithoutOptIn = try #require(sema.symbols.lookup(fqName: ["jscontract", "ExportedWithoutOptIn"].map(ctx.interner.intern)))
            #expect(sema.symbols.annotations(for: markerOnly).contains { $0.annotationFQName == "kotlin.js.ExperimentalJsExport" })
            #expect(!sema.symbols.annotations(for: markerOnly).contains { $0.annotationFQName == "kotlin.js.JsExport" })
            #expect(sema.symbols.annotations(for: exportedWithoutOptIn).contains { $0.annotationFQName == "kotlin.js.JsExport" })
        }

        @Test
        func markerWithoutExplicitTargetCannotAnnotateFile() throws {
            let ctx = makeContextFromSource("""
            @file:kotlin.js.ExperimentalJsExport
            package jscontract

            class FileMarkerUse
            """)
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" && $0.severity == .error
            }, "\(ctx.diagnostics.diagnostics)")
        }

        @Test
        func unsupportedExportDeclarationsAndTypesMatchAuditedSeverity() throws {
            let ctx = makeContextFromSource("""
            package jscontract

            class InternalBox

            @kotlin.OptIn(kotlin.js.ExperimentalJsExport::class)
            @kotlin.js.JsExport
            suspend fun suspended(): Int = 1

            @kotlin.OptIn(kotlin.js.ExperimentalJsExport::class)
            @kotlin.js.JsExport
            fun exposesInternalType(): InternalBox = InternalBox()
            """)
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-JS-EXPORT-WRONG-DECLARATION" && $0.severity == .error
            }, "\(ctx.diagnostics.diagnostics)")
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-JS-EXPORT-NON-EXPORTABLE-TYPE" && $0.severity == .warning
            }, "\(ctx.diagnostics.diagnostics)")
        }
    }
#endif
