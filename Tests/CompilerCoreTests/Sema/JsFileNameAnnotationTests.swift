#if canImport(Testing)
    @testable import CompilerCore
    import Testing

    struct JsFileNameAnnotationTests {
        @Test
        func fileNameAndMarkerContractIsSourceBacked() throws {
            let ctx = makeContextFromSources([
                """
                @file:kotlin.js.JsFileName("JsAnnotationsCase")
                package validfile
                class FileNamedDeclaration
                """,
                """
                @file:kotlin.js.JsFileName(FILE_NAME)
                package constfile
                const val FILE_NAME: String = "ConstFileName"
                class ConstNamedDeclaration
                """,
                """
                @file:kotlin.js.JsFileName(42)
                package badtype
                class WrongType
                """,
                """
                @file:kotlin.js.JsFileName(42.5)
                package badfloattype
                class WrongFloatType
                """,
                """
                @file:kotlin.js.JsFileName(fileName())
                package badconst
                fun fileName(): String = "dynamic"
                class NonConstant
                """,
                """
                @file:kotlin.js.JsFileName()
                package missingarg
                class MissingArgument
                """,
                """
                @file:kotlin.js.JsFileName("a", "b")
                package extraarg
                class ExtraArgument
                """,
                """
                @file:kotlin.js.ExperimentalJsFileName("JsAnnotationsCase")
                package badmarkerfile
                class FileMarkerUse
                """,
                """
                package baddeclaration
                @kotlin.js.JsFileName("WrongTarget")
                class DeclarationUse
                """,
                """
                package unopted
                @kotlin.js.ExperimentalJsFileName
                class ExperimentalApi
                fun use(value: ExperimentalApi) {}
                """,
                """
                @file:OptIn(kotlin.js.ExperimentalJsFileName::class)
                package opted
                @kotlin.js.ExperimentalJsFileName
                class ExperimentalApi
                fun use(value: ExperimentalApi) {}
                """,
            ])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics
            #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }.count == 2, "\(diagnostics)")
            #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-TYPE" }.count == 2, "\(diagnostics)")
            #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST" }.count == 1, "\(diagnostics)")
            #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-ARITY" }.count == 3, "\(diagnostics)")
            #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning }.count == 1, "\(diagnostics)")

            let sema = try #require(ctx.sema)
            let jsFileName = try #require(sema.symbols.lookup(fqName: ["kotlin", "js", "JsFileName"].map(ctx.interner.intern)))
            #expect(sema.symbols.annotations(for: jsFileName).contains {
                $0.annotationFQName == "Target" && $0.arguments.contains { $0.contains("FILE") }
            })
            #expect(sema.symbols.annotations(for: jsFileName).contains {
                $0.annotationFQName == "Retention" && $0.arguments.contains { $0.contains("SOURCE") }
            })
            #expect(!sema.symbols.annotations(for: jsFileName).contains {
                $0.annotationFQName == "kotlin.js.ExperimentalJsFileName"
            })

            let sourceFile = try #require(ctx.ast?.files.first { $0.packageFQName.map { ctx.interner.resolve($0) } == ["validfile"] })
            #expect(sourceFile.annotations.contains {
                $0.name == "kotlin.js.JsFileName" && $0.arguments.contains { $0.contains("JsAnnotationsCase") }
            })
            let validPackage = sema.symbols.lookup(fqName: ["validfile"].map(ctx.interner.intern))
            #expect(validPackage.map { packageID in
                !sema.symbols.annotations(for: packageID).contains { $0.annotationFQName == "kotlin.js.JsFileName" }
            } ?? true)

            let marker = try #require(sema.symbols.lookup(fqName: ["kotlin", "js", "ExperimentalJsFileName"].map(ctx.interner.intern)))
            #expect(sema.symbols.annotations(for: marker).contains {
                $0.annotationFQName == "RequiresOptIn" && $0.arguments.contains { $0.contains("WARNING") }
            })
            #expect(sema.symbols.annotations(for: marker).contains {
                $0.annotationFQName == "Retention" && $0.arguments.contains { $0.contains("BINARY") }
            })
        }

        @Test
        func auditedAlternativeFixtureUsesJsFileNameOnTheFile() throws {
            // Kotlin 2.3.10 rejects the original marker-with-argument file use; this is the valid replacement.
            let ctx = makeContextFromSource(
                """
                @file:OptIn(kotlin.js.ExperimentalJsFileName::class)
                @file:kotlin.js.JsFileName("JsAnnotationsCase")
                package jsannotations

                class FileNamedDeclaration
                """
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" }, "\(ctx.diagnostics.diagnostics)")

            let file = try #require(ctx.ast?.files.first)
            #expect(file.annotations.contains {
                $0.name == "kotlin.js.JsFileName" && $0.arguments.contains { $0.contains("JsAnnotationsCase") }
            })
            let sema = try #require(ctx.sema)
            let marker = try #require(sema.symbols.lookup(
                fqName: ["kotlin", "js", "ExperimentalJsFileName"].map(ctx.interner.intern)
            ))
            let fileName = try #require(sema.symbols.lookup(
                fqName: ["kotlin", "js", "JsFileName"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.annotations(for: marker).contains { $0.annotationFQName == "RequiresOptIn" })
            #expect(!sema.symbols.annotations(for: marker).contains { $0.annotationFQName == "kotlin.js.JsFileName" })
            #expect(!sema.symbols.annotations(for: fileName).contains { $0.annotationFQName == "kotlin.js.ExperimentalJsFileName" })
        }
    }
#endif
