#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `SinceKotlin` / data-class copy-visibility / DSL-marker / and other
/// version- and visibility-related annotation tests, split out from
/// `AnnotationSemanticTests` to keep each test source under ~1500 lines.
extension AnnotationSemanticTests {

    @Test func testVersionAndVisibilitySema() throws {
        let sources: [String] = [
            // testSinceKotlinAcceptsDocumentedDeclarationTargets
            """
            package sample0
                    @SinceKotlin("1.0")
                    class Stable {
                        @SinceKotlin(version = "1.1")
                        val value: Int = 1

                        @SinceKotlin("1.2")
                        fun expose(): Int = value
                    }

                    @SinceKotlin("1.3")
                    typealias StableAlias = Stable

            """,

            // testSinceKotlinRejectsFileTarget
            """
            package sample1
                    @file:SinceKotlin("1.0")


            """,

            // testDslMarkerAcceptsAnnotationClassTarget
            """
            package sample2
                    @DslMarker
                    annotation class HtmlDsl

            """,

            // testDslMarkerRejectsRegularClassTarget
            """
            package sample3
                    @DslMarker
                    class BadMarker

            """,

            // testIntroducedAtAllowsValueParameterUse
            """
            package sample4
                    fun sample(@IntroducedAt("1.1") value: Int = 0): Int = value

            """,

            // testIntroducedAtRejectsClassTarget
            """
            package sample5
                    @IntroducedAt("1.1")
                    class Bad

            """,

            // testOptionalExpectationAcceptsAnnotationClassTarget
            """
            package sample6
                    @OptionalExpectation
                    annotation class PlatformMarker

            """,

            // testOptionalExpectationRejectsFunctionTarget
            """
            package sample7
                    @OptIn(ExperimentalMultiplatform::class)
                    @OptionalExpectation
                    fun bad() {}

            """,

            // testRootThrowsAcceptsDocumentedDeclarationTargets
            """
            package sample8
                    class Host @Throws(Throwable::class) constructor() {
                        @get:Throws(Throwable::class)
                        val readonly: Int = 1

                        @set:Throws(Throwable::class)
                        var value: Int = 0

                        @Throws(Throwable::class)
                        fun expose(): Int = value
                    }

            """,

            // testRootThrowsRejectsClassTarget
            """
            package sample9
                    @Throws(Throwable::class)
                    class Bad

            """,

            // testTargetAnnotationIsRejectedOnRegularClass
            """
            package sample10
                    @Target(AnnotationTarget.CLASS)
                    class BadTarget

            """,

            // testTargetAnnotationAllowsAnnotationClassButRejectsFunctionUsage
            """
            package sample11
                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassOnly

                    @ClassOnly
                    class Good

                    @ClassOnly
                    fun bad() {}

            """,

            // testAnnotationClassInheritsKotlinAnnotation
            """
            package sample12
                    annotation class MyAnnotation

            """,

            // testExperimentalExtendedContractsRequiresOptIn
            """
            package sample13
                    import kotlin.contracts.ExperimentalExtendedContracts

                    @ExperimentalExtendedContracts
                    fun extendedApi(): Int = 1

                    fun caller(): Int = extendedApi()

            """,

            // testOverloadResolutionByLambdaReturnTypeRejectsClassTarget
            """
            package sample14
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.OptIn
                    import kotlin.experimental.ExperimentalTypeInference

                    @Target(AnnotationTarget.CLASS)
                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    class Bad

            """,

            // testExperimentalTypeInferenceAcceptsFunctionTarget
            """
            package sample15
                    import kotlin.experimental.ExperimentalTypeInference

                    @ExperimentalTypeInference
                    fun bad() {}

            """,

            // testOverloadResolutionByLambdaReturnTypeRequiresOptIn
            """
            package sample16
                    import kotlin.OverloadResolutionByLambdaReturnType

                    @OverloadResolutionByLambdaReturnType
                    fun foo(block: () -> Int): Int = block()

            """,

            // testOverloadResolutionByLambdaReturnTypeAcceptsOptIn
            """
            package sample17
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(block: () -> Int): Int = block()

            """,

            // testFieldTargetAllowsBackedFieldAndRejectsMissingBackingField
            """
            package sample18
                    @Target(value = [AnnotationTarget.FIELD])
                    annotation class FieldOnly

                    class Storage {
                        @field:FieldOnly val stored: String = ""
                    }

                    class Missing {
                        @field:FieldOnly val missing: String
                            get() = "x"
                    }

            """,

            // testFieldTargetRejectsExtensionProperty
            """
            package sample19
                    @Target(value = [AnnotationTarget.FIELD])
                    annotation class FieldOnly

                    @field:FieldOnly
                    val String.ext: Int
                        get() = length

            """,

            // testAnnotationTargetSuppressionAliasSuppressesDiagnostic
            """
            package sample20
                    @Suppress("ANNOTATION_TARGET")
                    @Target(AnnotationTarget.CLASS)
                    class BadTarget

            """,

            // testWasExperimentalAnnotationIsCollectedOnDeclaration
            """
            package sample21
                    annotation class ExperimentalApi

                    @WasExperimental(markerClass = ExperimentalApi::class)
                    fun stabilizedApi(): Int = 42

            """,

            // testExtensionFunctionTypeRejectsFunction0
            """
            package sample22
                    interface Host {
                        val invalid: @ExtensionFunctionType Function0<Unit>
                    }

            """,

            // testExtensionFunctionTypeRejectsNonFunctionNominalType
            """
            package sample23
                    interface Host {
                        val invalid: @ExtensionFunctionType List<String>
                    }

            """,

            // testTypeAnnotationTargetValidationRejectsClassOnlyAnnotationOnTypeUsage
            """
            package sample24
                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassOnly

                    interface Host {
                        val invalid: @ClassOnly String
                    }

            """,

            // testTypeAnnotationRejectsUseSiteTarget
            """
            package sample25
                    interface Host {
                        val invalid: @field:ExtensionFunctionType Function1<String, Unit>
                    }

            """,

            // testCompilerMetadataAutoAttachedToNominalDeclarations
            """
            package sample26
                    class Plain
                    interface Face
                    object Singleton
                    enum class Color { RED }
                    annotation class Marker

            """,

            // testOptInAllowsExperimentalStdlibApiUsage
            """
            package sample27
                    @OptIn(ExperimentalStdlibApi::class)
                    fun hex(): String = 255.toHexString()

            """,

            // testExperimentalStdlibApiWithoutOptInEmitsDiagnostic
            """
            package sample28
                    fun hex(): String = 255.toHexString()

            """,

            // testExperimentalStdlibApiDefaultPropertyWithoutOptInEmitsDiagnostic
            """
            package sample29
                    fun hex(): String = 42.toHexString(HexFormat.Default)

            """,

            // testExperimentalVersionOverloadingAnnotationRequiresOptIn
            """
            package sample30
                    import kotlin.ExperimentalVersionOverloading

                    @ExperimentalVersionOverloading
                    annotation class Versioned

                    @Versioned
                    fun api() {}

            """,

            // testExperimentalVersionOverloadingAnnotationAcceptsOptIn
            """
            package sample31
                    import kotlin.ExperimentalVersionOverloading

                    @ExperimentalVersionOverloading
                    annotation class Versioned

                    @OptIn(ExperimentalVersionOverloading::class)
                    @Versioned
                    fun api() {}

            """,

            // testExperimentalContextParametersMarkerRequiresOptIn
            """
            package sample32
                    import kotlin.ExperimentalContextParameters

                    @ExperimentalContextParameters
                    fun contextApi(): Int = 1

                    fun caller(): Int = contextApi()

            """,

            // testExperimentalContextParametersMarkerAcceptsOptIn
            """
            package sample33
                    import kotlin.ExperimentalContextParameters

                    @ExperimentalContextParameters
                    fun contextApi(): Int = 1

                    @OptIn(ExperimentalContextParameters::class)
                    fun caller(): Int = contextApi()

            """,

            // testSubclassOptInRequiredRejectsSubclassWithoutOptIn
            """
            package sample34
                    @RequiresOptIn
                    annotation class ExperimentalBase

                    @SubclassOptInRequired(ExperimentalBase::class)
                    open class Base

                    class Child : Base()

            """,

            // testSubclassOptInRequiredAllowsSubclassWithOptIn
            """
            package sample35
                    @RequiresOptIn
                    annotation class ExperimentalBase

                    @SubclassOptInRequired(ExperimentalBase::class)
                    open class Base

                    @OptIn(ExperimentalBase::class)
                    class Child : Base()

            """,

            // testSubclassOptInRequiredPropagatesThroughSupertypeChain
            """
            package sample36
                    @RequiresOptIn
                    annotation class ExperimentalBase

                    @SubclassOptInRequired(ExperimentalBase::class)
                    open class Base

                    @OptIn(ExperimentalBase::class)
                    open class Middle : Base()

                    class Child : Middle()

            """,

            // testSubclassOptInRequiredRejectsNonOptInMarkerClass
            """
            package sample37
                    annotation class PlainMarker

                    @SubclassOptInRequired(PlainMarker::class)
                    open class Base

                    class Child : Base()

            """,

            // testFileLevelOptInAllowsExperimentalStdlibApiUsage
            """
            package sample38
                    @file:OptIn(ExperimentalStdlibApi::class)

                    fun hex(): Int = "ff".hexToInt()

            """,

            // testExperimentalAssociatedObjectsMarkerRequiresOptIn
            """
            package sample39
                    import kotlin.reflect.ExperimentalAssociatedObjects

                    @ExperimentalAssociatedObjects
                    fun associatedObjectsApi(): Int = 1

                    fun caller(): Int = associatedObjectsApi()

            """,

            // testExperimentalAssociatedObjectsMarkerAllowsExplicitOptIn
            """
            package sample40
                    import kotlin.reflect.ExperimentalAssociatedObjects

                    @ExperimentalAssociatedObjects
                    fun associatedObjectsApi(): Int = 1

                    @OptIn(ExperimentalAssociatedObjects::class)
                    fun caller(): Int = associatedObjectsApi()

            """,

            // testOptInSuppressionAliasSuppressesDiagnostic
            """
            package sample41
                    @Suppress("OPT_IN_USAGE")
                    fun hex(): String = 255.toHexString()

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testSinceKotlinAcceptsDocumentedDeclarationTargets
            do {
                let samplePath = paths[0]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected SinceKotlin declaration targets to be accepted, got: \(sampleDiags)")
            }
            // testSinceKotlinRejectsFileTarget
            do {
                let samplePath = paths[1]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected SinceKotlin to reject file target, got: \(sampleDiags)")
                let v1 = diagnostics.allSatisfy(isError)
                #expect(v1, "Annotation-target diagnostics should be errors")
            }
            // testDslMarkerAcceptsAnnotationClassTarget
            do {
                let samplePath = paths[2]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected DslMarker to be accepted on annotation classes, got: \(sampleDiags)")
            }
            // testDslMarkerRejectsRegularClassTarget
            do {
                let samplePath = paths[3]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected annotation-class-only target diagnostic, got: \(sampleDiags)")
                let v6 = diagnostics.allSatisfy(isError)
                #expect(v6, "Annotation-target diagnostics should be errors")
            }
            // testIntroducedAtAllowsValueParameterUse
            do {
                let samplePath = paths[4]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected IntroducedAt value-parameter target to be accepted, got: \(sampleDiags)")
            }
            // testIntroducedAtRejectsClassTarget
            do {
                let samplePath = paths[5]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected IntroducedAt to reject class target, got: \(sampleDiags)")
                let v10 = diagnostics.allSatisfy(isError)
                #expect(v10, "Annotation-target diagnostics should be errors")
            }
            // testOptionalExpectationAcceptsAnnotationClassTarget
            do {
                let samplePath = paths[6]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected OptionalExpectation annotation-class target to be accepted, got: \(sampleDiags)")
            }
            // testOptionalExpectationRejectsFunctionTarget
            do {
                let samplePath = paths[7]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected OptionalExpectation to reject function target, got: \(sampleDiags)")
                let v13 = diagnostics.allSatisfy(isError)
                #expect(v13, "Annotation-target diagnostics should be errors")
            }
            // testRootThrowsAcceptsDocumentedDeclarationTargets
            do {
                let samplePath = paths[8]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected Throws declaration targets to be accepted, got: \(sampleDiags)")
            }
            // testRootThrowsRejectsClassTarget
            do {
                let samplePath = paths[9]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected Throws to reject class target, got: \(sampleDiags)")
                let v15 = diagnostics.allSatisfy(isError)
                #expect(v15, "Annotation-target diagnostics should be errors")
            }
            // testTargetAnnotationIsRejectedOnRegularClass
            do {
                let samplePath = paths[10]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic, got: \(sampleDiags)")
                let v16 = diagnostics.allSatisfy(isError)
                #expect(v16, "Annotation-target diagnostics should be errors")
            }
            // testTargetAnnotationAllowsAnnotationClassButRejectsFunctionUsage
            do {
                let samplePath = paths[11]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected exactly one annotation-target diagnostic, got: \(sampleDiags)")
                let v17 = diagnostics.allSatisfy(isError)
                #expect(v17, "Annotation-target diagnostics should be errors")
            }
            // testAnnotationClassInheritsKotlinAnnotation
            do {


                let sema = try #require(ctx.sema)
                let kotlinAnnotationSymbol = try #require(
                    sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Annotation")])
                )
                let myAnnotationSymbol = try #require(
                    sema.symbols.lookup(fqName: [ctx.interner.intern("sample12"), ctx.interner.intern("MyAnnotation")])
                )

                #expect(sema.symbols.symbol(myAnnotationSymbol)?.kind == .annotationClass)
                let v19 = sema.symbols.directSupertypes(for: myAnnotationSymbol).contains(kotlinAnnotationSymbol)
                #expect(
                    v19,
                    "Annotation classes should implicitly inherit kotlin.Annotation"
                )
            }
            // testExperimentalExtendedContractsRequiresOptIn
            do {
                let samplePath = paths[13]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.count == 1, "Expected one ExperimentalExtendedContracts opt-in diagnostic, got: \(sampleDiags)")
                let v25 = diagnostics.allSatisfy(isError)
                #expect(v25, "ExperimentalExtendedContracts opt-in diagnostics should be errors")
            }
            // testOverloadResolutionByLambdaReturnTypeRejectsClassTarget
            do {
                let samplePath = paths[14]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 2, "Expected target diagnostics for both @Target and @OverloadResolutionByLambdaReturnType misuse, got: \(sampleDiags)")
                let v26 = diagnostics.allSatisfy(isError)
                #expect(v26, "Annotation-target diagnostics should be errors")
            }
            // testExperimentalTypeInferenceAcceptsFunctionTarget
            do {
                let samplePath = paths[15]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "ExperimentalTypeInference should be accepted on functions, got: \(sampleDiags)")
            }
            // testOverloadResolutionByLambdaReturnTypeRequiresOptIn
            do {
                let samplePath = paths[16]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPTIN" }

                #expect(diagnostics.count == 1, "Expected one opt-in diagnostic, got: \(sampleDiags)")
                let v27 = diagnostics.allSatisfy(isError)
                #expect(v27, "Opt-in diagnostics should be errors")
            }
            // testOverloadResolutionByLambdaReturnTypeAcceptsOptIn
            do {
                let samplePath = paths[17]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPTIN" }

                #expect(diagnostics.isEmpty, "Expected opt-in diagnostic to be suppressed by @OptIn, got: \(sampleDiags)")
            }
            // testFieldTargetAllowsBackedFieldAndRejectsMissingBackingField
            do {
                let samplePath = paths[18]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected exactly one annotation-target diagnostic for the missing backing field, got: \(sampleDiags)")
                let v28 = diagnostics.allSatisfy(isError)
                #expect(v28, "Annotation-target diagnostics should be errors")
            }
            // testFieldTargetRejectsExtensionProperty
            do {
                let samplePath = paths[19]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic for the extension property, got: \(sampleDiags)")
                let v29 = diagnostics.allSatisfy(isError)
                #expect(v29, "Annotation-target diagnostics should be errors")
            }
            // testAnnotationTargetSuppressionAliasSuppressesDiagnostic
            do {
                let samplePath = paths[20]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected ANNOTATION_TARGET suppression alias to suppress annotation-target diagnostics, got: \(sampleDiags)")
            }
            // testWasExperimentalAnnotationIsCollectedOnDeclaration
            do {


                let sema = try #require(ctx.sema)
                let symbolID = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("sample21"), ctx.interner.intern("stabilizedApi")]).first)
                let annotations = sema.symbols.annotations(for: symbolID)
                let annotation = try #require(annotations.first(where: {
                    KnownCompilerAnnotation.wasExperimental.matches($0.annotationFQName)
                }))

                #expect(annotation.arguments == ["markerClass=ExperimentalApi::class"])
            }
            // testExtensionFunctionTypeRejectsFunction0
            do {
                let samplePath = paths[22]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-EXTFN-TYPE" }

                #expect(diagnostics.count == 1, "Expected one extension-function-type diagnostic, got: \(sampleDiags)")
                let v30 = diagnostics.allSatisfy(isError)
                #expect(v30, "Extension-function-type diagnostics should be errors")
            }
            // testExtensionFunctionTypeRejectsNonFunctionNominalType
            do {
                let samplePath = paths[23]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-EXTFN-TYPE" }

                #expect(diagnostics.count == 1, "Expected one extension-function-type diagnostic, got: \(sampleDiags)")
                let v31 = diagnostics.allSatisfy(isError)
                #expect(v31, "Extension-function-type diagnostics should be errors")
            }
            // testTypeAnnotationTargetValidationRejectsClassOnlyAnnotationOnTypeUsage
            do {
                let samplePath = paths[24]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic for type usage, got: \(sampleDiags)")
                let v32 = diagnostics.allSatisfy(isError)
                #expect(v32, "Annotation-target diagnostics should be errors")
            }
            // testTypeAnnotationRejectsUseSiteTarget
            do {
                let samplePath = paths[25]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-PARSE-TYPE-ANNOTATION" }

                #expect(diagnostics.count == 1, "Expected one parse diagnostic for type annotation use-site target, got: \(sampleDiags)")
                let v33 = diagnostics.allSatisfy(isError)
                #expect(v33, "Type-annotation parse diagnostics should be errors")
            }
            // testCompilerMetadataAutoAttachedToNominalDeclarations
            do {
                let samplePath = paths[26]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected metadata attachment smoke test to compile cleanly, got: \(sampleDiags)")

                let sema = try #require(ctx.sema)
                let interner = ctx.interner

                #expect(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Metadata")]) != nil)

                let sample26 = interner.intern("sample26")
                for name in ["Plain", "Face", "Singleton", "Color", "Marker"] {
                    let symbol = try #require(sema.symbols.lookup(fqName: [sample26, interner.intern(name)]))
                    let annotations = sema.symbols.annotations(for: symbol)
                    let v34 = annotations.contains(where: { $0.annotationFQName == KnownCompilerAnnotation.metadata.qualifiedName })
                    #expect(
                        v34,
                        "Expected \(name) to receive compiler metadata annotation, got: \(annotations)"
                    )
                }
            }
            // testOptInAllowsExperimentalStdlibApiUsage
            do {
                let samplePath = paths[27]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.isEmpty, "Expected opt-in annotated function to use HexFormat API without diagnostics, got: \(sampleDiags)")
            }
            // testExperimentalStdlibApiWithoutOptInEmitsDiagnostic
            do {
                let samplePath = paths[28]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.count == 1, "Expected one opt-in diagnostic for toHexString(), got: \(sampleDiags)")
                let v35 = diagnostics.allSatisfy(isError)
                #expect(v35, "Opt-in diagnostics should be errors")
            }
            // testExperimentalStdlibApiDefaultPropertyWithoutOptInEmitsDiagnostic
            do {
                let samplePath = paths[29]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.count == 2, "Expected opt-in diagnostics for HexFormat.Default and toHexString(), got: \(sampleDiags)")
                let v36 = diagnostics.allSatisfy(isError)
                #expect(v36, "Opt-in diagnostics should be errors")
            }
            // testExperimentalVersionOverloadingAnnotationRequiresOptIn
            do {
                let samplePath = paths[30]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.count == 1, "Expected one ExperimentalVersionOverloading opt-in diagnostic, got: \(sampleDiags)")
                let v37 = diagnostics.allSatisfy(isError)
                #expect(v37, "ExperimentalVersionOverloading opt-in diagnostics should be errors")
            }
            // testExperimentalVersionOverloadingAnnotationAcceptsOptIn
            do {
                let samplePath = paths[31]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalVersionOverloading diagnostics, got: \(sampleDiags)")
            }
            // testExperimentalContextParametersMarkerRequiresOptIn
            do {
                let samplePath = paths[32]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.count == 1, "Expected one ExperimentalContextParameters opt-in diagnostic, got: \(sampleDiags)")
                let v38 = diagnostics.allSatisfy(isError)
                #expect(v38, "ExperimentalContextParameters opt-in diagnostics should be errors")
                #expect(
                    diagnostics.first?.message.contains("context parameters") == true,
                    "Expected diagnostic to include the ExperimentalContextParameters message, got: \(diagnostics)"
                )
            }
            // testExperimentalContextParametersMarkerAcceptsOptIn
            do {
                let samplePath = paths[33]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalContextParameters diagnostics, got: \(sampleDiags)")
            }
            // testSubclassOptInRequiredRejectsSubclassWithoutOptIn
            do {
                let samplePath = paths[34]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-SUBCLASS-OPT-IN" }

                #expect(diagnostics.count == 1, "Expected one subclass opt-in diagnostic, got: \(sampleDiags)")
                let v39 = diagnostics.contains(where: isError)
                #expect(v39, "Subclass opt-in diagnostic should follow ERROR marker severity")
            }
            // testSubclassOptInRequiredAllowsSubclassWithOptIn
            do {
                let samplePath = paths[35]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-SUBCLASS-OPT-IN" }

                #expect(diagnostics.isEmpty, "Expected @OptIn to satisfy subclass opt-in requirement, got: \(sampleDiags)")
            }
            // testSubclassOptInRequiredPropagatesThroughSupertypeChain
            do {
                let samplePath = paths[36]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-SUBCLASS-OPT-IN" }

                #expect(diagnostics.count == 1, "Expected inherited subclass opt-in requirement to reach Child, got: \(sampleDiags)")
            }
            // testSubclassOptInRequiredRejectsNonOptInMarkerClass
            do {
                let samplePath = paths[37]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-SUBCLASS-OPT-IN" }

                #expect(diagnostics.count == 1, "Expected misuse diagnostic for non opt-in marker, got: \(sampleDiags)")
                #expect(diagnostics.first?.message.contains("markerClass") == true)
            }
            // testFileLevelOptInAllowsExperimentalStdlibApiUsage
            do {
                let samplePath = paths[38]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.isEmpty, "Expected file-level opt-in to suppress HexFormat diagnostics, got: \(sampleDiags)")
            }
            // testExperimentalAssociatedObjectsMarkerRequiresOptIn
            do {
                let samplePath = paths[39]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                let v40 = diagnostics.contains(where: isError)
                #expect(v40, "Expected ExperimentalAssociatedObjects opt-in error, got: \(sampleDiags)")
                #expect(
                    diagnostics.first?.message.contains("ExperimentalAssociatedObjects") == true,
                    "Expected diagnostic to mention ExperimentalAssociatedObjects, got: \(diagnostics)"
                )
            }
            // testExperimentalAssociatedObjectsMarkerAllowsExplicitOptIn
            do {
                let samplePath = paths[40]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalAssociatedObjects diagnostics, got: \(sampleDiags)")
            }
            // testOptInSuppressionAliasSuppressesDiagnostic
            do {
                let samplePath = paths[41]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }

                #expect(diagnostics.isEmpty, "Expected OPT_IN_USAGE suppression alias to suppress opt-in diagnostics, got: \(sampleDiags)")
            }

        }
    }




    @Test func testAnnotationSemanticVersionAndVisibilitySurfaceRegistrations() throws {
        let sources: [String] = [
            // testSinceKotlinSurfaceHasVersionPropertyConstructorAndTargets
            """
            package sample0
            class Host
            """,
            // testDslMarkerSurfaceHasDocumentedMetadata
            """
            package sample1
            fun noop() {}
            """,
            // testIntroducedAtSurfaceHasVersionPropertyConstructorAndValueParameterTarget
            """
            package sample2
            class Host
            """,
            // testOptionalExpectationSurfaceIsSyntheticTargetedAndExperimental
            """
            package sample3
            class Host
            """,
            // testRootThrowsSurfaceHasVarargKClassPropertyConstructorAndTargets
            """
            package sample4
            class Host
            """,
            // testMustBeDocumentedAnnotationIsSyntheticAndTargetedToAnnotationClasses
            """
            package sample5
            annotation class ExperimentalApi
            """,
            // testExperimentalContractsAnnotationIsSourceBackedAnnotationClass
            """
            package sample6
            annotation class ExperimentalApi
            """,
            // testExperimentalExtendedContractsAnnotationIsSyntheticOptInMarker
            """
            package sample7
            fun noop() {}
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)

            // testSinceKotlinSurfaceHasVersionPropertyConstructorAndTargets
            do {
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
            #expect(symbol.declSite != nil, "SinceKotlin should be source-backed")
            #expect(!symbol.flags.contains(.synthetic))
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
            // testDslMarkerSurfaceHasDocumentedMetadata
            do {
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
            #expect(!symbol.flags.contains(.synthetic))
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
            let v5 = annotations.contains { ann in
                guard KnownCompilerAnnotation.sinceKotlin.matches(ann.annotationFQName) else {
                    return false
                }
                return ann.arguments.first?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) == "1.1"
            }
            #expect(
                v5,
                "DslMarker should carry SinceKotlin(1.1), got: \(annotations)"
            )

            }
            // testIntroducedAtSurfaceHasVersionPropertyConstructorAndValueParameterTarget
            do {
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
            // testOptionalExpectationSurfaceIsSourceBackedTargetedAndExperimental
            do {
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
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.kind == .annotationClass)

            let constructorSymbol = try #require(
                sema.symbols.lookupAll(fqName: optionalExpectationFQName + [ctx.interner.intern("<init>")])
                    .first(where: { sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true }),
                "kotlin.OptionalExpectation() constructor must be registered"
            )
            #expect(
                sema.symbols.functionSignature(for: constructorSymbol)?.returnType == sema.types.make(.classType(ClassType(
                    classSymbol: symbolID,
                    args: [],
                    nullability: .nonNull
                )))
            )

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
            // testRootThrowsSurfaceHasVarargKClassPropertyConstructorAndTargets
            do {
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
            #expect(!symbol.flags.contains(.synthetic))
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
            // testMustBeDocumentedAnnotationIsSyntheticAndTargetedToAnnotationClasses
            do {
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
            // testExperimentalContractsAnnotationIsSourceBackedAnnotationClass
            do {
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("contracts"),
                ctx.interner.intern("ExperimentalContracts"),
            ]
            let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
            let symbol = try #require(sema.symbols.symbol(symbolID))

            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.declSite != nil)
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
            // testExperimentalExtendedContractsAnnotationIsSourceBackedOptInMarker
            do {
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("contracts"),
                ctx.interner.intern("ExperimentalExtendedContracts"),
            ]
            let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
            let symbol = try #require(sema.symbols.symbol(symbolID))

            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.declSite != nil)
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
        }
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
