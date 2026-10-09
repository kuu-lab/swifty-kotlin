#if canImport(Testing)
    @testable import CompilerCore
    import Testing

    struct JsStaticAnnotationTests {
        @Test
        func sourceBackedDeclarationsSeparateMarkerAndStaticMemberMetadata() throws {
            let ctx = makeContextFromSource("""
            @file:OptIn(kotlin.js.ExperimentalJsStatic::class)
            package jscontract

            @kotlin.js.JsStatic
            fun topLevel(): String = "top-level"

            class Ordinary {
                companion object {
                    @kotlin.js.JsStatic
                    fun message(): String = "companion"

                    @get:kotlin.js.JsStatic
                    val computed: Int get() = 7

                    @set:kotlin.js.JsStatic
                    var mutable: Int = 1
                }
            }

            interface Contract {
                companion object {
                    @kotlin.js.JsStatic
                    fun message(): String = "interface"
                }
            }

            @OptIn(kotlin.js.ExperimentalJsStatic::class)
            fun main() {
                println(topLevel())
                println(Ordinary.message())
                println(Ordinary.computed)
                println(Contract.message())
            }
            """)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            #expect(!ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-JS-STATIC-NOT-IN-CLASS-COMPANION"
            }, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let holder = try #require(sema.symbols.lookup(fqName: ["jscontract", "Ordinary"].map(ctx.interner.intern)))
            let companion = try #require(sema.symbols.companionObjectSymbol(for: holder))
            let companionFQName = try #require(sema.symbols.symbol(companion)?.fqName)
            let message = try #require(sema.symbols.lookup(fqName: companionFQName + [ctx.interner.intern("message")]))
            let computed = try #require(sema.symbols.lookup(fqName: companionFQName + [ctx.interner.intern("computed")]))
            let mutable = try #require(sema.symbols.lookup(fqName: companionFQName + [ctx.interner.intern("mutable")]))
            #expect(sema.symbols.annotations(for: message).contains {
                $0.annotationFQName == "kotlin.js.JsStatic"
            })
            #expect(sema.symbols.annotations(for: computed).contains {
                $0.annotationFQName == "kotlin.js.JsStatic" && $0.useSiteTarget == "get"
            })
            #expect(sema.symbols.annotations(for: mutable).contains {
                $0.annotationFQName == "kotlin.js.JsStatic" && $0.useSiteTarget == "set"
            })

            let marker = try #require(sema.symbols.lookup(
                fqName: ["kotlin", "js", "ExperimentalJsStatic"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.annotations(for: marker).contains {
                $0.annotationFQName == "RequiresOptIn" && $0.arguments.contains { $0.contains("WARNING") }
            })
            #expect(sema.symbols.annotations(for: marker).contains {
                $0.annotationFQName == "Retention" && $0.arguments.contains { $0.contains("BINARY") }
            })

            let jsStatic = try #require(sema.symbols.lookup(fqName: ["kotlin", "js", "JsStatic"].map(ctx.interner.intern)))
            #expect(sema.symbols.annotations(for: jsStatic).contains {
                $0.annotationFQName == "ExperimentalJsStatic"
            })
            #expect(sema.symbols.annotations(for: jsStatic).contains {
                $0.annotationFQName == "Retention" && $0.arguments.contains { $0.contains("BINARY") }
            })
            #expect(sema.symbols.annotations(for: jsStatic).contains { annotation in
                annotation.annotationFQName == "Target"
                    && ["FUNCTION", "PROPERTY", "PROPERTY_GETTER", "PROPERTY_SETTER"].allSatisfy { target in
                        annotation.arguments.contains { $0.contains(target) }
                    }
            })
        }

        @Test
        func markerOnlyUseInObjectDoesNotBecomeJsStaticMember() throws {
            let ctx = makeContextFromSource("""
            @file:OptIn(kotlin.js.ExperimentalJsStatic::class)
            package jscontract

            object JsHolder {
                @kotlin.js.ExperimentalJsStatic
                fun message(): String = "marker"
            }

            fun main() {
                println(JsHolder.message())
            }
            """)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let markerOnly = try #require(sema.symbols.lookup(
                fqName: ["jscontract", "JsHolder", "message"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.annotations(for: markerOnly).contains {
                $0.annotationFQName == "kotlin.js.ExperimentalJsStatic"
            })
            #expect(!sema.symbols.annotations(for: markerOnly).contains {
                $0.annotationFQName == "kotlin.js.JsStatic"
            })
        }

        @Test
        func receiverVisibilityAndConstRulesMatchKotlinJS() throws {
            let ctx = makeContextFromSource("""
            @file:OptIn(kotlin.js.ExperimentalJsStatic::class)

            @kotlin.js.JsStatic
            fun topLevel() {}

            object ObjectHolder {
                @kotlin.js.JsStatic
                fun objectMember() {}
            }

            class Ordinary {
                @kotlin.js.JsStatic
                fun instanceMember() {}
                companion object {
                    @kotlin.js.JsStatic
                    private fun hidden() {}
                    @kotlin.js.JsStatic
                    const val answer: Int = 7
                    @kotlin.js.JsStatic
                    var limited: Int = 7
                        private set
                    @kotlin.js.JsStatic
                    fun valid() {}
                }
            }

            fun main() {}
            """)
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics
            let ast = try #require(ctx.ast)
            let limited = try #require(ast.arena.declarations().compactMap { declaration -> PropertyDecl? in
                guard case let .propertyDecl(property) = declaration,
                      ctx.interner.resolve(property.name) == "limited"
                else {
                    return nil
                }
                return property
            }.first)
            #expect(limited.setter?.visibility == .private, "Expected private setter visibility in the AST: \(limited.setter)")
            #expect(diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-JS-STATIC-NOT-IN-CLASS-COMPANION"
            }.count == 2, "\(diagnostics)")
            #expect(diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-JS-STATIC-ON-NON-PUBLIC-MEMBER"
            }.count == 2, "\(diagnostics)")
            #expect(diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-JS-STATIC-ON-CONST"
            }.count == 1, "\(diagnostics)")
        }

        @Test
        func targetArgumentsAndOptInAreChecked() throws {
            let invalid = makeContextFromSource("""
            @file:OptIn(kotlin.js.ExperimentalJsStatic::class)

            @kotlin.js.JsStatic
            class InvalidTarget

            @kotlin.js.ExperimentalJsStatic("unexpected")
            class InvalidMarkerArguments

            @kotlin.js.JsStatic("unexpected")
            fun invalidArguments() {}

            fun main() {}
            """)
            try runSema(invalid)
            #expect(invalid.diagnostics.hasError, "\(invalid.diagnostics.diagnostics)")
            #expect(invalid.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-JS-ANNOTATION-TOO-MANY-ARGUMENTS" && $0.severity == .error
            }.count == 2, "Both JS annotations have zero-argument declarations: \(invalid.diagnostics.diagnostics)")
            #expect(invalid.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" && $0.severity == .error
            }, "\(invalid.diagnostics.diagnostics)")

            let missingOptIn = makeContextFromSource("""
            class Holder {
                companion object {
                    @kotlin.js.JsStatic
                    fun message(): String = "message"
                }
            }

            fun useMessage(): String = Holder.message()
            """)
            try runSema(missingOptIn)
            #expect(!missingOptIn.diagnostics.hasError, "\(missingOptIn.diagnostics.diagnostics)")
            #expect(missingOptIn.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
            }, "\(missingOptIn.diagnostics.diagnostics)")
        }
    }
#endif
