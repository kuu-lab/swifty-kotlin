#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `SinceKotlin` / data-class copy-visibility / DSL-marker / and other
/// version- and visibility-related annotation tests, split out from
/// `AnnotationSemanticTests` to keep each test source under ~1500 lines.
extension AnnotationSemanticTests {
    @Test func testSinceKotlinSurfaceHasVersionPropertyConstructorAndTargets() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let sinceKotlinFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("SinceKotlin"),
        ]
        let symbolID = try #require(
            sema.symbols.lookup(fqName: sinceKotlinFQName),
            "kotlin.SinceKotlin must be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        let v0 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
        }
        #expect(
            v0,
            "SinceKotlin should carry declaration target metadata, got: \(annotations)"
        )

        let versionSymbol = try #require(
            sema.symbols.lookup(fqName: sinceKotlinFQName + [ctx.interner.intern("version")]),
            "SinceKotlin.version property must be registered"
        )
        #expect(sema.symbols.propertyType(for: versionSymbol) == sema.types.stringType)

        let constructors = sema.symbols.lookupAll(fqName: sinceKotlinFQName + [ctx.interner.intern("<init>")])
        let constructorSignature = try #require(
            constructors.lazy.compactMap { sema.symbols.functionSignature(for: $0) }.first { signature in
                signature.parameterTypes == [sema.types.stringType]
            },
            "SinceKotlin(version: String) constructor must be registered"
        )
        #expect(constructorSignature.valueParameterSymbols.count == 1)
        let parameter = try #require(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0]))
        #expect(ctx.interner.resolve(parameter.name) == "version")
    }

    @Test func testSinceKotlinAcceptsDocumentedDeclarationTargets() {
        let source = """
        @SinceKotlin("1.0")
        class Stable {
            @SinceKotlin(version = "1.1")
            val value: Int = 1

            @SinceKotlin("1.2")
            fun expose(): Int = value
        }

        @SinceKotlin("1.3")
        typealias StableAlias = Stable
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected SinceKotlin declaration targets to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSinceKotlinRejectsFileTarget() {
        let source = """
        @file:SinceKotlin("1.0")

        package sample
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected SinceKotlin to reject file target, got: \(ctx.diagnostics.diagnostics)")
        let v1 = diagnostics.allSatisfy(isError)
        #expect(v1, "Annotation-target diagnostics should be errors")
    }

    @Test func testDslMarkerSurfaceHasDocumentedMetadata() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let dslMarkerFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("DslMarker"),
        ]
        let symbolID = try #require(
            sema.symbols.lookup(fqName: dslMarkerFQName),
            "kotlin.DslMarker must be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        let v2 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
        }
        #expect(
            v2,
            "DslMarker should target annotation classes, got: \(annotations)"
        )
        let v3 = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments == ["AnnotationRetention.BINARY"]
        }
        #expect(
            v3,
            "DslMarker should carry binary retention, got: \(annotations)"
        )
        let v4 = annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" }
        #expect(
            v4,
            "DslMarker should carry MustBeDocumented, got: \(annotations)"
        )
        let v5 = annotations.contains {
            KnownCompilerAnnotation.sinceKotlin.matches($0.annotationFQName)
                && $0.arguments == ["1.1"]
        }
        #expect(
            v5,
            "DslMarker should carry SinceKotlin(1.1), got: \(annotations)"
        )
    }

    @Test func testDslMarkerAcceptsAnnotationClassTarget() {
        let source = """
        @DslMarker
        annotation class HtmlDsl
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected DslMarker to be accepted on annotation classes, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDslMarkerRejectsRegularClassTarget() {
        let source = """
        @DslMarker
        class BadMarker
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected annotation-class-only target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v6 = diagnostics.allSatisfy(isError)
        #expect(v6, "Annotation-target diagnostics should be errors")
    }

    @Test func testIntroducedAtSurfaceHasVersionPropertyConstructorAndValueParameterTarget() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let introducedAtFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("IntroducedAt"),
        ]
        let symbolID = try #require(
            sema.symbols.lookup(fqName: introducedAtFQName),
            "kotlin.IntroducedAt must be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        let v7 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.VALUE_PARAMETER"]
        }
        #expect(
            v7,
            "IntroducedAt should target value parameters, got: \(annotations)"
        )
        let v8 = annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" }
        #expect(
            v8,
            "IntroducedAt should be documented in the public API, got: \(annotations)"
        )
        let v9 = annotations.contains {
            KnownCompilerAnnotation.experimentalVersionOverloading.matches($0.annotationFQName)
        }
        #expect(
            v9,
            "IntroducedAt should require ExperimentalVersionOverloading opt-in, got: \(annotations)"
        )

        let versionSymbol = try #require(
            sema.symbols.lookup(fqName: introducedAtFQName + [ctx.interner.intern("version")]),
            "IntroducedAt.version property must be registered"
        )
        #expect(sema.symbols.propertyType(for: versionSymbol) == sema.types.stringType)

        let constructors = sema.symbols.lookupAll(fqName: introducedAtFQName + [ctx.interner.intern("<init>")])
        let constructorSignature = try #require(
            constructors.lazy.compactMap { sema.symbols.functionSignature(for: $0) }.first { signature in
                signature.parameterTypes == [sema.types.stringType]
            },
            "IntroducedAt(version: String) constructor must be registered"
        )
        #expect(constructorSignature.valueParameterSymbols.count == 1)
        let parameter = try #require(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0]))
        #expect(ctx.interner.resolve(parameter.name) == "version")
    }

    @Test func testIntroducedAtAllowsValueParameterUse() {
        let source = """
        fun sample(@IntroducedAt("1.1") value: Int = 0): Int = value
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected IntroducedAt value-parameter target to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testIntroducedAtRejectsClassTarget() {
        let source = """
        @IntroducedAt("1.1")
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected IntroducedAt to reject class target, got: \(ctx.diagnostics.diagnostics)")
        let v10 = diagnostics.allSatisfy(isError)
        #expect(v10, "Annotation-target diagnostics should be errors")
    }

    @Test func testOptionalExpectationSurfaceIsSyntheticTargetedAndExperimental() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let optionalExpectationFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("OptionalExpectation"),
        ]
        let symbolID = try #require(
            sema.symbols.lookup(fqName: optionalExpectationFQName),
            "kotlin.OptionalExpectation must be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        let v11 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
        }
        #expect(
            v11,
            "OptionalExpectation should target annotation classes, got: \(annotations)"
        )
        let v12 = annotations.contains { $0.annotationFQName == "kotlin.ExperimentalMultiplatform" }
        #expect(
            v12,
            "OptionalExpectation should require ExperimentalMultiplatform opt-in, got: \(annotations)"
        )
    }

    @Test func testOptionalExpectationAcceptsAnnotationClassTarget() {
        let source = """
        @OptionalExpectation
        annotation class PlatformMarker
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected OptionalExpectation annotation-class target to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testOptionalExpectationRejectsFunctionTarget() {
        let source = """
        @OptIn(ExperimentalMultiplatform::class)
        @OptionalExpectation
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected OptionalExpectation to reject function target, got: \(ctx.diagnostics.diagnostics)")
        let v13 = diagnostics.allSatisfy(isError)
        #expect(v13, "Annotation-target diagnostics should be errors")
    }

    @Test func testRootThrowsSurfaceHasVarargKClassPropertyConstructorAndTargets() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let throwsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("Throws"),
        ]
        let symbolID = try #require(
            sema.symbols.lookup(fqName: throwsFQName),
            "kotlin.Throws must be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        let v14 = annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments == [
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.CONSTRUCTOR",
                ]
        }
        #expect(
            v14,
            "Throws should carry function/getter/setter/constructor target metadata, got: \(annotations)"
        )

        let exceptionClassesSymbol = try #require(
            sema.symbols.lookup(fqName: throwsFQName + [ctx.interner.intern("exceptionClasses")]),
            "Throws.exceptionClasses property must be registered"
        )
        let exceptionClassesType = try #require(sema.symbols.propertyType(for: exceptionClassesSymbol))
        try assertArrayOfOutThrowableKClass(exceptionClassesType, in: sema, interner: ctx.interner)

        let constructors = sema.symbols.lookupAll(fqName: throwsFQName + [ctx.interner.intern("<init>")])
        let constructorSignature = try #require(
            constructors.lazy.compactMap { sema.symbols.functionSignature(for: $0) }.first { signature in
                signature.valueParameterIsVararg == [true]
                    && signature.valueParameterSymbols.count == 1
            },
            "Throws(vararg exceptionClasses: KClass<out Throwable>) constructor must be registered"
        )
        try assertThrowableKClass(constructorSignature.parameterTypes[0], in: sema, interner: ctx.interner)
        let parameter = try #require(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0]))
        #expect(ctx.interner.resolve(parameter.name) == "exceptionClasses")
    }

    @Test func testRootThrowsAcceptsDocumentedDeclarationTargets() {
        let source = """
        class Host @Throws(Throwable::class) constructor() {
            @get:Throws(Throwable::class)
            val readonly: Int = 1

            @set:Throws(Throwable::class)
            var value: Int = 0

            @Throws(Throwable::class)
            fun expose(): Int = value
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected Throws declaration targets to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testRootThrowsRejectsClassTarget() {
        let source = """
        @Throws(Throwable::class)
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected Throws to reject class target, got: \(ctx.diagnostics.diagnostics)")
        let v15 = diagnostics.allSatisfy(isError)
        #expect(v15, "Annotation-target diagnostics should be errors")
    }

    @Test func testTargetAnnotationIsRejectedOnRegularClass() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        class BadTarget
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v16 = diagnostics.allSatisfy(isError)
        #expect(v16, "Annotation-target diagnostics should be errors")
    }

    @Test func testTargetAnnotationAllowsAnnotationClassButRejectsFunctionUsage() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly

        @ClassOnly
        class Good

        @ClassOnly
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected exactly one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v17 = diagnostics.allSatisfy(isError)
        #expect(v17, "Annotation-target diagnostics should be errors")
    }

    @Test func testMustBeDocumentedAnnotationIsSyntheticAndTargetedToAnnotationClasses() throws {
        let source = """
        annotation class ExperimentalApi
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let mustBeDocumentedFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("annotation"),
            ctx.interner.intern("MustBeDocumented"),
        ]
        let symbolID = try #require(sema.symbols.lookup(fqName: mustBeDocumentedFQName))
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol.id)
        let v18 = annotations.contains(
            where: {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
            }
        )
        #expect(
            v18,
            "Expected MustBeDocumented to carry @Target(AnnotationTarget.ANNOTATION_CLASS), got: \(annotations)"
        )
    }

    @Test func testAnnotationClassInheritsKotlinAnnotation() throws {
        let source = """
        annotation class MyAnnotation
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let kotlinAnnotationSymbol = try #require(
            sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Annotation")])
        )
        let myAnnotationSymbol = try #require(
            sema.symbols.lookup(fqName: [ctx.interner.intern("MyAnnotation")])
        )

        #expect(sema.symbols.symbol(myAnnotationSymbol)?.kind == .annotationClass)
        let v19 = sema.symbols.directSupertypes(for: myAnnotationSymbol).contains(kotlinAnnotationSymbol)
        #expect(
            v19,
            "Annotation classes should implicitly inherit kotlin.Annotation"
        )
    }

    @Test func testExperimentalContractsAnnotationIsSyntheticAnnotationClass() throws {
        let source = """
        annotation class ExperimentalApi
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
            ctx.interner.intern("ExperimentalContracts"),
        ]
        let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol.id)
        let v20 = annotations.contains(
            where: {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.TYPEALIAS",
                    ]
            }
        )
        #expect(
            v20,
            "Expected ExperimentalContracts to carry @Target for class/function/property/typealias, got: \(annotations)"
        )
        let v21 = annotations.contains(
            where: {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            }
        )
        #expect(
            v21,
            "Expected ExperimentalContracts to carry @Retention(AnnotationRetention.BINARY), got: \(annotations)"
        )
    }

    @Test func testExperimentalExtendedContractsAnnotationIsSyntheticOptInMarker() throws {
        let source = """
        fun noop() {}
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
            ctx.interner.intern("ExperimentalExtendedContracts"),
        ]
        let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol.id)
        let v22 = annotations.contains { $0.annotationFQName == "kotlin.RequiresOptIn" }
        #expect(
            v22,
            "Expected ExperimentalExtendedContracts to carry @RequiresOptIn, got: \(annotations)"
        )
        let v23 = annotations.contains(
            where: {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.TYPEALIAS",
                    ]
            }
        )
        #expect(
            v23,
            "Expected ExperimentalExtendedContracts to carry @Target for class/function/property/typealias, got: \(annotations)"
        )
        let v24 = annotations.contains(
            where: {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            }
        )
        #expect(
            v24,
            "Expected ExperimentalExtendedContracts to carry @Retention(AnnotationRetention.BINARY), got: \(annotations)"
        )
    }

    @Test func testExperimentalExtendedContractsRequiresOptIn() {
        let source = """
        import kotlin.contracts.ExperimentalExtendedContracts

        @ExperimentalExtendedContracts
        fun extendedApi(): Int = 1

        fun caller(): Int = extendedApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected one ExperimentalExtendedContracts opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v25 = diagnostics.allSatisfy(isError)
        #expect(v25, "ExperimentalExtendedContracts opt-in diagnostics should be errors")
    }

    @Test func testOverloadResolutionByLambdaReturnTypeRejectsClassTarget() {
        let source = """
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.OptIn
        import kotlin.experimental.ExperimentalTypeInference

        @Target(AnnotationTarget.CLASS)
        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 2, "Expected target diagnostics for both @Target and @OverloadResolutionByLambdaReturnType misuse, got: \(ctx.diagnostics.diagnostics)")
        let v26 = diagnostics.allSatisfy(isError)
        #expect(v26, "Annotation-target diagnostics should be errors")
    }

    @Test func testExperimentalTypeInferenceAcceptsFunctionTarget() {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        @ExperimentalTypeInference
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "ExperimentalTypeInference should be accepted on functions, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testOverloadResolutionByLambdaReturnTypeRequiresOptIn() {
        let source = """
        import kotlin.OverloadResolutionByLambdaReturnType

        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = block()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPTIN", in: ctx)

        #expect(diagnostics.count == 1, "Expected one opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v27 = diagnostics.allSatisfy(isError)
        #expect(v27, "Opt-in diagnostics should be errors")
    }

    @Test func testOverloadResolutionByLambdaReturnTypeAcceptsOptIn() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = block()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPTIN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected opt-in diagnostic to be suppressed by @OptIn, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testFieldTargetAllowsBackedFieldAndRejectsMissingBackingField() {
        let source = """
        @Target(value = [AnnotationTarget.FIELD])
        annotation class FieldOnly

        class Storage {
            @field:FieldOnly val stored: String = ""
        }

        class Missing {
            @field:FieldOnly val missing: String
                get() = "x"
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected exactly one annotation-target diagnostic for the missing backing field, got: \(ctx.diagnostics.diagnostics)")
        let v28 = diagnostics.allSatisfy(isError)
        #expect(v28, "Annotation-target diagnostics should be errors")
    }

    @Test func testFieldTargetRejectsExtensionProperty() {
        let source = """
        @Target(value = [AnnotationTarget.FIELD])
        annotation class FieldOnly

        @field:FieldOnly
        val String.ext: Int
            get() = length
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic for the extension property, got: \(ctx.diagnostics.diagnostics)")
        let v29 = diagnostics.allSatisfy(isError)
        #expect(v29, "Annotation-target diagnostics should be errors")
    }

    @Test func testAnnotationTargetSuppressionAliasSuppressesDiagnostic() {
        let source = """
        @Suppress("ANNOTATION_TARGET")
        @Target(AnnotationTarget.CLASS)
        class BadTarget
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.isEmpty, "Expected ANNOTATION_TARGET suppression alias to suppress annotation-target diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testWasExperimentalAnnotationIsCollectedOnDeclaration() throws {
        let source = """
        annotation class ExperimentalApi

        @WasExperimental(markerClass = ExperimentalApi::class)
        fun stabilizedApi(): Int = 42
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let symbolID = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("stabilizedApi")]).first)
        let annotations = sema.symbols.annotations(for: symbolID)
        let annotation = try #require(annotations.first(where: {
            KnownCompilerAnnotation.wasExperimental.matches($0.annotationFQName)
        }))

        #expect(annotation.arguments == ["markerClass=ExperimentalApi::class"])
    }

    @Test func testExtensionFunctionTypeResolvesInterfacePropertyAndTypeAlias() throws {
        let source = """
        interface Host {
            val receiverAction: @ExtensionFunctionType Function1<String, Unit>
        }

        typealias Action = @ExtensionFunctionType Function2<String, Int, Unit>
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected extension function type source to compile cleanly, got: \(ctx.diagnostics.diagnostics)")

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
        let propertyDeclID = try #require(interfaceDecl.memberProperties.first)
        let propertySymbol = try #require(sema.bindings.declSymbol(for: propertyDeclID))
        let propertyType = try #require(sema.symbols.propertyType(for: propertySymbol))

        if case let .functionType(functionType) = sema.types.kind(of: propertyType) {
            #expect(functionType.receiver == sema.types.stringType)
            #expect(functionType.params.isEmpty)
            #expect(functionType.returnType == sema.types.unitType)
            #expect(!functionType.isSuspend)
        } else {
            Issue.record("Expected interface property type to resolve as functionType")
        }

        let actionSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Action")]))
        let actionUnderlyingType = try #require(sema.symbols.typeAliasUnderlyingType(for: actionSymbol))

        if case let .functionType(functionType) = sema.types.kind(of: actionUnderlyingType) {
            #expect(functionType.receiver == sema.types.stringType)
            #expect(functionType.params == [sema.types.intType])
            #expect(functionType.returnType == sema.types.unitType)
            #expect(!functionType.isSuspend)
        } else {
            Issue.record("Expected typealias underlying type to resolve as functionType")
        }
    }

    @Test func testExtensionFunctionTypeRejectsFunction0() {
        let source = """
        interface Host {
            val invalid: @ExtensionFunctionType Function0<Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-EXTFN-TYPE", in: ctx)

        #expect(diagnostics.count == 1, "Expected one extension-function-type diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v30 = diagnostics.allSatisfy(isError)
        #expect(v30, "Extension-function-type diagnostics should be errors")
    }

    @Test func testExtensionFunctionTypeRejectsNonFunctionNominalType() {
        let source = """
        interface Host {
            val invalid: @ExtensionFunctionType List<String>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-EXTFN-TYPE", in: ctx)

        #expect(diagnostics.count == 1, "Expected one extension-function-type diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v31 = diagnostics.allSatisfy(isError)
        #expect(v31, "Extension-function-type diagnostics should be errors")
    }

    @Test func testTypeAnnotationTargetValidationRejectsClassOnlyAnnotationOnTypeUsage() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly

        interface Host {
            val invalid: @ClassOnly String
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic for type usage, got: \(ctx.diagnostics.diagnostics)")
        let v32 = diagnostics.allSatisfy(isError)
        #expect(v32, "Annotation-target diagnostics should be errors")
    }

    @Test func testTypeAnnotationRejectsUseSiteTarget() {
        let source = """
        interface Host {
            val invalid: @field:ExtensionFunctionType Function1<String, Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-PARSE-TYPE-ANNOTATION", in: ctx)

        #expect(diagnostics.count == 1, "Expected one parse diagnostic for type annotation use-site target, got: \(ctx.diagnostics.diagnostics)")
        let v33 = diagnostics.allSatisfy(isError)
        #expect(v33, "Type-annotation parse diagnostics should be errors")
    }

    @Test func testCompilerMetadataAutoAttachedToNominalDeclarations() throws {
        let source = """
        class Plain
        interface Face
        object Singleton
        enum class Color { RED }
        annotation class Marker
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected metadata attachment smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        #expect(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Metadata")]) != nil)

        for name in ["Plain", "Face", "Singleton", "Color", "Marker"] {
            let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern(name)]))
            let annotations = sema.symbols.annotations(for: symbol)
            let v34 = annotations.contains(where: { $0.annotationFQName == KnownCompilerAnnotation.metadata.qualifiedName })
            #expect(
                v34,
                "Expected \(name) to receive compiler metadata annotation, got: \(annotations)"
            )
        }
    }

    @Test func testOptInAllowsExperimentalStdlibApiUsage() {
        let source = """
        @OptIn(ExperimentalStdlibApi::class)
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected opt-in annotated function to use HexFormat API without diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExperimentalStdlibApiWithoutOptInEmitsDiagnostic() {
        let source = """
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected one opt-in diagnostic for toHexString(), got: \(ctx.diagnostics.diagnostics)")
        let v35 = diagnostics.allSatisfy(isError)
        #expect(v35, "Opt-in diagnostics should be errors")
    }

    @Test func testExperimentalStdlibApiDefaultPropertyWithoutOptInEmitsDiagnostic() {
        let source = """
        fun hex(): String = 42.toHexString(HexFormat.Default)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.count == 2, "Expected opt-in diagnostics for HexFormat.Default and toHexString(), got: \(ctx.diagnostics.diagnostics)")
        let v36 = diagnostics.allSatisfy(isError)
        #expect(v36, "Opt-in diagnostics should be errors")
    }

    @Test func testCompilerOptInFlagAllowsExperimentalStdlibApiUsage() {
        let source = """
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(
            source,
            frontendFlags: ["opt-in=kotlin.ExperimentalStdlibApi"]
        )
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected compiler -opt-in flag to suppress stdlib opt-in diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExperimentalVersionOverloadingAnnotationRequiresOptIn() {
        let source = """
        import kotlin.ExperimentalVersionOverloading

        @ExperimentalVersionOverloading
        annotation class Versioned

        @Versioned
        fun api() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected one ExperimentalVersionOverloading opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v37 = diagnostics.allSatisfy(isError)
        #expect(v37, "ExperimentalVersionOverloading opt-in diagnostics should be errors")
    }

    @Test func testExperimentalVersionOverloadingAnnotationAcceptsOptIn() {
        let source = """
        import kotlin.ExperimentalVersionOverloading

        @ExperimentalVersionOverloading
        annotation class Versioned

        @OptIn(ExperimentalVersionOverloading::class)
        @Versioned
        fun api() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalVersionOverloading diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExperimentalVersionOverloadingAnnotationAcceptsCompilerOptInFlag() {
        let source = """
        import kotlin.ExperimentalVersionOverloading

        @ExperimentalVersionOverloading
        annotation class Versioned

        @Versioned
        fun api() {}
        """

        let ctx = runSemaCollectingDiagnostics(
            source,
            frontendFlags: ["opt-in=kotlin.ExperimentalVersionOverloading"]
        )
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected compiler -opt-in flag to suppress ExperimentalVersionOverloading diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExperimentalContextParametersMarkerRequiresOptIn() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @ExperimentalContextParameters
        fun contextApi(): Int = 1

        fun caller(): Int = contextApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected one ExperimentalContextParameters opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v38 = diagnostics.allSatisfy(isError)
        #expect(v38, "ExperimentalContextParameters opt-in diagnostics should be errors")
        #expect(
            diagnostics.first?.message.contains("context parameters") == true,
            "Expected diagnostic to include the ExperimentalContextParameters message, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalContextParametersMarkerAcceptsOptIn() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @ExperimentalContextParameters
        fun contextApi(): Int = 1

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): Int = contextApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalContextParameters diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExperimentalContextParametersMarkerAcceptsCompilerOptInFlag() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @ExperimentalContextParameters
        fun contextApi(): Int = 1

        fun caller(): Int = contextApi()
        """

        let ctx = runSemaCollectingDiagnostics(
            source,
            frontendFlags: ["opt-in=kotlin.ExperimentalContextParameters"]
        )
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected compiler -opt-in flag to suppress ExperimentalContextParameters diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSubclassOptInRequiredRejectsSubclassWithoutOptIn() {
        let source = """
        @RequiresOptIn
        annotation class ExperimentalBase

        @SubclassOptInRequired(ExperimentalBase::class)
        open class Base

        class Child : Base()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected one subclass opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v39 = diagnostics.contains(where: isError)
        #expect(v39, "Subclass opt-in diagnostic should follow ERROR marker severity")
    }

    @Test func testSubclassOptInRequiredAllowsSubclassWithOptIn() {
        let source = """
        @RequiresOptIn
        annotation class ExperimentalBase

        @SubclassOptInRequired(ExperimentalBase::class)
        open class Base

        @OptIn(ExperimentalBase::class)
        class Child : Base()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected @OptIn to satisfy subclass opt-in requirement, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSubclassOptInRequiredPropagatesThroughSupertypeChain() {
        let source = """
        @RequiresOptIn
        annotation class ExperimentalBase

        @SubclassOptInRequired(ExperimentalBase::class)
        open class Base

        @OptIn(ExperimentalBase::class)
        open class Middle : Base()

        class Child : Middle()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected inherited subclass opt-in requirement to reach Child, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSubclassOptInRequiredRejectsNonOptInMarkerClass() {
        let source = """
        annotation class PlainMarker

        @SubclassOptInRequired(PlainMarker::class)
        open class Base

        class Child : Base()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected misuse diagnostic for non opt-in marker, got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.first?.message.contains("markerClass") == true)
    }

    @Test func testFileLevelOptInAllowsExperimentalStdlibApiUsage() {
        let source = """
        @file:OptIn(ExperimentalStdlibApi::class)

        fun hex(): Int = "ff".hexToInt()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected file-level opt-in to suppress HexFormat diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExperimentalAssociatedObjectsMarkerRequiresOptIn() {
        let source = """
        import kotlin.reflect.ExperimentalAssociatedObjects

        @ExperimentalAssociatedObjects
        fun associatedObjectsApi(): Int = 1

        fun caller(): Int = associatedObjectsApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        let v40 = diagnostics.contains(where: isError)
        #expect(v40, "Expected ExperimentalAssociatedObjects opt-in error, got: \(ctx.diagnostics.diagnostics)")
        #expect(
            diagnostics.first?.message.contains("ExperimentalAssociatedObjects") == true,
            "Expected diagnostic to mention ExperimentalAssociatedObjects, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalAssociatedObjectsMarkerAllowsExplicitOptIn() {
        let source = """
        import kotlin.reflect.ExperimentalAssociatedObjects

        @ExperimentalAssociatedObjects
        fun associatedObjectsApi(): Int = 1

        @OptIn(ExperimentalAssociatedObjects::class)
        fun caller(): Int = associatedObjectsApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalAssociatedObjects diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testOptInSuppressionAliasSuppressesDiagnostic() {
        let source = """
        @Suppress("OPT_IN_USAGE")
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.isEmpty, "Expected OPT_IN_USAGE suppression alias to suppress opt-in diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func propertyType(
        named name: String,
        in interfaceDecl: InterfaceDecl,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let expectedName = interner.intern(name)
        let propertyDeclID = try #require(interfaceDecl.memberProperties.first(where: { declID in
            guard case let .propertyDecl(propertyDecl) = ast.arena.decl(declID) else {
                return false
            }
            return propertyDecl.name == expectedName
        }))
        let propertySymbol = try #require(sema.bindings.declSymbol(for: propertyDeclID))
        return try #require(sema.symbols.propertyType(for: propertySymbol))
    }

    func runSemaCollectingDiagnostics(
        _ source: String,
        frontendFlags: [String] = []
    ) -> CompilationContext {
        let ctx = makeAnnotationSemanticContext(source, frontendFlags: frontendFlags)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func makeAnnotationSemanticContext(
        _ source: String,
        frontendFlags: [String]
    ) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], frontendFlags: frontendFlags)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        return ctx
    }

    func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    func isError(_ diagnostic: Diagnostic) -> Bool {
        if case .error = diagnostic.severity {
            return true
        }
        return false
    }

    func isWarning(_ diagnostic: Diagnostic) -> Bool {
        if case .warning = diagnostic.severity {
            return true
        }
        return false
    }

    func symbolVisibility(_ path: [String], in ctx: CompilationContext) throws -> Visibility {
        let sema = try #require(ctx.sema)
        let fqName = path.map(ctx.interner.intern)
        let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
        let symbol = try #require(sema.symbols.symbol(symbolID))
        return symbol.visibility
    }

    private func assertArrayOfOutThrowableKClass(
        _ type: TypeID,
        in sema: SemaModule,
        interner: StringInterner
    ) throws {
        guard case let .classType(arrayType) = sema.types.kind(of: type) else {
            Issue.record("Expected Array<out KClass<Throwable>>, got \(sema.types.renderType(type))")
            return
        }
        let arraySymbol = try #require(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Array")])
        )
        #expect(arrayType.classSymbol == arraySymbol)
        #expect(arrayType.args.count == 1)
        guard case let .out(elementType) = arrayType.args[0] else {
            Issue.record("Expected covariant Array element, got \(arrayType.args[0])")
            return
        }
        try assertThrowableKClass(elementType, in: sema, interner: interner)
    }

    private func assertThrowableKClass(
        _ type: TypeID,
        in sema: SemaModule,
        interner: StringInterner
    ) throws {
        guard case let .kClassType(kClassType) = sema.types.kind(of: type) else {
            Issue.record("Expected KClass<Throwable>, got \(sema.types.renderType(type))")
            return
        }
        guard case let .classType(argumentType) = sema.types.kind(of: kClassType.argument) else {
            Issue.record("Expected KClass argument to be Throwable, got \(sema.types.renderType(kClassType.argument))")
            return
        }
        let throwableSymbol = try #require(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Throwable")])
        )
        #expect(argumentType.classSymbol == throwableSymbol)
    }
}
#endif
