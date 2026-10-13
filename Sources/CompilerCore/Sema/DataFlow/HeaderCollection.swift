import Foundation

extension DataFlowSemaPhase {
    func isValueClassDeclaration(_ classDecl: ClassDecl) -> Bool {
        classDecl.modifiers.contains(.value) || classDecl.modifiers.contains(.inline)
    }

    func registerFileAnnotations(
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard !file.annotations.isEmpty else {
            return
        }

        let packageSymbol = symbols.lookup(fqName: file.packageFQName.isEmpty ? [interner.intern("_root_")] : file.packageFQName)
        let records = file.annotations.compactMap { annotation -> MetadataAnnotationRecord? in
            // File annotations are also kept on the package symbol so
            // binary annotations such as @file:JsExport can round-trip.
            // SOURCE-retained annotations only affect the current source file
            // and must not be written into a library's package metadata.
            if hasSourceRetention(
                annotation,
                file: file,
                symbols: symbols,
                interner: interner
            ) {
                return nil
            }
            return MetadataAnnotationRecord(
                annotationFQName: annotation.name,
                arguments: annotation.arguments,
                useSiteTarget: annotation.useSiteTarget
            )
        }
        if let packageSymbol {
            var merged = symbols.annotations(for: packageSymbol)
            for record in records where !merged.contains(record) {
                merged.append(record)
            }
            symbols.setAnnotations(merged, for: packageSymbol)
        }

        for annotation in file.annotations where KnownCompilerAnnotation.suppress.matches(annotation.name) {
            guard let fileRange = file.range else {
                continue
            }
            for argument in annotation.arguments {
                let code = argument.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                diagnostics.addSuppression(code: code, range: fileRange)
            }
        }
    }

    private func hasSourceRetention(
        _ annotation: AnnotationNode,
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = resolveAnnotationSymbol(
            named: annotation.name,
            in: file,
            symbols: symbols,
            interner: interner
        ) else {
            return false
        }
        if symbols.symbol(symbol)?.fqName.map(interner.resolve) == ["kotlin", "js", "JsFileName"] {
            // File annotations are registered before stdlib declaration
            // annotations have been collected, so this SOURCE-retained
            // declaration's metadata is not available at this point.
            return true
        }
        return symbols.annotations(for: symbol).contains { metaAnnotation in
            guard metaAnnotation.annotationFQName == "Retention"
                || metaAnnotation.annotationFQName == "kotlin.annotation.Retention"
            else {
                return false
            }
            return metaAnnotation.arguments.contains { argument in
                argument.contains("SOURCE")
            }
        }
    }

    /// Describes the symbol a top-level declaration introduces, without touching
    /// the symbol table. Shared by the forward-declaration pass and `collectHeader`
    /// so both agree on kind/visibility/flags.
    func topLevelDeclarationDescriptor(
        for decl: Decl,
        diagnostics: DiagnosticEngine?
    ) -> (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags)? {
        switch decl {
        case let .classDecl(classDecl):
            var classFlags = flags(from: classDecl.modifiers)
            classFlags.remove(.inlineFunction)
            if isValueClassDeclaration(classDecl) {
                classFlags.insert(.valueType)
            }

            // STDLIB-CLASS-010: Check for conflicting modifiers
            if classDecl.modifiers.contains(.abstract) && classDecl.modifiers.contains(.final) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Class cannot be both 'abstract' and 'final'.",
                    range: classDecl.range
                )
            }
            if classDecl.modifiers.contains(.sealed) && classDecl.modifiers.contains(.final) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Class cannot be both 'sealed' and 'final'.",
                    range: classDecl.range
                )
            }

            // STDLIB-CLASS-010: Abstract classes are implicitly open
            if classDecl.modifiers.contains(.abstract) {
                classFlags.insert(.openType)
            }
            // STDLIB-CLASS-010: Sealed classes are implicitly abstract
            if classDecl.modifiers.contains(.sealed) {
                classFlags.insert(.abstractType)
                classFlags.insert(.openType)
            }
            return (
                kind: classSymbolKind(for: classDecl),
                name: classDecl.name,
                range: classDecl.range,
                visibility: visibility(from: classDecl.modifiers),
                flags: classFlags
            )
        case let .interfaceDecl(interfaceDecl):
            var interfaceFlags = flags(from: interfaceDecl.modifiers)
            if interfaceDecl.isFunInterface {
                interfaceFlags.insert(.funInterface)
            }
            return (
                kind: .interface,
                name: interfaceDecl.name,
                range: interfaceDecl.range,
                visibility: visibility(from: interfaceDecl.modifiers),
                flags: interfaceFlags
            )
        case let .objectDecl(objectDecl):
            return (
                kind: .object,
                name: objectDecl.name,
                range: objectDecl.range,
                visibility: visibility(from: objectDecl.modifiers),
                flags: flags(from: objectDecl.modifiers)
            )
        case let .funDecl(funDecl):
            return (
                kind: .function,
                name: funDecl.name,
                range: funDecl.range,
                visibility: visibility(from: funDecl.modifiers),
                flags: flags(from: funDecl.modifiers)
            )
        case let .propertyDecl(propertyDecl):
            var propertyFlags = flags(from: propertyDecl.modifiers)
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            return (
                kind: .property,
                name: propertyDecl.name,
                range: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: propertyFlags
            )
        case let .typeAliasDecl(typeAliasDecl):
            return (
                kind: .typeAlias,
                name: typeAliasDecl.name,
                range: typeAliasDecl.range,
                visibility: visibility(from: typeAliasDecl.modifiers),
                flags: flags(from: typeAliasDecl.modifiers)
            )
        case let .enumEntryDecl(entry):
            return (
                kind: .field,
                name: entry.name,
                range: entry.range,
                visibility: .public,
                flags: []
            )
        }
    }

    func defineTopLevelSymbol(
        declaration: (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags),
        decl: Decl,
        file: ASTFile,
        symbols: SymbolTable,
        scope: Scope,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> SymbolID {
        let fqName = file.packageFQName + [declaration.name]
        let scopeExisting = scope.lookup(declaration.name).compactMap { symbolID -> SemanticSymbol? in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.fqName == fqName
            else {
                return nil
            }
            return symbol
        }
        let newIsExtensionProperty: Bool
        if case let .propertyDecl(pd) = decl {
            newIsExtensionProperty = pd.receiverType != nil
        } else {
            newIsExtensionProperty = false
        }
        let reusableSyntheticSymbol = newIsExtensionProperty ? nil : reusableSyntheticDeclarationSymbol(
            kind: declaration.kind,
            fqName: fqName,
            declarationFlags: declaration.flags,
            file: file,
            sourceManager: sourceManager,
            symbols: symbols
        )
        if reusableSyntheticSymbol == nil {
            checkAndReportDuplicateDeclaration(
                newKind: declaration.kind,
                fqName: fqName,
                range: declaration.range,
                symbols: symbols,
                diagnostics: diagnostics,
                newFlags: declaration.flags,
                additionalExisting: scopeExisting,
                newIsExtensionProperty: newIsExtensionProperty,
                topLevelVisibility: declaration.visibility,
                topLevelFileID: file.fileID
            )
        }
        let symbol: SymbolID
        if let reusableSyntheticSymbol {
            symbol = reusableSyntheticSymbol
            symbols.removeFlags(.synthetic, for: symbol)
            // Preserve semantic modifiers from the bundled declaration when a
            // predeclared synthetic placeholder is reused. Without this,
            // abstract/open/sealed flags are lost for source-backed types such
            // as kotlin.random.Random.
            symbols.insertFlags(declaration.flags, for: symbol)
            if shouldRestoreDeclSiteForReusableSyntheticSymbol(fqName: fqName, interner: interner) {
                symbols.setDeclSite(declaration.range, for: symbol)
            }
        } else {
            symbol = symbols.define(
                kind: declaration.kind,
                name: declaration.name,
                fqName: fqName,
                declSite: declaration.range,
                visibility: declaration.visibility,
                flags: declaration.flags,
                isExtensionProperty: newIsExtensionProperty,
                topLevelFileID: file.fileID
            )
        }
        symbols.setSourceFileID(file.fileID, for: symbol)
        scope.insert(symbol)
        return symbol
    }

    /// Returns the predeclared synthetic nominal that a bundled source
    /// declaration takes over, if one exists. Early synthetic stub passes
    /// register nominal placeholders (e.g. `kotlin.Comparator`) so other stubs
    /// can reference the type before bundled header collection runs; the
    /// bundled declaration then claims that placeholder instead of defining a
    /// duplicate symbol. User sources never claim placeholders — a same-name
    /// collision there must still surface as KSWIFTK-SEMA-0001.
    func reusableSyntheticDeclarationSymbol(
        kind: SymbolKind,
        fqName: [InternedString],
        declarationFlags: SymbolFlags,
        file: ASTFile,
        sourceManager: SourceManager,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard kind == .class || kind == .interface || kind == .object || kind == .enumClass else { return nil }
        guard sourceManager.path(of: file.fileID).hasPrefix("__bundled_") else { return nil }
        // expect/actual declarations keep the coexistence path that
        // checkAndReportDuplicateDeclaration already grants them over
        // synthetic-only collisions, instead of claiming the placeholder.
        guard !declarationFlags.contains(.expectDeclaration),
              !declarationFlags.contains(.actualDeclaration)
        else { return nil }
        return symbols.lookupAll(fqName: fqName).first { symbolID in
            guard let symbol = symbols.symbol(symbolID) else { return false }
            return symbol.kind == kind && symbol.flags.contains(.synthetic)
        }
    }

    func shouldRestoreDeclSiteForReusableSyntheticSymbol(
        fqName: [InternedString],
        interner: StringInterner
    ) -> Bool {
        // A shell reused without restoring its declSite stays non-source-backed
        // (`isSourceBackedSymbol` returns false): that is the remaining
        // compiler/metadata compatibility contract for nominals whose call
        // lowering, export, or member binding still assumes the pre-migration
        // shell. Golden dumping no longer reads declSite -- symbol origin is
        // classified from the tracked source file ID instead -- so unlisted
        // FQNames keep nil declSite only until their compiler-side paths are
        // migrated off the shell. Listed FQNames were migrated deliberately:
        // KSP-683 needs the Duration nominals source-backed for their
        // value-class and enum metadata, and KSP-1083 applies the same staged
        // source-shell treatment to the kotlin.concurrent atomic nominals
        // while their constructors and members remain residual.
        let resolvedFQName = fqName.map(interner.resolve)
        if resolvedFQName == ["kotlinx", "coroutines", "CoroutineName"]
            || resolvedFQName == ["kotlin", "collections", "Iterator"]
            || resolvedFQName == ["kotlin", "collections", "Map", "Entry"]
            || resolvedFQName == ["kotlin", "collections", "MutableMap", "MutableEntry"]
            || resolvedFQName == ["kotlin", "native", "ref", "WeakReference"]
            || resolvedFQName == ["kotlin", "native", "runtime", "RootSetStatistics"]
            // KSP-1259: reusing the synthetic Debugging object shell must still
            // leave the bundled Kotlin declaration source-backed.
            || resolvedFQName == ["kotlin", "native", "runtime", "Debugging"]
            || resolvedFQName == ["kotlin", "ranges", "IntProgression"]
            // KSP-1305: mirror the IntProgression staged source-shell treatment
            // for LongProgression's nominal and Companion.
            || resolvedFQName == ["kotlin", "ranges", "LongProgression"]
            // KSP-1313: mirror the staged progression source-shell treatment
            // for UIntProgression's nominal and Companion.
            || resolvedFQName == ["kotlin", "ranges", "UIntProgression"]
            || resolvedFQName == ["kotlin", "ranges", "CharProgression"]
            || resolvedFQName == ["kotlin", "time", "Duration"]
            || resolvedFQName == ["kotlin", "time", "DurationUnit"]
            // KSP-1472/KSP-1477/KSP-1479/KSP-1490: time API nominals are
            // declared in bundled source while early bootstrap still creates
            // compatibility shells for their signatures.
            || resolvedFQName == ["kotlin", "time", "AbstractDoubleTimeSource"]
            || resolvedFQName == ["kotlin", "time", "AbstractLongTimeSource"]
            || resolvedFQName == ["kotlin", "time", "Clock"]
            || resolvedFQName == ["kotlin", "time", "ComparableTimeMark"]
            || resolvedFQName == ["kotlin", "time", "ExperimentalTime"]
            || resolvedFQName == ["kotlin", "time", "Instant"]
            || resolvedFQName == ["kotlin", "time", "TestTimeSource"]
            || resolvedFQName == ["kotlin", "time", "TimeMark"]
            || resolvedFQName == ["kotlin", "time", "TimeSource"]
            || resolvedFQName == ["kotlin", "time", "TimedValue"]
            || resolvedFQName == ["kotlin", "native", "concurrent", "Future"]
            || resolvedFQName == ["kotlin", "text", "CharCategory"]
            || resolvedFQName == ["kotlin", "text", "CharDirectionality"]
            || resolvedFQName == ["kotlin", "native", "concurrent", "TransferMode"]
            // KUU-876: the source-backed InvalidMutabilityException must keep
            // its bundled declSite when the synthetic anchor is reused.
            || resolvedFQName == ["kotlin", "native", "concurrent", "InvalidMutabilityException"]
            // KSP-1361: Reusing the synthetic SequenceScope shell must still
            // leave the bundled Kotlin declaration source-backed.
            || resolvedFQName == ["kotlin", "sequences", "SequenceScope"]
            // KUU-936: the atomics-package AtomicNativePtr constructor and field
            // are bundled source; the synthetic shell keeps only residual members.
            || resolvedFQName == ["kotlin", "concurrent", "atomics", "AtomicNativePtr"] {
            return true
        }
        guard resolvedFQName.count == 3,
              resolvedFQName[0] == "kotlin",
              resolvedFQName[1] == "concurrent"
        else {
            return false
        }
        return [
            "AtomicArray",
            "AtomicInt",
            "AtomicIntArray",
            "AtomicLong",
            "AtomicLongArray",
            "AtomicNativePtr",
            "AtomicReference",
        ].contains(resolvedFQName[2])
    }

    /// Registers type parameters for a nominal type (class or interface) as symbols,
    /// sets their variances and upper bounds, and returns the symbol list and local map.
    func registerNominalTypeParameters(
        _ typeParams: [TypeParamDecl],
        ownerSymbol: SymbolID,
        fqName: [InternedString],
        namespacePrefix: String,
        declSite: SourceRange,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = [],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        sourceManager: SourceManager? = nil,
        diagnostics: DiagnosticEngine,
        enclosingTypeParameters: [InternedString: SymbolID] = [:]
    ) -> (symbols: [SymbolID], localMap: [InternedString: SymbolID]) {
        var typeParamSymbols: [SymbolID] = []
        var localTypeParameters = enclosingTypeParameters

        guard !typeParams.isEmpty else {
            return (symbols: typeParamSymbols, localMap: localTypeParameters)
        }

        types.setNominalTypeParameterVariances(
            typeParams.map(\.variance),
            for: ownerSymbol
        )
        // When a bundled source declaration reuses a synthetic shell
        // (`reusableSyntheticDeclarationSymbol`), the shell's type parameters are already
        // referenced by the residual synthetic members registered against it. Defining fresh
        // symbols here would leave those members typed against orphaned type parameters, so
        // adopt the shell's symbols and only re-apply variances and bounds to them.
        let existingTypeParamSymbols = types.nominalTypeParameterSymbols(for: ownerSymbol)
        let reusesShellTypeParameters = existingTypeParamSymbols.count == typeParams.count
            && zip(existingTypeParamSymbols, typeParams).allSatisfy { existing, declared in
                symbols.symbol(existing)?.name == declared.name
            }
        let typeParamNamespace = fqName + [interner.intern("\(namespacePrefix)\(ownerSymbol.rawValue)")]
        for (index, typeParam) in typeParams.enumerated() {
            let typeParamSymbol: SymbolID
            if reusesShellTypeParameters {
                typeParamSymbol = existingTypeParamSymbols[index]
            } else {
                let typeParamFQName = typeParamNamespace + [typeParam.name]
                typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: typeParam.name,
                    fqName: typeParamFQName,
                    declSite: declSite,
                    visibility: .private,
                    flags: []
                )
            }
            typeParamSymbols.append(typeParamSymbol)
            localTypeParameters[typeParam.name] = typeParamSymbol
        }
        types.setNominalTypeParameterSymbols(
            typeParamSymbols,
            for: ownerSymbol
        )
        for typeParam in typeParams {
            guard let typeParamSym = localTypeParameters[typeParam.name] else {
                continue
            }
            let resolvedBounds = typeParam.upperBounds.compactMap { boundRef in
                resolveTypeRef(
                    boundRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: fqName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    usageRange: declSite
                )
            }
            if !resolvedBounds.isEmpty {
                symbols.setTypeParameterUpperBounds(resolvedBounds, for: typeParamSym)
                symbols.recordTypeParameterForBoundConflictCheck(typeParamSym, declSite: declSite)
            }
        }

        return (symbols: typeParamSymbols, localMap: localTypeParameters)
    }
}
