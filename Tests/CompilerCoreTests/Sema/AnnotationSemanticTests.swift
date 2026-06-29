#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AnnotationSemanticTests {
    @Test func testDeprecatedLevelErrorEmitsErrorAtCallSite() {
        let source = """
        @Deprecated("Use replacement", level = DeprecationLevel.ERROR)
        fun oldApi(): Int = 1

        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        let v0 = diagnostics.contains(where: isError)
        #expect(v0, "Expected deprecated(error) diagnostic, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDeprecatedLevelErrorCanBeSuppressedWithDeprecationError() {
        let source = """
        @Deprecated("Use replacement", level = DeprecationLevel.ERROR)
        fun oldApi(): Int = 1

        @Suppress("DEPRECATION_ERROR")
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.isEmpty, "Expected deprecated(error) diagnostic to be suppressed, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDeprecatedStdlibApisCanBeSuppressedWithDeprecationError() {
        let source = """
        import kotlin.io.createTempDir
        import kotlin.io.createTempFile

        @Suppress("DEPRECATION_ERROR", "KSWIFTK-SEMA-DEPRECATED")
        fun caller() {
            val legacyChar = 65.toChar()
            println(legacyChar)
            val legacySlice = "kotlin".subSequence(1, 4)
            println(legacySlice)
            val tempDir = createTempDir(prefix = "kswiftk-", suffix = "-dir")
            val tempFile = createTempFile(prefix = "kswiftk-", suffix = ".tmp", directory = tempDir)
            println(tempFile)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.isEmpty, "Expected stdlib deprecation diagnostics to be suppressed, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDeprecatedDefaultEmitsWarningAtCallSite() {
        let source = """
        @Deprecated("Use replacement")
        fun oldApi(): Int = 1

        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        let v1 = diagnostics.contains(where: isWarning)
        #expect(v1, "Expected deprecated(warning) diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v2 = diagnostics.contains(where: isError)
        #expect(!v2, "Did not expect deprecated(error) diagnostic for default level")
    }

    @Test func testDeprecatedOnCompanionMemberEmitsWarning() {
        let source = """
        class Host {
            companion object {
                @Deprecated("Use create2")
                fun create(): Int = 1
            }
        }

        fun caller(): Int = Host.create()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        let v3 = diagnostics.contains(where: isWarning)
        #expect(v3, "Expected deprecated warning on companion call, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDeprecatedReplaceWithAddsMessageAndCodeAction() {
        let source = """
        @Deprecated("Use replacement", replaceWith = ReplaceWith("newApi()"))
        fun oldApi(): Int = 1

        fun newApi(): Int = 2
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v4 = diagnostics.contains(where: isWarning)
        #expect(v4, "Expected deprecated warning, got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
        #expect(diagnostics[0].codeActions.map(\.title) == ["Replace with 'newApi()'"])
    }

    @Test func testDeprecatedReplaceWithNamedExpressionParses() {
        let source = """
        @Deprecated(
            message = "Use replacement",
            replaceWith = ReplaceWith(expression = "newApi()")
        )
        fun oldApi(): Int = 1

        fun newApi(): Int = 2
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
        #expect(diagnostics[0].codeActions.map(\.title) == ["Replace with 'newApi()'"])
    }

    @Test func testDeprecatedErrorLevelWithReplaceWithStillEmitsError() {
        let source = """
        @Deprecated("Use replacement", replaceWith = ReplaceWith("newApi()"), level = DeprecationLevel.ERROR)
        fun oldApi(): Int = 1

        fun newApi(): Int = 2
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v5 = diagnostics.contains(where: isError)
        #expect(v5, "Expected deprecated error, got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
    }

    @Test func testDeprecatedEmptyReplaceWithDoesNotAddSuggestion() {
        let source = """
        @Deprecated("Use replacement", replaceWith = ReplaceWith())
        fun oldApi(): Int = 1

        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        #expect(!(diagnostics[0].message.contains("Replace with:")), "Did not expect replaceWith message, got: \(diagnostics[0].message)")
        #expect(diagnostics[0].codeActions.isEmpty, "Did not expect code actions for empty replaceWith")
    }

    @Test func testDeprecatedSinceKotlinSurfaceHasVersionPropertiesAndDefaults() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("DeprecatedSinceKotlin"),
        ]
        let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.kind == .annotationClass)
        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbolID)
        let v6 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
        }
        #expect(
            v6,
            "DeprecatedSinceKotlin should carry its declaration target list, got: \(annotations)"
        )

        let propertyNames = ["warningSince", "errorSince", "hiddenSince"]
        for propertyName in propertyNames {
            let propertySymbol = try #require(
                sema.symbols.lookup(fqName: fqName + [ctx.interner.intern(propertyName)])
            )
            #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.stringType)
        }

        let initName = ctx.interner.intern("<init>")
        let ctorSymbol = try #require(
            sema.symbols.lookupAll(fqName: fqName + [initName]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            }
        )
        let signature = try #require(sema.symbols.functionSignature(for: ctorSymbol))
        #expect(signature.parameterTypes == Array(repeating: sema.types.stringType, count: 3))
        #expect(signature.valueParameterHasDefaultValues == [true, true, true])
        #expect(signature.valueParameterIsVararg == [false, false, false])
    }

    @Test func testDeprecatedSinceKotlinAcceptsDocumentedTargets() {
        let source = """
        @DeprecatedSinceKotlin(warningSince = "1.0", errorSince = "1.1", hiddenSince = "1.2")
        class OldClass {
            @DeprecatedSinceKotlin
            constructor()
        }

        @DeprecatedSinceKotlin
        fun oldFun() {}

        @DeprecatedSinceKotlin
        val oldProperty: Int = 1

        @DeprecatedSinceKotlin
        annotation class OldAnnotation
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected DeprecatedSinceKotlin target uses to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDeprecatedSinceKotlinRejectsFileTarget() {
        let source = """
        @file:DeprecatedSinceKotlin

        package sample
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected file-target diagnostic for DeprecatedSinceKotlin, got: \(ctx.diagnostics.diagnostics)")
        let v7 = diagnostics.allSatisfy(isError)
        #expect(v7, "Annotation-target diagnostics should be errors")
    }

    @Test func testSyntheticDeprecatedToCharEmitsWarning() {
        let source = """
        fun caller(): Char = 65.toChar()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.count == 1, "Expected one deprecated diagnostic for toChar(), got: \(ctx.diagnostics.diagnostics)")
        let v8 = diagnostics.contains(where: isWarning)
        #expect(v8, "Expected deprecated warning for toChar(), got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics[0].message.contains("toChar"), "Expected toChar() in message, got: \(diagnostics[0].message)")
    }

    @Test func testSyntheticDeprecatedStringSubSequenceEmitsWarning() {
        let source = """
        fun caller(): String = "kotlin".subSequence(1, 4).toString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.count == 1, "Expected one deprecated diagnostic for subSequence(), got: \(ctx.diagnostics.diagnostics)")
        let v9 = diagnostics.contains(where: isWarning)
        #expect(v9, "Expected deprecated warning for subSequence(), got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics[0].message.contains("subSequence"), "Expected subSequence() in message, got: \(diagnostics[0].message)")
    }

    @Test func testSyntheticDeprecatedCreateTempDirEmitsError() {
        let source = """
        import kotlin.io.createTempDir

        fun caller() = createTempDir(prefix = "demo")
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(diagnostics.count == 1, "Expected one deprecated diagnostic for createTempDir(), got: \(ctx.diagnostics.diagnostics)")
        let v10 = diagnostics.contains(where: isError)
        #expect(v10, "Expected deprecated error for createTempDir(), got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics[0].message.contains("createTempDir"), "Expected createTempDir() in message, got: \(diagnostics[0].message)")
    }

    @Test func testSuppressUncheckedCastByKotlinNameSuppressesDiagnostic() {
        let source = """
        @Suppress("UNCHECKED_CAST")
        fun suppressed(v: Any): List<String> = v as List<String>

        fun unsuppressed(v: Any): List<String> = v as List<String>
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-UNCHECKED-CAST", in: ctx)

        #expect(diagnostics.count == 1, "Expected exactly one unchecked-cast warning from unsuppressed function, got: \(diagnostics)")
        let v11 = diagnostics.allSatisfy(isWarning)
        #expect(v11, "Unchecked-cast diagnostics should be warnings")
    }

    @Test func testSuppressUncheckedCastByInternalCodeSuppressesDiagnostic() {
        let source = """
        @Suppress("KSWIFTK-SEMA-UNCHECKED-CAST")
        fun suppressed(v: Any): List<String> = v as List<String>

        fun unsuppressed(v: Any): List<String> = v as List<String>
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-UNCHECKED-CAST", in: ctx)

        #expect(diagnostics.count == 1, "Expected exactly one unchecked-cast warning from unsuppressed function, got: \(diagnostics)")
        let v12 = diagnostics.allSatisfy(isWarning)
        #expect(v12, "Unchecked-cast diagnostics should be warnings")
    }

    @Test func testAnnotationTargetEnumConstantResolves() {
        let source = """
        fun targetSmoke(): AnnotationTarget = AnnotationTarget.CLASS
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected AnnotationTarget smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testOverloadResolutionByLambdaReturnTypeResolves() {
        let source = """
        import kotlin.OverloadResolutionByLambdaReturnType

        fun marker(x: OverloadResolutionByLambdaReturnType?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected OverloadResolutionByLambdaReturnType smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExperimentalTypeInferenceResolves() {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        fun marker(x: ExperimentalTypeInference?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected ExperimentalTypeInference smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testOptInResolves() {
        let source = """
        fun marker(x: OptIn?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected OptIn smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSubclassOptInRequiredResolves() {
        let source = """
        fun marker(x: SubclassOptInRequired?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected SubclassOptInRequired smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSubclassOptInRequiredMarkerClassPropertyIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let valueSymbol = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("SubclassOptInRequired"),
                ctx.interner.intern("markerClass"),
            ]),
            "kotlin.SubclassOptInRequired.markerClass must be registered"
        )
        #expect(sema.symbols.propertyType(for: valueSymbol) != nil, "markerClass must have a property type")
    }

    @Test func testContextFunctionTypeParamsSurfaceIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let annotationFQName = [
            interner.intern("kotlin"),
            interner.intern("ContextFunctionTypeParams"),
        ]
        let annotationSymbol = try #require(
            sema.symbols.lookup(fqName: annotationFQName),
            "kotlin.ContextFunctionTypeParams must be registered"
        )
        #expect(sema.symbols.symbol(annotationSymbol)?.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: annotationSymbol)
        let v13 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments.contains("AnnotationTarget.TYPE")
        }
        #expect(v13, "ContextFunctionTypeParams must be targeted to type usages")

        let countSymbol = try #require(
            sema.symbols.lookup(fqName: annotationFQName + [interner.intern("count")]),
            "kotlin.ContextFunctionTypeParams.count must be registered"
        )
        #expect(sema.symbols.propertyType(for: countSymbol) == sema.types.intType)

        let ctorSymbol = try #require(
            sema.symbols.lookupAll(fqName: annotationFQName + [interner.intern("<init>")]).first(where: {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.intType]
            }),
            "kotlin.ContextFunctionTypeParams(count: Int) constructor must be registered"
        )
        #expect(sema.symbols.functionSignature(for: ctorSymbol)?.returnType == sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        ))))
    }

    @Test func testContextFunctionTypeParamsResolvesAnnotatedFunctionType() throws {
        let source = """
        interface Host {
            val action: @ContextFunctionTypeParams(2) @ExtensionFunctionType Function4<String, Int, Double, Byte, Unit>
            val block: @ContextFunctionTypeParams(count = 1) Function2<String, Byte, Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected ContextFunctionTypeParams source to compile cleanly, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let file = try #require(ast.files.first)
        let interfaceDeclID = try #require(
            file.topLevelDecls.first(where: {
                if case .interfaceDecl = ast.arena.decl($0) {
                    return true
                }
                return false
            })
        )
        guard case let .interfaceDecl(interfaceDecl) = ast.arena.decl(interfaceDeclID) else {
            Issue.record("Expected interface declaration")
            return
        }

        let actionPropertyType = try propertyType(named: "action", in: interfaceDecl, ast: ast, sema: sema, interner: ctx.interner)
        guard case let .functionType(actionFunctionType) = sema.types.kind(of: actionPropertyType) else {
            Issue.record("Expected action to resolve as a function type")
            return
        }
        #expect(actionFunctionType.contextReceivers == [sema.types.stringType, sema.types.intType])
        #expect(actionFunctionType.receiver == sema.types.doubleType)
        #expect(actionFunctionType.params == [sema.types.intType])
        #expect(actionFunctionType.returnType == sema.types.unitType)

        let blockPropertyType = try propertyType(named: "block", in: interfaceDecl, ast: ast, sema: sema, interner: ctx.interner)
        guard case let .functionType(blockFunctionType) = sema.types.kind(of: blockPropertyType) else {
            Issue.record("Expected block to resolve as a function type, got \(sema.types.renderType(blockPropertyType))")
            return
        }
        #expect(blockFunctionType.contextReceivers == [sema.types.stringType])
        #expect(blockFunctionType.receiver == nil)
        #expect(blockFunctionType.params == [sema.types.intType])
        #expect(blockFunctionType.returnType == sema.types.unitType)
    }

    @Test func testContextFunctionTypeParamsRejectsDeclarationUsage() {
        let source = """
        @ContextFunctionTypeParams(1)
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v14 = diagnostics.allSatisfy(isError)
        #expect(v14, "Annotation-target diagnostics should be errors")
    }

    @Test func testContextFunctionTypeParamsRejectsTooLargeCount() {
        let source = """
        interface Host {
            val invalid: @ContextFunctionTypeParams(3) Function2<String, Int, Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-CONTEXT-FN-TYPE", in: ctx)

        #expect(diagnostics.count == 1, "Expected one context-function-type diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v15 = diagnostics.allSatisfy(isError)
        #expect(v15, "Context-function-type diagnostics should be errors")
    }

    @Test func testConsistentCopyVisibilityResolvesAndTargetsClasses() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let symbol = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ConsistentCopyVisibility"),
            ]),
            "kotlin.ConsistentCopyVisibility must be registered"
        )
        let annotations = sema.symbols.annotations(for: symbol)
        let v16 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.CLASS"]
        }
        #expect(
            v16,
            "ConsistentCopyVisibility should target classes, got: \(annotations)"
        )
    }

    @Test func testConsistentCopyVisibilityRejectsFunctionUse() {
        let source = """
        @ConsistentCopyVisibility
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected class-only annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v17 = diagnostics.allSatisfy(isError)
        #expect(v17, "Annotation-target diagnostics should be errors")
    }

    @Test func testMustUseReturnValuesResolvesAndTargetsFileAndClass() throws {
        let source = """
        fun marker(x: MustUseReturnValues?): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let symbol = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("MustUseReturnValues"),
            ]),
            "kotlin.MustUseReturnValues must be registered"
        )
        let symbolInfo = try #require(sema.symbols.symbol(symbol))
        #expect(symbolInfo.kind == .annotationClass, "MustUseReturnValues must be an annotation class")

        let annotations = sema.symbols.annotations(for: symbol)
        let v18 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && Set($0.arguments) == Set(["AnnotationTarget.FILE", "AnnotationTarget.CLASS"])
        }
        #expect(
            v18,
            "MustUseReturnValues should target files and classes, got: \(annotations)"
        )
    }

    @Test func testMustUseReturnValuesAllowsClassUse() {
        let source = """
        @MustUseReturnValues
        class ApiScope
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected @MustUseReturnValues to be accepted on classes, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testMustUseReturnValuesAllowsFileUse() {
        let source = """
        @file:MustUseReturnValues

        fun api(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected @file:MustUseReturnValues to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testMustUseReturnValuesRejectsFunctionUse() {
        let source = """
        @MustUseReturnValues
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected file-or-class annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v19 = diagnostics.allSatisfy(isError)
        #expect(v19, "Annotation-target diagnostics should be errors")
    }

    @Test func testBuilderInferenceAnnotationSurfaceIsSyntheticAndTargeted() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let symbolID = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("BuilderInference"),
            ]),
            "kotlin.BuilderInference must be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.kind == .annotationClass)
        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbolID)
        let v20 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == [
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                ]
        }
        #expect(
            v20,
            "BuilderInference should target value parameters, functions, and properties, got: \(annotations)"
        )
        let v21 = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments == ["AnnotationRetention.BINARY"]
        }
        #expect(
            v21,
            "BuilderInference should carry binary retention, got: \(annotations)"
        )
        let v22 = annotations.contains {
            KnownCompilerAnnotation.experimentalTypeInference.matches($0.annotationFQName)
        }
        #expect(
            v22,
            "BuilderInference should be annotated with ExperimentalTypeInference, got: \(annotations)"
        )
    }

    @Test func testBuilderInferenceAcceptsDocumentedTargets() {
        let source = """
        @BuilderInference
        fun builderFunction(block: () -> Unit) {}

        fun acceptsValueParameter(@BuilderInference block: () -> Unit) {}

        @BuilderInference
        val builderProperty: Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected BuilderInference target uses to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testBuilderInferenceRejectsClassTarget() {
        let source = """
        @BuilderInference
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected class-target diagnostic for BuilderInference, got: \(ctx.diagnostics.diagnostics)")
        let v23 = diagnostics.allSatisfy(isError)
        #expect(v23, "Annotation-target diagnostics should be errors")
    }

    @Test func testIgnorableReturnValueResolvesAndTargetsFunctions() throws {
        let source = """
        fun marker(x: IgnorableReturnValue?): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let symbol = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("IgnorableReturnValue"),
            ]),
            "kotlin.IgnorableReturnValue must be registered"
        )
        let symbolInfo = try #require(sema.symbols.symbol(symbol))
        #expect(symbolInfo.kind == .annotationClass, "IgnorableReturnValue must be an annotation class")

        let annotations = sema.symbols.annotations(for: symbol)
        let v24 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.FUNCTION"]
        }
        #expect(
            v24,
            "IgnorableReturnValue should target functions, got: \(annotations)"
        )
    }

    @Test func testIgnorableReturnValueAllowsFunctionUse() {
        let source = """
        @IgnorableReturnValue
        fun ignored(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected @IgnorableReturnValue to be accepted on functions, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testIgnorableReturnValueRejectsClassUse() {
        let source = """
        @IgnorableReturnValue
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected function-only annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v25 = diagnostics.allSatisfy(isError)
        #expect(v25, "Annotation-target diagnostics should be errors")
    }

    @Test func testExposedCopyVisibilityResolvesAndTargetsClasses() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let symbol = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ExposedCopyVisibility"),
            ]),
            "kotlin.ExposedCopyVisibility must be registered"
        )

        let annotations = sema.symbols.annotations(for: symbol)
        let v26 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.CLASS"]
        }
        #expect(
            v26,
            "ExposedCopyVisibility should target classes, got: \(annotations)"
        )
    }

    @Test func testDslMarkerResolvesAndTargetsAnnotationClasses() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let symbol = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("DslMarker"),
            ]),
            "kotlin.DslMarker must be registered"
        )
        let declaration = try #require(sema.symbols.symbol(symbol))

        #expect(declaration.kind == .annotationClass)
        #expect(declaration.visibility == .public)
        #expect(declaration.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbol)
        let v27 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
        }
        #expect(
            v27,
            "DslMarker should target annotation classes, got: \(annotations)"
        )
    }

    @Test func testExposedCopyVisibilityRejectsFunctionUse() {
        let source = """
        @ExposedCopyVisibility
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected class-only annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v28 = diagnostics.allSatisfy(isError)
        #expect(v28, "Annotation-target diagnostics should be errors")
    }

    @Test func testParameterNameSurfaceHasNamePropertyConstructorAndTypeTarget() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("ParameterName"),
        ]
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let declaration = try #require(sema.symbols.symbol(symbol))

        #expect(declaration.kind == .annotationClass)
        #expect(declaration.visibility == .public)
        #expect(declaration.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbol)
        let v29 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.TYPE"]
        }
        #expect(
            v29,
            "ParameterName should target type uses, got: \(annotations)"
        )
        let v30 = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments == ["AnnotationRetention.BINARY"]
        }
        #expect(
            v30,
            "ParameterName should carry binary retention, got: \(annotations)"
        )

        let propertySymbol = try #require(
            sema.symbols.lookup(fqName: fqName + [ctx.interner.intern("name")])
        )
        #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.stringType)

        let ctorSymbol = try #require(
            sema.symbols.lookupAll(fqName: fqName + [ctx.interner.intern("<init>")]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            }
        )
        let signature = try #require(sema.symbols.functionSignature(for: ctorSymbol))
        #expect(signature.parameterTypes == [sema.types.stringType])
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [false])
    }

    @Test func testParameterNameAcceptsTypeUse() {
        let source = """
        interface Host {
            val value: @ParameterName(name = "value") String
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)

        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected ParameterName on a type use to compile, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testParameterNameRejectsClassUse() {
        let source = """
        @ParameterName("Bad")
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected ParameterName to reject class use, got: \(ctx.diagnostics.diagnostics)")
        let v31 = diagnostics.allSatisfy(isError)
        #expect(v31, "Annotation-target diagnostics should be errors")
    }

    @Test func testPublishedApiSurfaceHasDeclarationTargetsAndBinaryRetention() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let symbol = try #require(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("PublishedApi"),
            ]),
            "kotlin.PublishedApi must be registered"
        )
        let declaration = try #require(sema.symbols.symbol(symbol))

        #expect(declaration.kind == .annotationClass)
        #expect(declaration.visibility == .public)
        #expect(declaration.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbol)
        let v32 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                ]
        }
        #expect(
            v32,
            "PublishedApi should target public ABI declaration sites, got: \(annotations)"
        )
        let v33 = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments == ["AnnotationRetention.BINARY"]
        }
        #expect(
            v33,
            "PublishedApi should carry binary retention, got: \(annotations)"
        )
    }

    @Test func testPublishedApiAcceptsDocumentedDeclarationTargets() {
        let source = """
        @PublishedApi
        internal class InternalHost {
            @PublishedApi
            internal val value: Int = 1

            @PublishedApi
            internal fun expose(): Int = value
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected PublishedApi declaration targets to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testPublishedApiRejectsFileTarget() {
        let source = """
        @file:PublishedApi

        package sample
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected PublishedApi to reject file target, got: \(ctx.diagnostics.diagnostics)")
        let v34 = diagnostics.allSatisfy(isError)
        #expect(v34, "Annotation-target diagnostics should be errors")
    }

    @Test func testDslMarkerAcceptsAnnotationClassAndRejectsRegularClassUse() {
        let source = """
        @DslMarker
        annotation class HtmlDsl

        @DslMarker
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected DslMarker to reject regular class use, got: \(ctx.diagnostics.diagnostics)")
        let v35 = diagnostics.allSatisfy(isError)
        #expect(v35, "Annotation-target diagnostics should be errors")
    }

    @Test func testDslMarkerCanMarkCustomDslAnnotation() {
        let source = """
        @DslMarker
        annotation class HtmlDsl

        @HtmlDsl
        class Tag
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected custom DslMarker annotation to compile, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testPrivateDataClassCopyVisibilityMigrationWarnsAndKeepsPublicCopy() throws {
        let source = """
        package test

        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        #expect(diagnostics.count == 1, "Expected one data class copy visibility warning, got: \(ctx.diagnostics.diagnostics)")
        let v36 = diagnostics.allSatisfy(isWarning)
        #expect(v36, "Data class copy visibility diagnostic should be a warning")
        #expect(diagnostics[0].message.contains("private"), "Expected primary constructor visibility in message, got: \(diagnostics[0].message)")
        #expect(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx) == .public,
            "Unannotated migration mode should keep copy() public"
        )
    }

    @Test func testConsistentCopyVisibilityMakesCopyUseConstructorVisibility() throws {
        let source = """
        package test

        @ConsistentCopyVisibility
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        #expect(diagnostics.isEmpty, "Expected ConsistentCopyVisibility to opt in to constructor visibility, got: \(ctx.diagnostics.diagnostics)")
        #expect(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx) == .private,
            "Annotated data class copy() should use the private primary constructor visibility"
        )
    }

    @Test func testExposedCopyVisibilitySuppressesWarningAndKeepsPublicCopy() throws {
        let source = """
        package test

        @ExposedCopyVisibility
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        #expect(diagnostics.isEmpty, "Expected ExposedCopyVisibility to suppress migration warning, got: \(ctx.diagnostics.diagnostics)")
        #expect(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx) == .public,
            "ExposedCopyVisibility should keep copy() public"
        )
    }

    @Test func testDataClassCopyVisibilityWarningCanBeSuppressedByAlias() {
        let source = """
        @Suppress("DATA_CLASS_COPY_VISIBILITY")
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        #expect(diagnostics.isEmpty, "Expected DATA_CLASS_COPY_VISIBILITY suppression alias to suppress diagnostic, got: \(ctx.diagnostics.diagnostics)")
    }

}
#endif
