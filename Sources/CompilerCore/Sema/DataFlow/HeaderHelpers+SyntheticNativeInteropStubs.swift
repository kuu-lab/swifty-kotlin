
/// Synthetic Kotlin/Native metaprogramming and C interop stubs.
extension DataFlowSemaPhase {
    func registerSyntheticNativeInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticNativeExperimentalAnnotations(
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeObjCAnnotations(
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCInteropStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeIdentityHashCodeStub(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeStackTraceAddressStub(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeUnhandledExceptionHookStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeByteArrayAccessorStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticNativeExperimentalAnnotations(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let experimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let experimentalPkgSymbol = symbols.lookup(fqName: experimentalPkg)

        let annotations: [(String, [String], String)] = [
            (
                "ExperimentalNativeApi",
                [
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
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "ExperimentalObjCName",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
            (
                "ExperimentalObjCRefinement",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
            (
                "ExperimentalObjCEnum",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
        ]

        for (name, targets, retention) in annotations {
            let symbol = ensureAnnotationClassSymbol(
                named: name,
                in: experimentalPkg,
                symbols: symbols,
                interner: interner
            )
            if let experimentalPkgSymbol {
                symbols.setParentSymbol(experimentalPkgSymbol, for: symbol)
            }
            appendStandardAnnotationMetadata(
                to: symbol,
                targets: targets,
                retention: retention,
                symbols: symbols
            )
            appendMetadataAnnotations(
                [
                    MetadataAnnotationRecord(
                        annotationFQName: "kotlin.RequiresOptIn",
                        arguments: ["level=RequiresOptIn.Level.ERROR"]
                    ),
                ],
                to: symbol,
                symbols: symbols
            )
        }
    }

    private func registerSyntheticNativeObjCAnnotations(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)

        let annotations: [(String, [String], String)] = [
            (
                "ObjCName",
                [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.FUNCTION",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "CName",
                [
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.CLASS",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "ObjCSignatureOverride",
                ["AnnotationTarget.FUNCTION"],
                "AnnotationRetention.BINARY"
            ),
            (
                "HidesFromObjC",
                [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "ShouldRefineInSwift",
                [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "RefinesInSwift",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
        ]

        for (name, targets, retention) in annotations {
            let symbol = ensureAnnotationClassSymbol(
                named: name,
                in: nativePkg,
                symbols: symbols,
                interner: interner
            )
            if let nativePkgSymbol {
                symbols.setParentSymbol(nativePkgSymbol, for: symbol)
            }
            appendStandardAnnotationMetadata(
                to: symbol,
                targets: targets,
                retention: retention,
                symbols: symbols
            )
        }

        let freezingIsDeprecatedSymbol = ensureAnnotationClassSymbol(
            named: "FreezingIsDeprecated",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: freezingIsDeprecatedSymbol)
        }
        appendStandardAnnotationMetadata(
            to: freezingIsDeprecatedSymbol,
            targets: [
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
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var freezingAnnotations = symbols.annotations(for: freezingIsDeprecatedSymbol)
        let freezingRequiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: [
                "message=Freezing API is deprecated since 1.7.20. See https://kotlinlang.org/docs/native-migration-guide.html for details",
                "level=RequiresOptIn.Level.WARNING",
            ]
        )
        if !freezingAnnotations.contains(freezingRequiresOptIn) {
            freezingAnnotations.append(freezingRequiresOptIn)
            symbols.setAnnotations(freezingAnnotations, for: freezingIsDeprecatedSymbol)
        }

        let obsoleteNativeApiSymbol = ensureAnnotationClassSymbol(
            named: "ObsoleteNativeApi",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: obsoleteNativeApiSymbol)
        }
        appendStandardAnnotationMetadata(
            to: obsoleteNativeApiSymbol,
            targets: [
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
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var obsoleteAnnotations = symbols.annotations(for: obsoleteNativeApiSymbol)
        let obsoleteRequiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: [
                "message=This API is obsolete and subject to removal in a future release.",
                "level=RequiresOptIn.Level.ERROR",
            ]
        )
        if !obsoleteAnnotations.contains(obsoleteRequiresOptIn) {
            obsoleteAnnotations.append(obsoleteRequiresOptIn)
            symbols.setAnnotations(obsoleteAnnotations, for: obsoleteNativeApiSymbol)
        }

        let eagerInitializationSymbol = ensureAnnotationClassSymbol(
            named: "EagerInitialization",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: eagerInitializationSymbol)
        }
        appendStandardAnnotationMetadata(
            to: eagerInitializationSymbol,
            targets: ["AnnotationTarget.PROPERTY"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var eagerInitializationAnnotations = symbols.annotations(for: eagerInitializationSymbol)
        let eagerInitializationMetaAnnotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi"),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"This annotation is a temporal migration assistance and may be removed in the future releases, please consider filing an issue about the case where it is needed\"",
                ]
            ),
        ]
        var didAppendEagerInitializationMetaAnnotation = false
        for record in eagerInitializationMetaAnnotations where !eagerInitializationAnnotations.contains(record) {
            eagerInitializationAnnotations.append(record)
            didAppendEagerInitializationMetaAnnotation = true
        }
        if didAppendEagerInitializationMetaAnnotation {
            symbols.setAnnotations(eagerInitializationAnnotations, for: eagerInitializationSymbol)
        }

        let hiddenFromObjCSymbol = ensureAnnotationClassSymbol(
            named: "HiddenFromObjC",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: hiddenFromObjCSymbol)
        }
        appendStandardAnnotationMetadata(
            to: hiddenFromObjCSymbol,
            targets: [
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.CLASS",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var hiddenFromObjCAnnotations = symbols.annotations(for: hiddenFromObjCSymbol)
        let hiddenFromObjCMetaAnnotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.native.HidesFromObjC"),
            MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalObjCRefinement"),
        ]
        var didAppendHiddenFromObjCMetaAnnotation = false
        for record in hiddenFromObjCMetaAnnotations where !hiddenFromObjCAnnotations.contains(record) {
            hiddenFromObjCAnnotations.append(record)
            didAppendHiddenFromObjCMetaAnnotation = true
        }
        if didAppendHiddenFromObjCMetaAnnotation {
            symbols.setAnnotations(hiddenFromObjCAnnotations, for: hiddenFromObjCSymbol)
        }

        let noInlineSymbol = ensureAnnotationClassSymbol(
            named: "NoInline",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: noInlineSymbol)
        }
        appendStandardAnnotationMetadata(
            to: noInlineSymbol,
            targets: [
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var noInlineAnnotations = symbols.annotations(for: noInlineSymbol)
        let experimentalNativeApiRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.experimental.ExperimentalNativeApi"
        )
        if !noInlineAnnotations.contains(experimentalNativeApiRecord) {
            noInlineAnnotations.append(experimentalNativeApiRecord)
            symbols.setAnnotations(noInlineAnnotations, for: noInlineSymbol)
        }
    }
}
