
/// Synthetic stubs for Kotlin stdlib experimental opt-in markers discovered
/// missing in STDLIB-EXPERIMENTAL-ABI-001.
///
/// Each marker is an annotation class annotated with `@RequiresOptIn` at the declared
/// severity level from the Kotlin stdlib source:
///
/// | Annotation                | Package              | Severity |
/// |---------------------------|----------------------|----------|
/// | ExperimentalVersionOverloading | kotlin          | ERROR    |
/// | ExpectRefinement          | kotlin.experimental  | @ExperimentalMultiplatform |
///
/// The common root opt-in markers (`ExperimentalUnsignedTypes`,
/// `ExperimentalMultiplatform`, `ExperimentalSubclassOptIn`) and the
/// `context parameters`/`uuid`/`io.encoding`/`reflect` experimental markers
/// (`ExperimentalContextParameters`, `ExperimentalUuidApi`,
/// `ExperimentalEncodingApi`, `ExperimentalAssociatedObjects`) are now declared
/// as bundled Kotlin source under `Sources/CompilerCore/Stdlib/kotlin/` (KSP-666, KSP-733).
///
/// See: https://kotlinlang.org/api/latest/jvm/stdlib/
extension DataFlowSemaPhase {
    func registerSyntheticExperimentalMarkerStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid

        // --- kotlin.ExperimentalVersionOverloading (ERROR) ---
        registerSyntheticExperimentalMarker(
            named: "ExperimentalVersionOverloading",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            severity: "ERROR",
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.experimental.ExpectRefinement ---
        let kotlinExperimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let kotlinExperimentalPkgSymbol = symbols.lookup(fqName: kotlinExperimentalPkg) ?? .invalid
        registerSyntheticExpectRefinementAnnotation(
            packageFQName: kotlinExperimentalPkg,
            packageSymbol: kotlinExperimentalPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// Registers a single experimental opt-in marker annotation class and attaches
    /// `@RequiresOptIn(level = RequiresOptIn.Level.<severity>)` to it so that the
    /// opt-in checker can emit the correct diagnostic severity.
    private func registerSyntheticExperimentalMarker(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        severity: String,
        message: String? = nil,
        targetArguments: [String]? = ["AnnotationTarget.ANNOTATION_CLASS"],
        retentionArgument: String? = "AnnotationRetention.BINARY",
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .annotationClass,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }

        // Attach @RequiresOptIn with the declared severity level.
        var requiresOptInArguments = ["level=RequiresOptIn.Level.\(severity)"]
        if let message {
            requiresOptInArguments.insert("message=\(message)", at: 0)
        }
        let requiresOptInRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: requiresOptInArguments
        )
        var annotations = symbols.annotations(for: classSymbol)
        if !annotations.contains(requiresOptInRecord) {
            annotations.append(requiresOptInRecord)
        }
        if let targetArguments {
            let targetRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: targetArguments
            )
            if !annotations.contains(targetRecord) {
                annotations.append(targetRecord)
            }
        }
        if let retentionArgument {
            let retentionRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: [retentionArgument]
            )
            if !annotations.contains(retentionRecord) {
                annotations.append(retentionRecord)
            }
        }
        symbols.setAnnotations(annotations, for: classSymbol)
    }

    private func registerSyntheticExpectRefinementAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("ExpectRefinement")
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .annotationClass,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }

        let metadata = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.CLASS"]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: ["AnnotationRetention.SOURCE"]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.SinceKotlin",
                arguments: ["\"2.2\""]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalMultiplatform"),
        ]

        var annotations = symbols.annotations(for: classSymbol)
        var didAppend = false
        for record in metadata where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: classSymbol)
        }

        let ownerType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        let initName = interner.intern("<init>")
        let initFQName = classFQName + [initName]
        let hasImplicitConstructor = symbols.lookupAll(fqName: initFQName).contains { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty && signature.returnType == ownerType
        }
        guard !hasImplicitConstructor else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(classSymbol, for: constructorSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: ownerType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: constructorSymbol
        )
    }
}
