
/// Kotlin-native metaprogramming annotation stubs.
///
/// Registers synthetic `kotlin.*`, `kotlin.annotation.*`, and
/// `kotlin.experimental.*` annotation classes that are needed for
/// name-resolution and type-checking on any Kotlin target (including Native).
///
/// JVM-specific annotations (`kotlin.jvm.*`) were removed as part of
/// CLEANUP-STUB-084 since this compiler targets macOS native via LLVM.
extension DataFlowSemaPhase {
    func registerSyntheticKotlinAnnotationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // kotlin package — ensure built-in metadata annotations are present.
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid

        registerSyntheticAnnotationClass(
            named: "Suppress",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "Deprecated",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "DeprecatedSinceKotlin",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "ReplaceWith",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticDeprecationLevelEnum(
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let deprecatedSinceKotlinSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("DeprecatedSinceKotlin")]
        ) {
            registerSyntheticDeprecatedSinceKotlinMembers(
                ownerSymbol: deprecatedSinceKotlinSymbol,
                ownerFQName: kotlinPkg + [interner.intern("DeprecatedSinceKotlin")],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        registerSyntheticAnnotationClass(
            named: "WasExperimental",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "OptionalExpectation",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "Throws",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "SinceKotlin",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "DslMarker",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "IntroducedAt",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "ExtensionFunctionType",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let extFunctionTypeSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("ExtensionFunctionType")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.TYPE"]
            )
            var annotations = symbols.annotations(for: extFunctionTypeSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: extFunctionTypeSymbol)
        }
        registerSyntheticContextFunctionTypeParamsAnnotation(
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "Metadata",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "OptIn",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "RequiresOptIn",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "SubclassOptInRequired",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "ConsistentCopyVisibility",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "ExposedCopyVisibility",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "ParameterName",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "PublishedApi",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "PublishedApi",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "IgnorableReturnValue",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "MustUseReturnValues",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "ExperimentalStdlibApi",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "BuilderInference",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let optInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("OptIn")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.LOCAL_VARIABLE",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.TYPEALIAS",
                    "AnnotationTarget.EXPRESSION",
                    "AnnotationTarget.FILE",
                ]
            )
            var annotations = symbols.annotations(for: optInSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: optInSymbol)
        }

        registerSyntheticAnnotationClass(
            named: "OverloadResolutionByLambdaReturnType",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let overloadSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("OverloadResolutionByLambdaReturnType")]
        ) {
            let targetRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.FUNCTION"]
            )
            let experimentalRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.experimental.ExperimentalTypeInference"
            )
            var annotations = symbols.annotations(for: overloadSymbol)
            if !annotations.contains(targetRecord) {
                annotations.append(targetRecord)
            }
            if !annotations.contains(experimentalRecord) {
                annotations.append(experimentalRecord)
            }
            symbols.setAnnotations(annotations, for: overloadSymbol)
        }
        if let builderInferenceSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("BuilderInference")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
                ),
                to: builderInferenceSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                to: builderInferenceSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.experimentalTypeInference.qualifiedName
                ),
                to: builderInferenceSymbol,
                symbols: symbols
            )
        }

        let kotlinExperimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let kotlinExperimentalPkgSymbol = symbols.lookup(fqName: kotlinExperimentalPkg) ?? .invalid
        registerSyntheticAnnotationClass(
            named: "ExperimentalTypeInference",
            packageFQName: kotlinExperimentalPkg,
            packageSymbol: kotlinExperimentalPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let experimentalSymbol = symbols.lookup(
            fqName: kotlinExperimentalPkg + [interner.intern("ExperimentalTypeInference")]
        ) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
            )
            var annotations = symbols.annotations(for: experimentalSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: experimentalSymbol)
        }

        // kotlin.annotation package — provides @Target and AnnotationTarget.
        let kotlinAnnotationPkg = ensurePackage(
            path: ["kotlin", "annotation"],
            symbols: symbols,
            interner: interner
        )
        let kotlinAnnotationPkgSymbol = symbols.lookup(fqName: kotlinAnnotationPkg) ?? .invalid

        registerSyntheticAnnotationClass(
            named: "Target",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let targetSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Target")]) {
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("Target")],
                symbols: symbols
            )
            _ = targetSymbol
        }

        registerSyntheticAnnotationClass(
            named: "MustBeDocumented",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let mustBeDocumentedSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("MustBeDocumented")]) {
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("MustBeDocumented")],
                symbols: symbols
            )
            _ = mustBeDocumentedSymbol
        }

        registerSyntheticAnnotationClass(
            named: "Repeatable",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let repeatableSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Repeatable")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
            )
            var annotations = symbols.annotations(for: repeatableSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: repeatableSymbol)
        }

        registerSyntheticAnnotationClass(
            named: "Retention",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let retentionSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Retention")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
            )
            var annotations = symbols.annotations(for: retentionSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: retentionSymbol)
        }

        attachAnnotationIfNeeded(
            MetadataAnnotationRecord(annotationFQName: "kotlin.RequiresOptIn"),
            to: kotlinPkg + [interner.intern("ExperimentalStdlibApi")],
            symbols: symbols
        )

        registerSyntheticAnnotationTargetEnum(
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticAnnotationRetentionEnum(
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let annotationRetentionName = interner.intern("AnnotationRetention")
        if let retentionSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Retention")]),
           let annotationRetentionSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [annotationRetentionName]),
           let retentionEntrySymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [annotationRetentionName, interner.intern("RUNTIME")])
        {
            let retentionType = types.make(.classType(ClassType(
                classSymbol: annotationRetentionSymbol,
                args: [],
                nullability: .nonNull
            )))
            let valueName = interner.intern("value")
            let retentionName = interner.intern("Retention")
            let valueFQName = kotlinAnnotationPkg + [retentionName, valueName]
            let valueSymbol: SymbolID
            if let existing = symbols.lookup(fqName: valueFQName) {
                valueSymbol = existing
            } else {
                valueSymbol = symbols.define(
                    kind: .property,
                    name: valueName,
                    fqName: valueFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .constValue]
                )
            }
            symbols.setParentSymbol(retentionSymbol, for: valueSymbol)
            symbols.setPropertyType(retentionType, for: valueSymbol)
            symbols.setConstValueExprKind(.symbolRef(retentionEntrySymbol), for: valueSymbol)
        }

        if let requiresOptInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("RequiresOptIn")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: requiresOptInSymbol,
                symbols: symbols
            )
            registerSyntheticRequiresOptInLevelEnum(
                ownerSymbol: requiresOptInSymbol,
                ownerFQName: kotlinPkg + [interner.intern("RequiresOptIn")],
                packageSymbol: kotlinPkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let subclassOptInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("SubclassOptInRequired")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.CLASS"]
                ),
                to: subclassOptInSymbol,
                symbols: symbols
            )
            registerSyntheticSubclassOptInRequiredMarkerClassProperty(
                ownerSymbol: subclassOptInSymbol,
                ownerFQName: kotlinPkg + [interner.intern("SubclassOptInRequired")],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let consistentCopyVisibilitySymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("ConsistentCopyVisibility")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.CLASS"]
                ),
                to: consistentCopyVisibilitySymbol,
                symbols: symbols
            )
        }

        if let publishedApiSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("PublishedApi")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
                ),
                to: publishedApiSymbol,
                symbols: symbols
            )
        }

        if let ignorableReturnValueSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("IgnorableReturnValue")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.FUNCTION"]
                ),
                to: ignorableReturnValueSymbol,
                symbols: symbols
            )
        }

        if let exposedCopyVisibilitySymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("ExposedCopyVisibility")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.CLASS"]
                ),
                to: exposedCopyVisibilitySymbol,
                symbols: symbols
            )
        }

        if let optionalExpectationSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("OptionalExpectation")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: optionalExpectationSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalMultiplatform"),
                to: optionalExpectationSymbol,
                symbols: symbols
            )
        }

        if let throwsSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("Throws")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.CONSTRUCTOR",
                    ]
                ),
                to: throwsSymbol,
                symbols: symbols
            )
            registerSyntheticThrowsExceptionClassesPropertyAndConstructor(
                ownerSymbol: throwsSymbol,
                ownerFQName: kotlinPkg + [interner.intern("Throws")],
                kotlinPkg: kotlinPkg,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
        if let sinceKotlinSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("SinceKotlin")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FIELD",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
                ),
                to: sinceKotlinSymbol,
                symbols: symbols
            )
            registerSyntheticStringAnnotationPropertyAndConstructor(
                ownerSymbol: sinceKotlinSymbol,
                ownerFQName: kotlinPkg + [interner.intern("SinceKotlin")],
                propertyName: "version",
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let dslMarkerSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("DslMarker")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: dslMarkerSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                to: dslMarkerSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(annotationFQName: "kotlin.annotation.MustBeDocumented"),
                to: dslMarkerSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.sinceKotlin.qualifiedName,
                    arguments: ["1.1"]
                ),
                to: dslMarkerSymbol,
                symbols: symbols
            )
        }

        if let introducedAtSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("IntroducedAt")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.VALUE_PARAMETER"]
                ),
                to: introducedAtSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(annotationFQName: "kotlin.annotation.MustBeDocumented"),
                to: introducedAtSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.experimentalVersionOverloading.qualifiedName
                ),
                to: introducedAtSymbol,
                symbols: symbols
            )
            registerSyntheticStringAnnotationPropertyAndConstructor(
                ownerSymbol: introducedAtSymbol,
                ownerFQName: kotlinPkg + [interner.intern("IntroducedAt")],
                propertyName: "version",
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let mustUseReturnValuesSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("MustUseReturnValues")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.FILE",
                        "AnnotationTarget.CLASS",
                    ]
                ),
                to: mustUseReturnValuesSymbol,
                symbols: symbols
            )
        }

        if let parameterNameSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("ParameterName")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.TYPE"]
                ),
                to: parameterNameSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                to: parameterNameSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(annotationFQName: "kotlin.annotation.MustBeDocumented"),
                to: parameterNameSymbol,
                symbols: symbols
            )
            registerSyntheticParameterNameMembers(
                ownerSymbol: parameterNameSymbol,
                ownerFQName: kotlinPkg + [interner.intern("ParameterName")],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let publishedApiSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("PublishedApi")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
                ),
                to: publishedApiSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                to: publishedApiSymbol,
                symbols: symbols
            )
        }

        if let optInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("OptIn")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.LOCAL_VARIABLE",
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.TYPE",
                        "AnnotationTarget.EXPRESSION",
                        "AnnotationTarget.FILE",
                        "AnnotationTarget.TYPEALIAS",
                    ]
                ),
                to: optInSymbol,
                symbols: symbols
            )
        }
    }
}
