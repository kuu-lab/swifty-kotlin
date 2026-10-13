#if canImport(Testing)
    @testable import CompilerCore
    import Testing

    struct JsExportAnnotationTests {
        // These tests cover native Sema acceptance and metadata only, not Kotlin/JS export emission.
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
            #expect(sema.symbols.annotations(for: jsExport).contains { annotation in
                annotation.annotationFQName == "kotlin.annotation.Target"
                    && ["CLASS", "PROPERTY", "FUNCTION", "FILE"].allSatisfy { target in
                        annotation.arguments.contains { $0.contains(target) }
                    }
            })
            #expect(sema.symbols.annotations(for: jsExport).contains {
                $0.annotationFQName == "kotlin.annotation.Retention" && $0.arguments.contains { $0.contains("BINARY") }
            })

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
        func fileAndDeclarationExportTargetsAreAccepted() throws {
            let ctx = makeContextFromSource(
                """
                @file:OptIn(kotlin.js.ExperimentalJsExport::class)
                @file:kotlin.js.JsExport
                package jscontract

                @kotlin.js.JsExport
                class ExplicitlyExported

                @kotlin.js.JsExport
                fun exportedFunction(): Int = 1

                @kotlin.js.JsExport
                val exportedProperty: Int = 2

                class ExportedByFile
                """
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" }, "\(ctx.diagnostics.diagnostics)")
            let file = try #require(ctx.ast?.files.first)
            #expect(file.annotations.contains { $0.name == "kotlin.js.JsExport" })
            let sema = try #require(ctx.sema)
            let explicit = try #require(sema.symbols.lookup(
                fqName: ["jscontract", "ExplicitlyExported"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.annotations(for: explicit).contains { $0.annotationFQName == "kotlin.js.JsExport" })
            let exportedFunction = try #require(sema.symbols.lookup(
                fqName: ["jscontract", "exportedFunction"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.annotations(for: exportedFunction).contains { $0.annotationFQName == "kotlin.js.JsExport" })
            let exportedProperty = try #require(sema.symbols.lookup(
                fqName: ["jscontract", "exportedProperty"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.annotations(for: exportedProperty).contains { $0.annotationFQName == "kotlin.js.JsExport" })
        }

        @Test
        func exportArgumentCountAndGetterTargetAreRejected() throws {
            let ctx = makeContextFromSources([
                """
                @file:OptIn(kotlin.js.ExperimentalJsExport::class)
                package badarity

                @kotlin.js.JsExport("unexpected")
                class BadArity

                @kotlin.js.ExperimentalJsExport("unexpected")
                class BadMarkerArity
                """,
                """
                @file:OptIn(kotlin.js.ExperimentalJsExport::class)
                package badtarget

                class Holder {
                    @get:kotlin.js.JsExport
                    val value: Int get() = 1
                }
                """,
            ])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics
            #expect(diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-JS-ANNOTATION-TOO-MANY-ARGUMENTS" && $0.severity == .error
            }.count == 2, "JsExport and its marker take no arguments: \(diagnostics)")
            #expect(diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" && $0.severity == .error
            }, "\(diagnostics)")
        }

        @Test
        func markerUsageAndExportAnnotationHaveSeparateEffects() throws {
            let ctx = makeContextFromSource("""
            package jscontract

            @kotlin.js.ExperimentalJsExport
            class MarkerOnly

            @kotlin.js.JsExport
            class ExportedWithoutOptIn

            @kotlin.OptIn(kotlin.js.ExperimentalJsExport::class)
            fun useMarkerWithOptIn(value: MarkerOnly) {}

            fun useMarkerWithoutOptIn(value: MarkerOnly) {}

            fun useExportedWithoutOptIn(value: ExportedWithoutOptIn) {}
            """)
            try runSema(ctx)

            let optInWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
            }
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(optInWarnings.count == 2, "Expected a warning for @JsExport itself and the unopted marker-only API use: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let markerOnly = try #require(sema.symbols.lookup(fqName: ["jscontract", "MarkerOnly"].map(ctx.interner.intern)))
            let exportedWithoutOptIn = try #require(sema.symbols.lookup(fqName: ["jscontract", "ExportedWithoutOptIn"].map(ctx.interner.intern)))
            #expect(sema.symbols.annotations(for: markerOnly).contains { $0.annotationFQName == "kotlin.js.ExperimentalJsExport" })
            #expect(!sema.symbols.annotations(for: markerOnly).contains { $0.annotationFQName == "kotlin.js.JsExport" })
            #expect(sema.symbols.annotations(for: exportedWithoutOptIn).contains { $0.annotationFQName == "kotlin.js.JsExport" })
        }

        @Test
        func fileOptInCoversMarkerUsesThroughoutTheFile() throws {
            let ctx = makeContextFromSource(
                """
                @file:OptIn(kotlin.js.ExperimentalJsExport::class)
                package optedfile

                @kotlin.js.ExperimentalJsExport
                class ExperimentalApi

                fun use(value: ExperimentalApi) {}
                """
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(!ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
            }, "\(ctx.diagnostics.diagnostics)")
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
