#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativePlatformAnnotationTests {

    private func diagnosticsForPath(_ path: String, in ctx: CompilationContext) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    @Test
    func testNativePlatformAnnotationsSema() throws {
        let sources: [String] = [
            """
            package sample0
            fun noop() {}
            """,
            // FreezingIsDeprecated warning
            """
            package sample1
            import kotlin.native.FreezingIsDeprecated

            @FreezingIsDeprecated
            fun frozenApi() {}

            fun probe() {
                frozenApi()
            }
            """,
            // FreezingIsDeprecated suppressed
            """
            package sample2
            @file:OptIn(kotlin.native.FreezingIsDeprecated::class)
            import kotlin.native.FreezingIsDeprecated

            @FreezingIsDeprecated
            fun frozenApi() {}

            fun probe() {
                frozenApi()
            }
            """,
            // HiddenFromObjC clean usage
            """
            package sample3
            @file:OptIn(kotlin.experimental.ExperimentalObjCRefinement::class)
            import kotlin.native.HiddenFromObjC

            @HiddenFromObjC
            class HiddenType {
                @HiddenFromObjC
                val hiddenProperty: Int = 1

                @HiddenFromObjC
                fun hiddenFunction(): Int = hiddenProperty
            }
            """,
            // NoInline clean usage
            """
            package sample4
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
            import kotlin.native.NoInline

            @NoInline
            val nativeValue: Int = 1

            @NoInline
            fun nativeFunction(): Int = nativeValue
            """,
            // ObsoleteNativeApi error
            """
            package sample5
            import kotlin.native.ObsoleteNativeApi

            @ObsoleteNativeApi
            fun obsoleteApi() {}

            fun probe() {
                obsoleteApi()
            }
            """,
            // ObsoleteNativeApi suppressed
            """
            package sample6
            @file:OptIn(kotlin.native.ObsoleteNativeApi::class)
            import kotlin.native.ObsoleteNativeApi

            @ObsoleteNativeApi
            fun obsoleteApi() {}

            fun probe() {
                obsoleteApi()
            }
            """,
            // EagerInitialization clean usage
            """
            package sample7
            @file:OptIn(kotlin.ExperimentalStdlibApi::class)
            import kotlin.native.EagerInitialization

            @EagerInitialization
            val eagerValue: Int = 1
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // MARK: - FreezingIsDeprecated

            let freezingFQName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
            let freezingSymbol = try #require(
                sema.symbols.lookup(fqName: freezingFQName),
                "kotlin.native.FreezingIsDeprecated must be registered"
            )

            // testFreezingIsDeprecatedMarkerIsRegistered
            do {
                #expect(sema.symbols.symbol(freezingSymbol)?.kind == .annotationClass)
            }

            // testFreezingIsDeprecatedCarriesRequiresOptInWarning
            do {
                let requiresOptIn = try #require(
                    sema.symbols.annotations(for: freezingSymbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
                    "FreezingIsDeprecated must carry @RequiresOptIn"
                )
                #expect(
                    requiresOptIn.arguments.contains("level=RequiresOptIn.Level.WARNING"),
                    "FreezingIsDeprecated must be a warning-level opt-in marker; got \(requiresOptIn.arguments)"
                )
                #expect(
                    requiresOptIn.arguments.contains { $0.contains("Freezing API is deprecated since 1.7.20") },
                    "FreezingIsDeprecated opt-in message should mention the freezing API deprecation"
                )
            }

            // testFreezingIsDeprecatedCarriesNativeTargets
            do {
                let target = try #require(
                    sema.symbols.annotations(for: freezingSymbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
                    "FreezingIsDeprecated must carry @Target metadata"
                )
                let expectedTargets = [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.LOCAL_VARIABLE",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
                for expectedTarget in expectedTargets {
                    #expect(
                        target.arguments.contains(expectedTarget),
                        "FreezingIsDeprecated @Target should include \(expectedTarget); got \(target.arguments)"
                    )
                }
            }

            // testUsingFreezingDeprecatedApiProducesWarningDiagnostic
            do {
                let sample1Path = paths[1]
                let optInWarnings = diagnosticsForPath(sample1Path, in: ctx).filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
                }
                #expect(
                    !optInWarnings.isEmpty,
                    "Expected warning-level opt-in diagnostic for FreezingIsDeprecated API usage"
                )
            }

            // testOptingInToFreezingIsDeprecatedSuppressesDiagnostic
            do {
                let sample2Path = paths[2]
                let optInDiagnostics = diagnosticsForPath(sample2Path, in: ctx).filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN"
                }
                #expect(
                    optInDiagnostics.isEmpty,
                    "Expected no opt-in diagnostic when @OptIn(FreezingIsDeprecated::class) is present"
                )
            }

            // MARK: - HiddenFromObjC

            let hiddenFromObjCFQName = ["kotlin", "native", "HiddenFromObjC"].map { interner.intern($0) }
            let hiddenFromObjCSymbol = try #require(
                sema.symbols.lookup(fqName: hiddenFromObjCFQName),
                "kotlin.native.HiddenFromObjC must be registered"
            )

            // testHiddenFromObjCAnnotationIsRegistered
            do {
                #expect(sema.symbols.symbol(hiddenFromObjCSymbol)?.kind == .annotationClass)
            }

            // testHiddenFromObjCCarriesObjCRefinementMetadata
            do {
                let annotations = sema.symbols.annotations(for: hiddenFromObjCSymbol)
                #expect(
                    annotations.contains { $0.annotationFQName == "kotlin.native.HidesFromObjC" },
                    "HiddenFromObjC must carry @HidesFromObjC metadata"
                )
                #expect(
                    annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalObjCRefinement" },
                    "HiddenFromObjC must carry @ExperimentalObjCRefinement metadata"
                )
            }

            // testHiddenFromObjCCarriesClassFunctionPropertyTargets
            do {
                let target = try #require(
                    sema.symbols.annotations(for: hiddenFromObjCSymbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
                    "HiddenFromObjC must carry @Target metadata"
                )
                #expect(
                    Set(target.arguments)
                    == Set([
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.CLASS",
                    ])
                )
            }

            // testHiddenFromObjCIsAcceptedOnClassFunctionAndProperty
            do {
                let sample3Path = paths[3]
                let errors = diagnosticsForPath(sample3Path, in: ctx).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected HiddenFromObjC on class/function/property to type-check with ObjC refinement opt-in, got \(errors)"
                )
            }

            // MARK: - NoInline

            let noInlineFQName = ["kotlin", "native", "NoInline"].map { interner.intern($0) }
            let noInlineSymbol = try #require(
                sema.symbols.lookup(fqName: noInlineFQName),
                "kotlin.native.NoInline must be registered"
            )

            // testNoInlineAnnotationIsRegistered
            do {
                #expect(sema.symbols.symbol(noInlineSymbol)?.kind == .annotationClass)
            }

            // testNoInlineCarriesExperimentalNativeApiMetadata
            do {
                let annotations = sema.symbols.annotations(for: noInlineSymbol)
                #expect(
                    annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi" },
                    "NoInline must carry @ExperimentalNativeApi metadata"
                )
            }

            // testNoInlineCarriesFunctionPropertyTargets
            do {
                let target = try #require(
                    sema.symbols.annotations(for: noInlineSymbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
                    "NoInline must carry @Target metadata"
                )
                #expect(
                    Set(target.arguments)
                    == Set([
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ])
                )
            }

            // testNoInlineIsAcceptedOnFunctionAndProperty
            do {
                let sample4Path = paths[4]
                let errors = diagnosticsForPath(sample4Path, in: ctx).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected NoInline on function/property to type-check with ExperimentalNativeApi opt-in, got \(errors)"
                )
            }

            // MARK: - ObsoleteNativeApi

            let obsoleteNativeApiFQName = ["kotlin", "native", "ObsoleteNativeApi"].map { interner.intern($0) }
            let obsoleteNativeApiSymbol = try #require(
                sema.symbols.lookup(fqName: obsoleteNativeApiFQName),
                "kotlin.native.ObsoleteNativeApi must be registered"
            )

            // testObsoleteNativeApiMarkerIsRegistered
            do {
                #expect(sema.symbols.symbol(obsoleteNativeApiSymbol)?.kind == .annotationClass)
            }

            // testObsoleteNativeApiCarriesRequiresOptInError
            do {
                let requiresOptIn = try #require(
                    sema.symbols.annotations(for: obsoleteNativeApiSymbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
                    "ObsoleteNativeApi must carry @RequiresOptIn"
                )
                #expect(
                    requiresOptIn.arguments.contains("level=RequiresOptIn.Level.ERROR"),
                    "ObsoleteNativeApi must be an error-level opt-in marker; got \(requiresOptIn.arguments)"
                )
                #expect(
                    requiresOptIn.arguments.contains { $0.contains("obsolete and subject to removal") },
                    "ObsoleteNativeApi opt-in message should mention removal risk"
                )
            }

            // testObsoleteNativeApiCarriesNativeTargets
            do {
                let target = try #require(
                    sema.symbols.annotations(for: obsoleteNativeApiSymbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
                    "ObsoleteNativeApi must carry @Target metadata"
                )
                let expectedTargets = [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.LOCAL_VARIABLE",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
                for expectedTarget in expectedTargets {
                    #expect(
                        target.arguments.contains(expectedTarget),
                        "ObsoleteNativeApi @Target should include \(expectedTarget); got \(target.arguments)"
                    )
                }
            }

            // testUsingObsoleteNativeApiWithoutOptInProducesErrorDiagnostic
            do {
                let sample5Path = paths[5]
                let optInErrors = diagnosticsForPath(sample5Path, in: ctx).filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error
                }
                #expect(
                    !optInErrors.isEmpty,
                    "Expected error-level opt-in diagnostic for ObsoleteNativeApi usage"
                )
            }

            // testOptingInToObsoleteNativeApiSuppressesDiagnostic
            do {
                let sample6Path = paths[6]
                let optInDiagnostics = diagnosticsForPath(sample6Path, in: ctx).filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN"
                }
                #expect(
                    optInDiagnostics.isEmpty,
                    "Expected no opt-in diagnostic when @OptIn(ObsoleteNativeApi::class) is present"
                )
            }

            // MARK: - EagerInitialization

            let eagerInitializationFQName = ["kotlin", "native", "EagerInitialization"].map { interner.intern($0) }
            let eagerInitializationSymbol = try #require(
                sema.symbols.lookup(fqName: eagerInitializationFQName),
                "kotlin.native.EagerInitialization must be registered"
            )

            // testEagerInitializationAnnotationIsRegistered
            do {
                #expect(sema.symbols.symbol(eagerInitializationSymbol)?.kind == .annotationClass)
            }

            // testEagerInitializationCarriesStdlibMetadata
            do {
                let annotations = sema.symbols.annotations(for: eagerInitializationSymbol)
                let target = try #require(
                    annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
                    "EagerInitialization must carry @Target metadata"
                )
                let retention = try #require(
                    annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" },
                    "EagerInitialization must carry @Retention metadata"
                )
                let deprecated = try #require(
                    annotations.first { $0.annotationFQName == "kotlin.Deprecated" },
                    "EagerInitialization must carry @Deprecated metadata"
                )

                #expect(Set(target.arguments) == Set(["AnnotationTarget.PROPERTY"]))
                #expect(retention.arguments == ["AnnotationRetention.BINARY"])
                #expect(
                    annotations.contains { $0.annotationFQName == "kotlin.ExperimentalStdlibApi" },
                    "EagerInitialization must carry @ExperimentalStdlibApi metadata"
                )
                #expect(
                    deprecated.arguments.contains { $0.contains("temporal migration assistance") },
                    "EagerInitialization deprecation message should mention temporary migration assistance"
                )
            }

            // testEagerInitializationIsAcceptedOnPropertyWithStdlibOptIn
            do {
                let sample7Path = paths[7]
                let errors = diagnosticsForPath(sample7Path, in: ctx).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected EagerInitialization on a property to type-check with ExperimentalStdlibApi opt-in, got \(errors)"
                )
            }
        }
    }
}
#endif
