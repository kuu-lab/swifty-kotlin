import Foundation

extension DataFlowSemaPhase {
    func contextParameterValueDeclarations(
        _ contextReceivers: [ContextReceiverDecl],
        interner: StringInterner
    ) -> [ValueParamDecl] {
        contextReceivers.enumerated().compactMap { index, contextReceiver in
            guard contextReceiver.isContextParameter else { return nil }
            return ValueParamDecl(
                name: contextReceiver.name ?? interner.intern("$contextParameter\(index)"),
                type: contextReceiver.type
            )
        }
    }

    private func syntheticDataClassMemberTypeParameterSymbols(
        ownerSymbol: SymbolID,
        types: TypeSystem
    ) -> [SymbolID] {
        types.nominalTypeParameterSymbols(for: ownerSymbol)
    }



    func registerAnnotations(
        for decl: Decl,
        symbol: SymbolID,
        declRange: SourceRange?,
        sourceFileID: FileID?,
        sourceFile: ASTFile?,
        sourceManager: SourceManager?,
        interner: StringInterner,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        registerAnnotations(
            metadataAnnotations(for: decl),
            symbol: symbol,
            declRange: declRange,
            sourceFileID: sourceFileID,
            sourceFile: sourceFile,
            sourceManager: sourceManager,
            interner: interner,
            symbols: symbols,
            diagnostics: diagnostics
        )

        guard let declRange else {
            return
        }
        guard let suppressionRange = suppressionRange(for: decl, declRange: declRange) else {
            return
        }
        for ann in decl.annotations where KnownCompilerAnnotation.suppress.matches(ann.name) {
            for arg in ann.arguments {
                let code = arg.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !code.isEmpty {
                    diagnostics.addSuppression(code: code, range: suppressionRange)
                }
            }
        }
    }

    func metadataAnnotations(for decl: Decl) -> [AnnotationNode] {
        guard case let .propertyDecl(property) = decl else {
            return decl.annotations
        }

        var annotations = property.annotations
        for accessor in [property.getter, property.setter].compactMap({ $0 }) {
            for annotation in accessor.annotations where !annotations.contains(annotation) {
                annotations.append(annotation)
            }
        }
        return annotations
    }

    func registerAnnotations(
        _ astAnnotations: [AnnotationNode],
        symbol: SymbolID,
        declRange: SourceRange?,
        sourceFileID: FileID?,
        sourceFile: ASTFile?,
        sourceManager: SourceManager?,
        interner: StringInterner,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        guard !astAnnotations.isEmpty else {
            return
        }

        let records = astAnnotations.map { ann in
            // Persist producer-side resolution so imported metadata does not
            // depend on the consumer having the producer's imports or AST.
            let resolvedFQName: String?
            if ann.name.contains(".") {
                resolvedFQName = ann.name
            } else {
                resolvedFQName = sourceFile
                    .flatMap {
                        resolveAnnotationSymbol(
                            named: ann.name, in: $0, symbols: symbols, interner: interner,
                            enclosingFQName: Array((symbols.symbol(symbol)?.fqName ?? []).dropLast())
                        )
                    }
                    .flatMap { symbols.symbol($0)?.fqName.map(interner.resolve).joined(separator: ".") }
            }
            let name = resolvedFQName.flatMap { $0.isEmpty ? nil : $0 } ?? ann.name
            return MetadataAnnotationRecord(
                annotationFQName: name,
                arguments: name == "kotlin.annotation.Retention"
                    ? canonicalRetentionArguments(ann.arguments, file: sourceFile, interner: interner) : ann.arguments,
                useSiteTarget: ann.useSiteTarget,
                usageID: ann.usageID
            )
        }
        symbols.setAnnotations(records, for: symbol)

        if let ksSymbolName = astAnnotations.first(where: { KnownCompilerAnnotation.ksSymbolName.matches($0.name) }) {
            if !isBundledSourceFile(sourceFileID, sourceManager: sourceManager) {
                diagnostics.error(
                    "KSWIFTK-SEMA-0007",
                    "@KsSymbolName is reserved for bundled stdlib declarations.",
                    range: declRange
                )
            }
            let symbolKind = symbols.symbol(symbol)?.kind
            if (symbolKind == .function || symbolKind == .constructor || symbolKind == .property || symbolKind == .object),
               let linkName = ksSymbolName.arguments.first.map(annotationStringArgumentValue(_:)),
               !linkName.isEmpty
            {
                symbols.setExternalLinkName(linkName, for: symbol)
            }
        }

        // Register @Suppress ranges so matching diagnostics are filtered.
        guard let declRange else {
            return
        }
        for ann in astAnnotations where KnownCompilerAnnotation.suppress.matches(ann.name) {
            for arg in ann.arguments {
                let code = arg.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !code.isEmpty {
                    diagnostics.addSuppression(code: code, range: declRange)
                }
            }
        }
    }

    func diagnoseReservedExternalFunctionUse(
        _ function: FunDecl,
        sourceFileID: FileID,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine
    ) {
        guard function.modifiers.contains(.external),
              !isBundledSourceFile(sourceFileID, sourceManager: sourceManager)
        else {
            return
        }
        diagnostics.error(
            "KSWIFTK-SEMA-0008",
            "The external modifier is reserved for bundled stdlib declarations.",
            range: function.range
        )
    }

    private func isBundledSourceFile(_ fileID: FileID?, sourceManager: SourceManager?) -> Bool {
        guard let fileID, let sourceManager else {
            return false
        }
        return sourceManager.origin(of: fileID)?.isBundledStdlib == true
    }

    private func annotationStringArgumentValue(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let equals = trimmed.firstIndex(of: "=") {
            let name = trimmed[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "name" || name == "value" {
                trimmed = String(trimmed[trimmed.index(after: equals)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        while trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'")
    }

    private func suppressionRange(for decl: Decl, declRange: SourceRange?) -> SourceRange? {
        guard let declRange else {
            return nil
        }

        let bodyRange: SourceRange? = switch decl {
        case let .funDecl(funDecl):
            switch funDecl.body {
            case let .block(_, range), let .expr(_, range):
                range
            case .unit:
                nil
            }
        case let .propertyDecl(propertyDecl):
            switch (propertyDecl.getter?.body, propertyDecl.setter?.body) {
            case (let getterBody?, _):
                switch getterBody {
                case let .block(_, range), let .expr(_, range):
                    range
                case .unit:
                    nil
                }
            case (_, let setterBody?):
                switch setterBody {
                case let .block(_, range), let .expr(_, range):
                    range
                case .unit:
                    nil
                }
            default:
                nil
            }
        case let .classDecl(classDecl):
            classDecl.range
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.range
        case let .objectDecl(objectDecl):
            objectDecl.range
        case let .typeAliasDecl(typeAliasDecl):
            typeAliasDecl.range
        case let .enumEntryDecl(enumEntryDecl):
            enumEntryDecl.range
        }

        guard let bodyRange else {
            return declRange
        }
        return SourceRange(start: declRange.start, end: bodyRange.end)
    }

    func attachCompilerMetadataAnnotations(
        symbols: SymbolTable,
        types: TypeSystem,
        moduleName: String,
        interner: StringInterner
    ) {
        let encoder = MetadataEncoder()
        let targets = symbols.allSymbols().filter { symbol in
            guard Self.compilerMetadataAnnotatedKinds.contains(symbol.kind),
                  !symbol.flags.contains(.synthetic)
            else {
                return false
            }
            return !symbols.annotations(for: symbol.id).contains {
                KnownCompilerAnnotation.metadata.matches($0.annotationFQName)
            }
        }

        let recordsBySymbol = targets.reduce(into: [SymbolID: MetadataRecord]()) { partial, symbol in
            partial[symbol.id] = encoder.buildRecord(
                for: symbol,
                symbols: symbols,
                types: types,
                moduleName: moduleName,
                interner: interner
            )
        }

        for symbol in targets {
            guard let record = recordsBySymbol[symbol.id] else {
                continue
            }
            // Strip any existing kotlin.Metadata annotation before appending the new one
            // to prevent infinite nesting when the symbol is re-processed.
            var annotations = symbols.annotations(for: symbol.id).filter {
                !KnownCompilerAnnotation.metadata.matches($0.annotationFQName)
            }
            annotations.append(encoder.metadataAnnotationRecord(for: record))
            symbols.setAnnotations(annotations, for: symbol.id)
        }
    }

    private static let compilerMetadataAnnotatedKinds: Set<SymbolKind> = [
        .class,
        .interface,
        .object,
        .enumClass,
        .annotationClass,
    ]

    /// Base value for synthetic type parameter symbol IDs used in metadata encoding.
    /// Shared between MetadataTypeSignatureParser (encoding) and collectSyntheticTypeParameters (decoding).
    static var syntheticTypeParameterBase: Int32 {
        -1_000_000
    }

    func definePackageSymbol(for file: ASTFile, symbols: SymbolTable, interner: StringInterner) -> SymbolID {
        let package = file.packageFQName.isEmpty ? [interner.intern("_root_")] : file.packageFQName
        let name = package.last ?? interner.intern("_root_")
        if let existing = symbols.lookup(fqName: package) {
            return existing
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: package,
            declSite: nil,
            visibility: .public
        )
    }

    /// Assigns the compilation module FQN to every source symbol that has a source file but no
    /// explicit module (library imports set their own module FQN during `loadImportedLibrarySymbols`).
    func assignCompilationModuleFQNames(
        symbols: SymbolTable,
        moduleName: String,
        interner: StringInterner
    ) {
        let moduleFQN = interner.intern(moduleName)
        for symbol in symbols.allSymbols() where symbols.moduleFQN(for: symbol.id) == nil {
            if symbols.sourceFileID(for: symbol.id) != nil {
                symbols.setModuleFQN(moduleFQN, for: symbol.id)
            }
        }
    }

    func classSymbolKind(for classDecl: ClassDecl) -> SymbolKind {
        if classDecl.modifiers.contains(.annotationClass) {
            return .annotationClass
        }
        if classDecl.modifiers.contains(.enumModifier) {
            return .enumClass
        }
        return .class
    }

    func visibility(from modifiers: Modifiers) -> Visibility {
        Visibility(modifiers: modifiers)
    }

    func restrictedVisibility(_ lhs: Visibility, _ rhs: Visibility) -> Visibility {
        switch (lhs, rhs) {
        case (.private, _), (_, .private):
            .private
        case (.protected, _), (_, .protected):
            .protected
        case (.internal, _), (_, .internal):
            .internal
        default:
            .public
        }
    }

    /// Computes the effective visibility for a class's constructor (primary or
    /// secondary) and whether that visibility was inherited from the owning
    /// class/object rather than written explicitly on the constructor itself.
    ///
    /// The distinction matters for `VisibilityChecker`: an inherited-private
    /// constructor's true accessibility ceiling is the owner's own visibility
    /// (e.g. file scope for a top-level `private class`), whereas an explicitly
    /// `private constructor` stays scoped to the class body/companion even when
    /// its owner happens to carry the same visibility keyword.
    func constructorVisibilityDetail(
        explicitModifiers: Modifiers,
        classKind: SymbolKind,
        isSealedClass: Bool,
        declarationVisibility: Visibility
    ) -> (visibility: Visibility, isInheritedFromOwner: Bool) {
        let explicitVisibilityModifiers: Modifiers = [.private, .internal, .protected, .public]
        if !explicitModifiers.isDisjoint(with: explicitVisibilityModifiers) {
            return (visibility(from: explicitModifiers), false)
        }
        if classKind == .class, isSealedClass {
            return (.protected, false)
        }
        return (declarationVisibility, true)
    }

    func primaryConstructorVisibilityDetail(
        for classDecl: ClassDecl,
        classKind: SymbolKind,
        declarationVisibility: Visibility
    ) -> (visibility: Visibility, isInheritedFromOwner: Bool) {
        constructorVisibilityDetail(
            explicitModifiers: classDecl.primaryConstructorModifiers,
            classKind: classKind,
            isSealedClass: classDecl.modifiers.contains(.sealed),
            declarationVisibility: declarationVisibility
        )
    }

    func primaryConstructorVisibility(
        for classDecl: ClassDecl,
        classKind: SymbolKind,
        declarationVisibility: Visibility
    ) -> Visibility {
        primaryConstructorVisibilityDetail(
            for: classDecl,
            classKind: classKind,
            declarationVisibility: declarationVisibility
        ).visibility
    }

    func primaryConstructorVisibility(
        for classDecl: ClassDecl,
        classSymbol: SemanticSymbol?
    ) -> Visibility {
        primaryConstructorVisibility(
            for: classDecl,
            classKind: classSymbol?.kind ?? classSymbolKind(for: classDecl),
            declarationVisibility: classSymbol?.visibility ?? visibility(from: classDecl.modifiers)
        )
    }

    func hasCompilerAnnotation(
        _ annotation: KnownCompilerAnnotation,
        on annotations: [AnnotationNode]
    ) -> Bool {
        annotations.contains { annotation.matches($0.name) }
    }

    func dataClassUsesConsistentCopyVisibility(_ classDecl: ClassDecl) -> Bool {
        hasCompilerAnnotation(.consistentCopyVisibility, on: classDecl.annotations)
    }

    func dataClassUsesExposedCopyVisibility(_ classDecl: ClassDecl) -> Bool {
        hasCompilerAnnotation(.exposedCopyVisibility, on: classDecl.annotations)
    }

    func dataClassCopyVisibility(
        for classDecl: ClassDecl,
        classSymbol: SemanticSymbol?
    ) -> Visibility {
        guard dataClassUsesConsistentCopyVisibility(classDecl) else {
            return .public
        }
        return primaryConstructorVisibility(for: classDecl, classSymbol: classSymbol)
    }

    func flags(from modifiers: Modifiers) -> SymbolFlags {
        SymbolFlags(modifiers: modifiers)
    }

    func inheritedExpectActualFlags(
        _ flags: SymbolFlags,
        from ownerSymbol: SymbolID,
        symbols: SymbolTable,
        includingActual: Bool = false
    ) -> SymbolFlags {
        guard !flags.contains(.expectDeclaration),
              !flags.contains(.actualDeclaration),
              let ownerFlags = symbols.symbol(ownerSymbol)?.flags
        else {
            return flags
        }

        var inheritedFlags = flags
        if ownerFlags.contains(.expectDeclaration) {
            inheritedFlags.insert(.expectDeclaration)
        } else if includingActual, ownerFlags.contains(.actualDeclaration) {
            inheritedFlags.insert(.actualDeclaration)
        }
        return inheritedFlags
    }

    func hasDeclarationConflict(
        newKind: SymbolKind,
        existing: [SemanticSymbol],
        symbols: SymbolTable? = nil,
        newIsExtensionProperty: Bool = false,
        newHasContextParameters: Bool = false
    ) -> Bool {
        guard !existing.isEmpty else {
            return false
        }
        // Package symbols share the FQ-name table but live in a separate namespace,
        // so they never conflict with declarations in that package.
        if newKind == .package {
            return false
        }
        let nonPackageExisting = existing.filter { $0.kind != .package }
        guard !nonPackageExisting.isEmpty else {
            return false
        }
        func isCallableLike(_ kind: SymbolKind) -> Bool {
            switch kind {
            case .function, .constructor:
                true
            default:
                false
            }
        }
        if newKind == .property {
            return nonPackageExisting.contains { existing in
                if isCallableLike(existing.kind) { return false }
                guard existing.kind == .property else { return true }
                if newIsExtensionProperty {
                    return false
                }
                let existingHasContextParameters: Bool
                if let symbols,
                   let getter = symbols.extensionPropertyGetterAccessor(for: existing.id),
                   let signature = symbols.functionSignature(for: getter) {
                    existingHasContextParameters = !signature.contextParameterTypes.isEmpty
                } else {
                    existingHasContextParameters = false
                }
                return !existing.flags.contains(.synthetic)
                    && !(symbols?.hasExtensionPropertyReceiver(existing.id) ?? false)
                    && !newHasContextParameters
                    && !existingHasContextParameters
            }
        }
        if isCallableLike(newKind) {
            return nonPackageExisting.contains {
                !(isCallableLike($0.kind) || $0.kind == .property || isNominalTypeSymbol($0.kind))
            }
        }
        // KSP-CAP-006: a class/interface/object/enum/annotation-class/typealias
        // may coexist with a top-level function of the same name (e.g. `class
        // Random` + `fun Random(seed: Long): Random`, the real kotlin-stdlib
        // factory-function idiom). This mirrors the tolerance already granted
        // above for the opposite declaration order (callable declared first),
        // so the check no longer depends on which of the two comes first in
        // source order. A second nominal type (or a property) of the same name
        // still conflicts.
        if isNominalTypeSymbol(newKind) {
            return nonPackageExisting.contains { !isCallableLike($0.kind) }
        }
        if isOverloadableSymbol(newKind) {
            return nonPackageExisting.contains(where: { !isOverloadableSymbol($0.kind) })
        }
        return true
    }

    func isOverloadableSymbol(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
    }

    /// Checks for a duplicate declaration conflict at the given fully-qualified name and
    /// emits the standard KSWIFTK-SEMA-0001 diagnostic when a conflict is detected.
    /// An `expect` and `actual` pair sharing the same FQ name is NOT a conflict.
    /// This includes `actual typealias` implementations of expect classes and
    /// annotation classes, such as `kotlin.concurrent.Volatile`.
    func checkAndReportDuplicateDeclaration(
        newKind: SymbolKind,
        fqName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        newFlags: SymbolFlags = [],
        additionalExisting: [SemanticSymbol] = [],
        newIsExtensionProperty: Bool = false,
        newHasContextParameters: Bool = false,
        topLevelVisibility: Visibility? = nil,
        topLevelFileID: FileID? = nil
    ) {
        var existingByID: [SymbolID: SemanticSymbol] = [:]
        for symbol in symbols.lookupAll(fqName: fqName).compactMap({ symbols.symbol($0) }) {
            existingByID[symbol.id] = symbol
        }
        for symbol in additionalExisting where symbol.fqName == fqName {
            existingByID[symbol.id] = symbol
        }
        // A source declaration may replace a declaration imported from a
        // dependency with the same FQName. Only declarations already owned by
        // this compilation participate in SEMA-0001 redeclaration checks.
        // Imported library symbols carry `.importedLibrary`; bundled source
        // declarations do not, so same-module source duplicates still fail.
        let existing = existingByID.values.filter { existing in
            guard !existing.flags.contains(.importedLibrary) else { return false }
            // Callable parameters are indexed under `callableFQName + name`.
            // When a factory shares a name with a class, that encoding can
            // overlap a class member's FQName even though the parameter does
            // not occupy the member declaration namespace.
            guard existing.kind != .valueParameter, existing.kind != .typeParameter else { return false }
            guard let topLevelVisibility, let topLevelFileID else { return true }
            return !symbols.canCoexistAsFilePrivateTopLevelCallable(
                kind: newKind, visibility: topLevelVisibility, fileID: topLevelFileID, existing: existing
            )
        }
        if newFlags.contains(.expectDeclaration) || newFlags.contains(.actualDeclaration) {
            let existingNonPackage = existing.filter {
                $0.kind != .package && !$0.flags.contains(.synthetic)
            }
            if existingNonPackage.count == 1,
               let existingSymbol = existingNonPackage.first,
               isCompatibleExpectActualPair(newKind: newKind, newFlags: newFlags, existing: existingSymbol)
            {
                return
            }
            if existingNonPackage.isEmpty {
                return
            }
        }
        if newKind == .property,
           !newFlags.contains(.synthetic)
        {
            let existingNonPackage = existing.filter { $0.kind != .package }
            if !existingNonPackage.isEmpty,
               existingNonPackage.allSatisfy({ $0.kind == .property && $0.flags.contains(.synthetic) })
            {
                return
            }
        }
        if hasDeclarationConflict(
            newKind: newKind,
            existing: existing,
            symbols: symbols,
            newIsExtensionProperty: newIsExtensionProperty,
            newHasContextParameters: newHasContextParameters
        ) {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate declaration in the same package scope.",
                range: range
            )
        }
    }

    func checkAndReportDuplicateExtensionPropertyReceiver(
        propertySymbol: SymbolID,
        receiverType: TypeID,
        fqName: [InternedString],
        range: SourceRange?,
        newFlags: SymbolFlags,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        let matchingDeclarations = symbols.lookupAll(fqName: fqName).compactMap { id -> SemanticSymbol? in
            guard id != propertySymbol,
                  let existing = symbols.symbol(id),
                  existing.kind == .property,
                  !existing.flags.contains(.synthetic),
                  symbols.hasExtensionPropertyReceiver(id),
                  symbols.extensionPropertyReceiverType(for: id) == receiverType
            else {
                return nil
            }
            return existing
        }
        guard !matchingDeclarations.isEmpty else { return }
        if matchingDeclarations.count == 1,
           let existing = matchingDeclarations.first,
           isCompatibleExpectActualPair(newKind: .property, newFlags: newFlags, existing: existing)
        {
            return
        }
        diagnostics.error(
            "KSWIFTK-SEMA-0001",
            "Duplicate declaration in the same package scope.",
            range: range
        )
    }

    func checkAndReportDuplicateContextPropertyParameters(
        propertySymbol: SymbolID,
        contextParameterTypes: [TypeID],
        fqName: [InternedString],
        range: SourceRange?,
        newFlags: SymbolFlags,
        topLevelVisibility: Visibility,
        topLevelFileID: FileID,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        guard !contextParameterTypes.isEmpty else { return }
        let matchingDeclarations = symbols.lookupAll(fqName: fqName).compactMap { id -> SemanticSymbol? in
            guard id != propertySymbol,
                  let existing = symbols.symbol(id),
                  existing.kind == .property,
                  !existing.flags.contains(.synthetic),
                  !existing.flags.contains(.importedLibrary),
                  !symbols.hasExtensionPropertyReceiver(id),
                  !symbols.canCoexistAsFilePrivateTopLevelCallable(
                      kind: .property,
                      visibility: topLevelVisibility,
                      fileID: topLevelFileID,
                      existing: existing
                  ),
                  let getter = symbols.extensionPropertyGetterAccessor(for: id),
                  let signature = symbols.functionSignature(for: getter),
                  signature.contextParameterTypes == contextParameterTypes
            else {
                return nil
            }
            return existing
        }
        guard !matchingDeclarations.isEmpty else { return }
        if matchingDeclarations.count == 1,
           let existing = matchingDeclarations.first,
           isCompatibleExpectActualPair(newKind: .property, newFlags: newFlags, existing: existing)
        {
            return
        }
        diagnostics.error(
            "KSWIFTK-SEMA-0001",
            "Duplicate declaration in the same package scope.",
            range: range
        )
    }

    private func hasUserDeclaredFunction(
        fqName: [InternedString],
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        symbols.lookupAll(fqName: fqName).contains { id in
            guard let symbol = symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: id)
            else {
                return false
            }
            // Expression-bodied members without an explicit return type carry a provisional
            // `Any` here (the real type is inferred later), so the return type is only compared
            // when the user declared one that is not that placeholder.
            let returnTypeMatches = signature.returnType == returnType
                || signature.returnType == types.anyType
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && returnTypeMatches
        }
    }

    func collectSyntheticToString(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        requireDataTypeFlag: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope?,
        interner: StringInterner
    ) {
        if requireDataTypeFlag {
            guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
                return
            }
        }
        // Kotlin data classes and data objects keep inherited final implementations
        // of the generated Any members.
        let toStringName = interner.intern("toString")
        if symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true,
           hasInheritedFinalDataClassMember(
               ownerSymbol: ownerSymbol,
               name: toStringName,
               parameterTypes: [],
               returnType: types.stringType,
               symbols: symbols,
               types: types
           ) {
            return
        }
        let toStringFQName = ownerFQName + [toStringName]
        let stringType = types.stringType
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )
        guard !hasUserDeclaredFunction(
            fqName: toStringFQName,
            receiverType: ownerType,
            parameterTypes: [],
            returnType: stringType,
            symbols: symbols,
            types: types
        ) else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: toStringName,
            fqName: toStringFQName,
            declSite: nil,
            visibility: .public,
            flags: symbols.symbol(ownerSymbol)?.kind == .annotationClass
                ? [.synthetic, .overrideMember] : [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: stringType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: funcSymbol
        )
        scope?.insert(funcSymbol)
    }

    /// Collects data-class and data-object generated members after superclass edges are bound.
    func collectDataTypeGeneratedMembersAfterInheritance(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) {
        for rawDeclID in 0 ..< ast.arena.declCount {
            let declID = DeclID(rawValue: Int32(rawDeclID))
            let ownerSymbol: SymbolID
            let owner: SemanticSymbol
            let requireDataTypeFlag: Bool
            switch ast.arena.decl(declID) {
            case let .classDecl(classDecl) where classDecl.modifiers.contains(.data):
                guard let symbol = bindings.declSymbols[declID],
                      let info = symbols.symbol(symbol)
                else {
                    continue
                }
                ownerSymbol = symbol
                owner = info
                requireDataTypeFlag = true
                validateDataClassComponentNSupertypeConflicts(
                    classDecl: classDecl,
                    ownerSymbol: symbol,
                    ownerFQName: info.fqName,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    diagnostics: diagnostics
                )
            case let .objectDecl(objectDecl) where objectDecl.modifiers.contains(.data):
                guard let symbol = bindings.declSymbols[declID],
                      let info = symbols.symbol(symbol)
                else {
                    continue
                }
                ownerSymbol = symbol
                owner = info
                requireDataTypeFlag = false
            default:
                continue
            }
            let typeArguments = types.nominalTypeParameterSymbols(for: ownerSymbol).map {
                TypeArg.invariant(types.make(.typeParam(TypeParamType(symbol: $0))))
            }
            let ownerType = types.make(.classType(ClassType(
                classSymbol: ownerSymbol,
                args: typeArguments,
                nullability: .nonNull
            )))
            collectSyntheticHashCode(
                ownerSymbol: ownerSymbol,
                ownerFQName: owner.fqName,
                ownerType: ownerType,
                requireDataTypeFlag: requireDataTypeFlag,
                symbols: symbols,
                types: types,
                scope: nil,
                interner: interner
            )
            collectSyntheticEquals(
                ownerSymbol: ownerSymbol,
                ownerFQName: owner.fqName,
                ownerType: ownerType,
                requireDataTypeFlag: requireDataTypeFlag,
                symbols: symbols,
                types: types,
                scope: nil,
                interner: interner
            )
            collectSyntheticToString(
                ownerSymbol: ownerSymbol,
                ownerFQName: owner.fqName,
                ownerType: ownerType,
                requireDataTypeFlag: requireDataTypeFlag,
                symbols: symbols,
                types: types,
                scope: nil,
                interner: interner
            )
        }
    }

    /// Returns the closest member declared on a superclass in the chain
    /// (interface supertypes do not participate) whose name, arity and — when
    /// `returnType` is non-nil — return type match a generated member.
    /// `private` members are invisible to the subclass and are skipped.
    private func inheritedClassMemberForGeneratedDataClassMember(
        ownerSymbol: SymbolID,
        name: InternedString,
        parameterTypes: [TypeID],
        returnType: TypeID?,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> SymbolID? {
        var currentSuperclass = symbols.directSupertypes(for: ownerSymbol).first {
            symbols.symbol($0)?.kind == .class
        }
        while let superclass = currentSuperclass,
              let superclassSymbol = symbols.symbol(superclass) {
            if let memberID = symbols.children(ofFQName: superclassSymbol.fqName).first(where: { memberID in
                guard let member = symbols.symbol(memberID),
                      member.kind == .function,
                      member.name == name,
                      member.visibility != .private,
                      let signature = symbols.functionSignature(for: memberID),
                      let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = types.kind(of: types.makeNonNullable(receiverType)),
                      receiverClass.classSymbol == superclass
                else {
                    return false
                }
                guard signature.parameterTypes == parameterTypes else {
                    return false
                }
                if let returnType {
                    return signature.returnType == returnType || signature.returnType == types.anyType
                }
                return true
            }) {
                return memberID
            }
            currentSuperclass = symbols.directSupertypes(for: superclass).first {
                symbols.symbol($0)?.kind == .class
            }
        }
        return nil
    }

    /// Returns whether the closest superclass declaration of a generated data-class member is final.
    private func hasInheritedFinalDataClassMember(
        ownerSymbol: SymbolID,
        name: InternedString,
        parameterTypes: [TypeID],
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard let memberID = inheritedClassMemberForGeneratedDataClassMember(
            ownerSymbol: ownerSymbol,
            name: name,
            parameterTypes: parameterTypes,
            returnType: returnType,
            symbols: symbols,
            types: types
        ) else {
            return false
        }
        return symbols.symbol(memberID)?.flags.contains(.finalMember) == true
    }

    /// KUU-3254: a data class's generated `componentN()` must be able to
    /// override each effective inherited member with the same name and arity.
    /// An effectively final member, or a member whose return type is not a
    /// supertype of the generated one, conflicts — kotlinc reports
    /// "generated for the data class conflicts with the supertype member".
    /// `private` members are invisible and never conflict.
    private func validateDataClassComponentNSupertypeConflicts(
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) {
        let componentReturnTypes = dataClassPrimaryConstructorParameterTypes(
            classDecl: classDecl,
            ownerSymbol: ownerSymbol,
            ownerFQName: ownerFQName,
            symbols: symbols,
            interner: interner
        )
        for (index, _) in classDecl.primaryConstructorParams.enumerated() {
            let componentName = interner.intern("component\(index + 1)")
            // An explicit user declaration suppresses generation; regular
            // override validation owns any conflict for it.
            let hasUserDeclared = symbols.lookupAll(fqName: ownerFQName + [componentName]).contains { id in
                guard let sym = symbols.symbol(id),
                      sym.kind == .function,
                      !sym.flags.contains(.synthetic)
                else { return false }
                return true
            }
            if hasUserDeclared { continue }

            for memberID in effectiveInheritedDataClassComponentMembers(
                ownerSymbol: ownerSymbol,
                name: componentName,
                symbols: symbols,
                types: types
            ) {
                guard let member = symbols.symbol(memberID),
                      let memberSignature = symbols.functionSignature(for: memberID)
                else { continue }

                // Interface members can never be final. Kotlin class members
                // are final unless declared `open`/`abstract` or overriding
                // without `final`.
                let memberOwnerIsInterface = symbols.parentSymbol(for: memberID)
                    .flatMap { symbols.symbol($0) }?.kind == .interface
                let isEffectivelyFinal = !memberOwnerIsInterface
                    && (member.flags.contains(.finalMember)
                        || (!member.flags.contains(.overrideMember)
                            && !member.flags.contains(.openType)
                            && !member.flags.contains(.abstractType)))
                let generatedReturn = componentReturnTypes.map { $0[index] }
                // A type-parameter return is left unvalidated: substituting it
                // through the supertype's type arguments is required to
                // compare precisely and is rare enough to stay out of this
                // check.
                let returnTypesCompatible = generatedReturn == nil
                    || types.typeContainsAnyTypeParam(memberSignature.returnType)
                    || types.isSubtype(generatedReturn ?? types.anyType, memberSignature.returnType)
                guard isEffectivelyFinal || !returnTypesCompatible else { continue }

                let generatedReturnName = generatedReturn.map { types.renderType($0) } ?? "?"
                let supertypeName = member.fqName.dropLast()
                    .map { interner.resolve($0) }.joined(separator: ".")
                diagnostics.error(
                    "KSWIFTK-SEMA-0442",
                    "Function 'fun \(interner.resolve(componentName))(): \(generatedReturnName)' generated for the data class conflicts with the supertype member 'fun \(interner.resolve(componentName))(): \(types.renderType(memberSignature.returnType))' defined in '\(supertypeName)'.",
                    range: classDecl.range
                )
            }
        }
    }

    /// All parameterless functions named `name` visible on the supertype
    /// chain — classes and interfaces alike — that the generated member must
    /// override. A declaration shadowed by a more-derived redeclaration of the
    /// same member no longer participates: the override targets the closest
    /// redeclaration on each path.
    private func effectiveInheritedDataClassComponentMembers(
        ownerSymbol: SymbolID,
        name: InternedString,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [SymbolID] {
        var collected: [SymbolID] = []
        var visited: Set<SymbolID> = [ownerSymbol]
        var queue = symbols.directSupertypes(for: ownerSymbol)
        while let current = queue.popLast() {
            guard visited.insert(current).inserted,
                  let currentSym = symbols.symbol(current),
                  currentSym.kind == .class || currentSym.kind == .interface
            else { continue }
            for memberID in symbols.children(ofFQName: currentSym.fqName) {
                guard let member = symbols.symbol(memberID),
                      member.kind == .function,
                      member.name == name,
                      member.visibility != .private,
                      let signature = symbols.functionSignature(for: memberID),
                      signature.parameterTypes.isEmpty,
                      let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = types.kind(of: types.makeNonNullable(receiverType)),
                      receiverClass.classSymbol == current
                else { continue }
                collected.append(memberID)
            }
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }
        return collected.filter { memberID in
            guard let memberOwner = symbols.parentSymbol(for: memberID) else { return true }
            return !collected.contains { otherID in
                otherID != memberID
                    && symbols.parentSymbol(for: otherID).map {
                        isNominalSubtypeOf($0, memberOwner, symbols: symbols)
                    } == true
            }
        }
    }

    /// Nominal (type-argument-insensitive) strict subtype check over direct
    /// supertypes.
    private func isNominalSubtypeOf(
        _ candidate: SymbolID,
        _ base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        var visited: Set<SymbolID> = [candidate]
        var queue = symbols.directSupertypes(for: candidate)
        while let current = queue.popLast() {
            if current == base { return true }
            if visited.insert(current).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: current))
            }
        }
        return false
    }

    func collectSyntheticEquals(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        requireDataTypeFlag: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope?,
        interner: StringInterner
    ) {
        if requireDataTypeFlag {
            guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
                return
            }
        }
        let equalsName = interner.intern("equals")
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = types.nullableAnyType
        if symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true,
           hasInheritedFinalDataClassMember(
               ownerSymbol: ownerSymbol,
               name: equalsName,
               parameterTypes: [nullableAnyType],
               returnType: boolType,
               symbols: symbols,
               types: types
           ) {
            return
        }
        let equalsFQName = ownerFQName + [equalsName]
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )
        guard !hasUserDeclaredFunction(
            fqName: equalsFQName,
            receiverType: ownerType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            symbols: symbols,
            types: types
        ) else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: equalsName,
            fqName: equalsFQName,
            declSite: nil,
            visibility: .public,
            // Synthesized equals replaces Any.equals in the vtable, including
            // when the class has an explicit superclass implementation.
            flags: [.synthetic, .overrideMember]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        let otherParamName = interner.intern("other")
        let otherParamSymbol = symbols.define(
            kind: .valueParameter,
            name: otherParamName,
            fqName: equalsFQName + [otherParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [nullableAnyType],
                returnType: boolType,
                isSuspend: false,
                valueParameterSymbols: [otherParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: funcSymbol
        )
        scope?.insert(funcSymbol)
    }

    func collectSyntheticHashCode(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        requireDataTypeFlag: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope?,
        interner: StringInterner
    ) {
        if requireDataTypeFlag {
            guard symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true else {
                return
            }
        }
        let hashCodeName = interner.intern("hashCode")
        let intType = types.make(.primitive(.int, .nonNull))
        if symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true,
           hasInheritedFinalDataClassMember(
               ownerSymbol: ownerSymbol,
               name: hashCodeName,
               parameterTypes: [],
               returnType: intType,
               symbols: symbols,
               types: types
           ) {
            return
        }
        let hashCodeFQName = ownerFQName + [hashCodeName]
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )
        guard !hasUserDeclaredFunction(
            fqName: hashCodeFQName,
            receiverType: ownerType,
            parameterTypes: [],
            returnType: intType,
            symbols: symbols,
            types: types
        ) else {
            return
        }
        let funcSymbol = symbols.define(
            kind: .function,
            name: hashCodeName,
            fqName: hashCodeFQName,
            declSite: nil,
            visibility: .public,
            flags: symbols.symbol(ownerSymbol)?.kind == .annotationClass
                ? [.synthetic, .overrideMember] : [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: intType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: funcSymbol
        )
        scope?.insert(funcSymbol)
    }

    private func dataClassPrimaryConstructorParameterTypes(
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [TypeID]? {
        let constructorFQName = ownerFQName + [interner.intern("<init>")]
        guard let constructor = symbols.lookupAll(fqName: constructorFQName).first(where: { id in
            guard let symbol = symbols.symbol(id) else { return false }
            return symbol.kind == .constructor
                && symbols.parentSymbol(for: id) == ownerSymbol
                && symbol.declSite == classDecl.range
        }), let signature = symbols.functionSignature(for: constructor),
            signature.parameterTypes.count == classDecl.primaryConstructorParams.count
        else {
            return nil
        }
        // Reuse the constructor's binding, including block-local classifiers
        // that cannot be reconstructed from the class FQName and file imports.
        return signature.parameterTypes
    }

    /// DATA-002 / STDLIB-090: Registers synthetic `componentN()` functions for each
    /// primary constructor parameter of a data class.
    /// `component1()` returns the first constructor property, `component2()` the second, etc.
    func collectSyntheticDataClassComponentN(
        classDecl: ClassDecl,
        ast: ASTModule,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        localTypeParameters: [InternedString: SymbolID] = [:],
        ownerIsLocal: Bool = false
    ) {
        let file = ast.file(for: classDecl.range.start.file)
        let parameterTypes = dataClassPrimaryConstructorParameterTypes(
            classDecl: classDecl, ownerSymbol: ownerSymbol, ownerFQName: ownerFQName,
            symbols: symbols, interner: interner
        )
        for (index, param) in classDecl.primaryConstructorParams.enumerated() {
            let componentName = interner.intern("component\(index + 1)")
            let componentFQName = ownerFQName + [componentName]

            let hasUserDeclared = symbols.lookupAll(fqName: componentFQName).contains { id in
                guard let sym = symbols.symbol(id),
                      sym.kind == .function,
                      !sym.flags.contains(.synthetic)
                else { return false }
                return true
            }
            guard !hasUserDeclared else { continue }

            let returnType = parameterTypes?[index] ?? resolveTypeRef(
                param.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                relativeOwnerFQName: ownerFQName,
                currentPackageFQName: file?.packageFQName,
                imports: file?.imports ?? [],
                diagnostics: diagnostics,
                usageRange: classDecl.range
            ) ?? types.anyType
            let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
                ownerSymbol: ownerSymbol,
                types: types
            )

            let funcSymbol = symbols.define(
                kind: .function,
                name: componentName,
                fqName: componentFQName,
                declSite: classDecl.range,
                // Local class symbols are private to model their lexical scope;
                // their generated component functions remain public in that scope.
                visibility: ownerIsLocal
                    ? .public
                    : restrictedVisibility(symbols.symbol(ownerSymbol)?.visibility ?? .public, .public),
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(ownerSymbol, for: funcSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: [],
                    returnType: returnType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: classTypeParameterSymbols,
                    classTypeParameterCount: classTypeParameterSymbols.count
                ),
                for: funcSymbol
            )
            scope.insert(funcSymbol)
        }
    }

    func collectSyntheticDataClassCopy(
        classDecl: ClassDecl,
        ast: ASTModule,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) {
        let copyName = interner.intern("copy")
        let copyFQName = ownerFQName + [copyName]
        guard symbols.lookupAll(fqName: copyFQName).isEmpty else {
            return
        }

        let ownerSemanticSymbol = symbols.symbol(ownerSymbol)
        let copyVisibility = dataClassCopyVisibility(
            for: classDecl,
            classSymbol: ownerSemanticSymbol
        )
        let copySymbol = symbols.define(
            kind: .function,
            name: copyName,
            fqName: copyFQName,
            declSite: classDecl.range,
            visibility: copyVisibility,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: copySymbol)

        let localNamespaceFQName = copyFQName + [interner.intern("$\(copySymbol.rawValue)")]
        // Synthetic signatures use the same lexical and import scope as the
        // primary constructor, rather than global short-name lookup.
        let file = ast.file(for: classDecl.range.start.file)
        let parameterTypes = dataClassPrimaryConstructorParameterTypes(
            classDecl: classDecl, ownerSymbol: ownerSymbol, ownerFQName: ownerFQName,
            symbols: symbols, interner: interner
        )
        let copyParams = collectValueParameters(
            classDecl.primaryConstructorParams,
            localNamespaceFQName: localNamespaceFQName,
            declSite: classDecl.range,
            ast: ast,
            symbols: symbols,
            types: types,
            interner: interner,
            localTypeParameters: localTypeParameters,
            relativeOwnerFQName: ownerFQName,
            currentPackageFQName: file?.packageFQName,
            imports: file?.imports ?? [],
            diagnostics: diagnostics,
            resolvedParameterTypes: parameterTypes,
            fallbackType: types.anyType
        )
        let classTypeParameterSymbols = syntheticDataClassMemberTypeParameterSymbols(
            ownerSymbol: ownerSymbol,
            types: types
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: copyParams.paramTypes,
                returnType: ownerType,
                valueParameterSymbols: copyParams.paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: true, count: copyParams.paramSymbols.count),
                valueParameterIsVararg: copyParams.paramIsVararg,
                valueParameterAllowsNonLocalReturn: copyParams.paramAllowsNonLocalReturn,
                typeParameterSymbols: classTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterSymbols.count
            ),
            for: copySymbol
        )
        scope.insert(copySymbol)
    }

    func collectSyntheticDataClassComponentsAndCopy(
        classDecl: ClassDecl,
        ast: ASTModule,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        localTypeParameters: [InternedString: SymbolID] = [:],
        ownerIsLocal: Bool = false
    ) {
        collectSyntheticDataClassComponentN(
            classDecl: classDecl,
            ast: ast,
            ownerSymbol: ownerSymbol,
            ownerFQName: ownerFQName,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            scope: scope,
            interner: interner,
            diagnostics: diagnostics,
            localTypeParameters: localTypeParameters,
            ownerIsLocal: ownerIsLocal
        )
        collectSyntheticDataClassCopy(
            classDecl: classDecl,
            ast: ast,
            ownerSymbol: ownerSymbol,
            ownerFQName: ownerFQName,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            scope: scope,
            interner: interner,
            diagnostics: diagnostics,
            localTypeParameters: localTypeParameters
        )
    }

    func collectValueParameters(
        _ valueParams: [ValueParamDecl],
        localNamespaceFQName: [InternedString],
        declSite: SourceRange?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        sourceManager: SourceManager? = nil,
        localTypeParameters: [InternedString: SymbolID] = [:],
        relativeOwnerFQName: [InternedString]? = nil,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = [],
        diagnostics: DiagnosticEngine? = nil,
        resolvedParameterTypes: [TypeID]? = nil,
        fallbackType: TypeID
    ) -> (
        paramTypes: [TypeID],
        paramSymbols: [SymbolID],
        paramHasDefaultValues: [Bool],
        paramIsVararg: [Bool],
        paramAllowsNonLocalReturn: [Bool],
        paramUnsafeVarianceTypeParameterSymbols: [Set<SymbolID>]
    ) {
        var paramTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        var paramHasDefaultValues: [Bool] = []
        var paramIsVararg: [Bool] = []
        var paramAllowsNonLocalReturn: [Bool] = []
        var paramUnsafeVarianceTypeParameterSymbols: [Set<SymbolID>] = []
        for (index, valueParam) in valueParams.enumerated() {
            let paramFQName = localNamespaceFQName + [valueParam.name]
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: valueParam.name,
                fqName: paramFQName,
                declSite: declSite,
                visibility: .private,
                flags: []
            )
            let preResolvedType = resolvedParameterTypes.flatMap { index < $0.count ? $0[index] : nil }
            let resolvedType = preResolvedType ?? resolveTypeRef(
                valueParam.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                sourceManager: sourceManager,
                localTypeParameters: localTypeParameters,
                relativeOwnerFQName: relativeOwnerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                diagnostics: diagnostics,
                usageRange: declSite
            ) ?? fallbackType
            paramTypes.append(resolvedType)
            paramSymbols.append(paramSymbol)
            paramUnsafeVarianceTypeParameterSymbols.append(unsafeVarianceTypeParameterSymbols(
                in: valueParam.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                sourceManager: sourceManager,
                localTypeParameters: localTypeParameters,
                relativeOwnerFQName: relativeOwnerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                diagnostics: diagnostics,
                usageRange: declSite
            ))
            paramHasDefaultValues.append(valueParam.hasDefaultValue)
            paramIsVararg.append(valueParam.isVararg)
            paramAllowsNonLocalReturn.append(!valueParam.isCrossinline && !valueParam.isNoinline)
        }
        return (
            paramTypes,
            paramSymbols,
            paramHasDefaultValues,
            paramIsVararg,
            paramAllowsNonLocalReturn,
            paramUnsafeVarianceTypeParameterSymbols
        )
    }

    func collectFunctionTypeParameters(
        _ typeParams: [TypeParamDecl],
        localNamespaceFQName: [InternedString],
        declSite: SourceRange?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        sourceManager: SourceManager? = nil,
        isInline: Bool,
        isProperty: Bool = false,
        diagnostics: DiagnosticEngine,
        enclosingTypeParameters: [InternedString: SymbolID] = [:],
        relativeOwnerFQName: [InternedString]? = nil,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = []
    ) -> (typeParameterSymbols: [SymbolID], localTypeParameters: [InternedString: SymbolID], reifiedIndices: Set<Int>) {
        var typeParameterSymbols: [SymbolID] = []
        var localTypeParameters: [InternedString: SymbolID] = [:]
        var reifiedIndices: Set<Int> = []
        for (index, typeParam) in typeParams.enumerated() {
            if !isProperty, typeParam.variance != .invariant {
                diagnostics.error(
                    "KSWIFTK-SEMA-0443",
                    "Variance annotations are only allowed for type parameters of classes and interfaces.",
                    range: declSite
                )
            }
            let typeParamFQName = localNamespaceFQName + [typeParam.name]
            let typeParamFlags: SymbolFlags = typeParam.isReified ? [.reifiedTypeParameter] : []
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParam.name,
                fqName: typeParamFQName,
                declSite: declSite,
                visibility: .private,
                flags: typeParamFlags
            )
            typeParameterSymbols.append(typeParamSymbol)
            // Preserve the resolved annotation identity for inference and metadata.
            // All source nominal headers are predeclared before function headers.
            let annotationFileID = declSite?.start.file
            registerAnnotations(
                typeParam.annotations,
                symbol: typeParamSymbol,
                declRange: declSite,
                sourceFileID: annotationFileID,
                sourceFile: annotationFileID.flatMap { ast.file(for: $0) },
                sourceManager: nil,
                interner: interner,
                symbols: symbols,
                diagnostics: diagnostics
            )
            localTypeParameters[typeParam.name] = typeParamSymbol
            if typeParam.isReified {
                reifiedIndices.insert(index)
            }
        }
        let boundTypeParameters = enclosingTypeParameters.merging(localTypeParameters) { _, local in local }
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
                    localTypeParameters: boundTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
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
        if !reifiedIndices.isEmpty, !isInline {
            diagnostics.error(
                "KSWIFTK-SEMA-0020",
                "Only type parameters of inline functions can be reified",
                range: declSite
            )
        }
        return (typeParameterSymbols, localTypeParameters, reifiedIndices)
    }

    func registerTypeAliasTypeParameters(
        _ typeParams: [TypeParamDecl],
        aliasSymbol: SymbolID,
        parentFQName: [InternedString],
        declSite: SourceRange?,
        symbols: SymbolTable,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) -> [InternedString: SymbolID] {
        var localTypeParameters: [InternedString: SymbolID] = [:]
        var typeParameterSymbols: [SymbolID] = []
        let localNamespaceFQName = parentFQName + [interner.intern("$\(aliasSymbol.rawValue)")]
        for typeParam in typeParams {
            let typeParamFQName = localNamespaceFQName + [typeParam.name]
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParam.name,
                fqName: typeParamFQName,
                declSite: declSite,
                visibility: .private,
                flags: typeParam.isReified ? [.reifiedTypeParameter] : []
            )
            if typeParam.isReified {
                diagnostics.error(
                    "KSWIFTK-SEMA-0020",
                    "Applying reified modifier to a type parameter of a type alias makes no sense",
                    range: declSite
                )
            }
            typeParameterSymbols.append(typeParamSymbol)
            localTypeParameters[typeParam.name] = typeParamSymbol
        }
        if !typeParameterSymbols.isEmpty {
            symbols.setTypeAliasTypeParameters(typeParameterSymbols, for: aliasSymbol)
        }
        return localTypeParameters
    }

    /// Register synthetic stdlib symbols for property delegate functions so that
    /// sema can resolve `lazy { }`, `Delegates.observable(...)`, and `Delegates.vetoable(...)`.
    /// Also registers `kotlin.properties.Lazy<T>` and `kotlin.properties.ReadWriteProperty<T, V>`
    /// as interface stubs so that return types are structurally correct.
    /// These are minimal stubs: just enough for name resolution and type checking to succeed.
    func registerSyntheticDelegateStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty
    ) {
        let skipStats = SyntheticStubSkipStatsCollector()
        let firstGeneratedSymbol = symbols.count
        defer {
            BundledSyntheticStubRegistration.clear()
        }
        BundledSyntheticStubRegistration.bundledIndex = bundledIndex
        BundledSyntheticStubRegistration.types = types
        let kotlinPkg = ensureKotlinPackage(symbols: symbols, interner: interner)
        let kotlinPropertiesPkg = ensureKotlinPropertiesPackage(symbols: symbols, interner: interner)
        let registryContext = SyntheticDelegateStubRegistryContext(
            kotlinPkg: kotlinPkg,
            kotlinPropertiesPkg: kotlinPropertiesPkg,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        registerSyntheticDelegateRegistryStubs(
            symbols: symbols,
            types: types,
            interner: interner,
            context: registryContext
        )
        if firstGeneratedSymbol < symbols.count {
            for index in firstGeneratedSymbol ..< symbols.count where index <= Int(Int32.max) {
                symbols.insertFlags(
                    .precomputedStdlibSynthetic,
                    for: SymbolID(rawValue: Int32(index))
                )
            }
        }
        skipStats.logIfEnabled()
    }

    /// Restores the TypeSystem anchors that the bootstrap registry normally
    /// installs after importing a stdlib artifact that already serializes its
    /// synthetic declarations and their metadata.
    func restorePrecomputedStdlibSyntheticTypeSymbols(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        defer { BundledSyntheticStubRegistration.clear() }

        func importedNominal(_ path: [String]) -> SymbolID? {
            let fqName = path.map { interner.intern($0) }
            guard let symbol = symbols.lookupAll(fqName: fqName).first(where: { id in
                guard let candidate = symbols.symbol(id) else { return false }
                return symbols.isImportedStdlibSymbol(id)
                    && Self.isNominalKind(candidate.kind)
            }) else {
                return nil
            }
            symbols.ensureLazyImportedMetadataLoaded(for: symbol)
            return symbol
        }

        guard let any = importedNominal(["kotlin", "Any"]),
              let annotation = importedNominal(["kotlin", "Annotation"]),
              let comparable = importedNominal(["kotlin", "Comparable"]),
              let charSequence = importedNominal(["kotlin", "CharSequence"]),
              let string = importedNominal(["kotlin", "String"]),
              let char = importedNominal(["kotlin", "Char"]),
              let kCallable = importedNominal(["kotlin", "reflect", "KCallable"]),
              let kFunction = importedNominal(["kotlin", "reflect", "KFunction"]),
              let kClass = importedNominal(["kotlin", "reflect", "KClass"])
        else {
            return false
        }

        types.anyClassSymbol = any
        types.annotationInterfaceSymbol = annotation
        types.comparableInterfaceSymbol = comparable
        types.charSequenceInterfaceSymbol = charSequence
        types.stringClassSymbol = string
        types.charClassSymbol = char
        types.kCallableInterfaceSymbol = kCallable
        types.kFunctionInterfaceSymbol = kFunction
        types.kClassInterfaceSymbol = kClass

        for arity in 0 ... 22 {
            guard let function = importedNominal(["kotlin", "Function", "Function\(arity)"]),
                  let suspendFunction = importedNominal(["kotlin", "coroutines", "SuspendFunction\(arity)"])
            else {
                return false
            }
            types.functionNInterfaceSymbols[arity] = function
            types.suspendFunctionNInterfaceSymbols[arity] = suspendFunction
        }
        return true
    }

    private static func isNominalKind(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass: true
        default: false
        }
    }

    /// Register the synthetic `kotlin.Any` and `kotlin.Annotation` built-in stubs.
    ///
    /// `Any` is needed as the root nominal type for default superclass binding, and
    /// `Annotation` is the built-in supertype used by annotation classes and the
    /// `Annotation` type name resolver.
    func registerSyntheticAnyStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]? = nil
    ) {
        let kotlinPkg = kotlinPkg ?? ensureKotlinPackage(symbols: symbols, interner: interner)

        let anySymbol = ensureClassSymbol(
            named: "Any",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        types.anyClassSymbol = anySymbol

        let annotationSymbol = ensureInterfaceSymbol(
            named: "Annotation",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        types.annotationInterfaceSymbol = annotationSymbol

        symbols.setDirectSupertypes([anySymbol], for: annotationSymbol)
        types.setNominalDirectSupertypes([anySymbol], for: annotationSymbol)

        // Register toString(), hashCode(), equals() as members of kotlin.Any so that
        // member calls on user-defined class instances resolve instead of producing <error>.
        guard let anyInfo = symbols.symbol(anySymbol) else { return }
        let anyClassType = types.make(.classType(ClassType(
            classSymbol: anySymbol, args: [], nullability: .nonNull)))

        // Kotlin/Native exposes Any's implicit public constructor in metadata,
        // although the actual class declaration is compiler-provided rather
        // than bundled Kotlin source. The KIR constructor path performs the
        // object allocation; no constructor body is emitted for this symbol.
        let anyConstructorName = interner.intern("<init>")
        let anyConstructorFQName = anyInfo.fqName + [anyConstructorName]
        if symbols.lookupAll(fqName: anyConstructorFQName).isEmpty {
            let constructorSymbol = symbols.define(
                kind: .constructor,
                name: anyConstructorName,
                fqName: anyConstructorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic])
            symbols.setParentSymbol(anySymbol, for: constructorSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: anyClassType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: []),
                for: constructorSymbol)
        }

        // Any has only the two-word object header and is the root of the
        // nominal allocation hierarchy. Keep its layout empty so the existing
        // Any member fallback remains responsible for toString/hashCode/equals
        // dispatch while constructors still receive a stable nominal type ID.
        if symbols.nominalLayout(for: anySymbol) == nil {
            symbols.setNominalLayout(
                NominalLayout(
                    objectHeaderWords: 2,
                    instanceFieldCount: 0,
                    instanceSizeWords: 2,
                    vtableSlots: [:],
                    itableSlots: [:],
                    superClass: nil),
                for: anySymbol)
        }

        let stringType = types.stringType
        let intType = types.intType
        let booleanType = types.booleanType
        let nullableAnyType = types.nullableAnyType

        let anyMemberSpecs: [(name: String, link: String, params: [TypeID], ret: TypeID)] = [
            ("toString", "kk_any_member_to_string", [], stringType),
            ("hashCode", "kk_any_member_hashCode", [], intType),
            ("equals",   "kk_any_member_equals",   [nullableAnyType], booleanType),
        ]
        for spec in anyMemberSpecs {
            let memberName = interner.intern(spec.name)
            let memberFQName = anyInfo.fqName + [memberName]
            if !symbols.lookupAll(fqName: memberFQName).isEmpty { continue }

            var paramSymbols: [SymbolID] = []
            for (i, paramType) in spec.params.enumerated() {
                let pName = interner.intern("p\(i)")
                let pSym = symbols.define(
                    kind: .valueParameter, name: pName,
                    fqName: memberFQName + [pName],
                    declSite: nil, visibility: .private, flags: [.synthetic])
                symbols.setPropertyType(paramType, for: pSym)
                paramSymbols.append(pSym)
            }

            let memberSymbol = symbols.define(
                kind: .function, name: memberName,
                fqName: memberFQName,
                declSite: nil, visibility: .public, flags: [.synthetic, .openType])
            symbols.setParentSymbol(anySymbol, for: memberSymbol)
            symbols.setExternalLinkName(spec.link, for: memberSymbol)
            for pSym in paramSymbols {
                symbols.setParentSymbol(memberSymbol, for: pSym)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: anyClassType,
                    parameterTypes: spec.params,
                    returnType: spec.ret,
                    isSuspend: false,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
                    valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)),
                for: memberSymbol)
        }
    }

    /// KSP-719: The bundled `kotlin/Annotation.kt` source declares
    /// `public interface Annotation {}` with no explicit supertype. That causes
    /// `bindInheritanceEdges` to overwrite the synthetic `Annotation` symbol's
    /// direct supertype list with an empty array, losing the `kotlin.Any`
    /// supertype that `registerSyntheticAnyStub` had installed. Restore it so
    /// `Any` member dispatch and nominal-subtype traversal stay intact.
    func patchBundledAnnotationSupertype(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let annotationSymbol = types.annotationInterfaceSymbol else { return }
        let anyFQName = [interner.intern("kotlin"), interner.intern("Any")]
        guard let anySymbol = symbols.lookup(fqName: anyFQName) else { return }

        let symbolSups = symbols.directSupertypes(for: annotationSymbol)
        if !symbolSups.contains(anySymbol) {
            let newSups = Array(Set(symbolSups + [anySymbol])).sorted(by: { $0.rawValue < $1.rawValue })
            symbols.setDirectSupertypes(newSups, for: annotationSymbol)
        }

        let typeSups = types.directNominalSupertypes(for: annotationSymbol)
        if !typeSups.contains(anySymbol) {
            types.setNominalDirectSupertypes(typeSups + [anySymbol], for: annotationSymbol)
        }
    }

    /// KSP-707: The bundled `kotlin/Preconditions.kt` source declares `require`/
    /// `check`/`assert` without a `contract { ... }` block, so their smart-cast
    /// narrowing (e.g. `require(x != null); x.length`) is not derived from the
    /// AST. `requireNotNull`/`checkNotNull` do declare a contract in source, but
    /// contract effects are not serialized into `.kklib` metadata, so symbols
    /// imported from a precompiled artifact need it re-attached too. Attach the
    /// `ContractNonNullEffect` directly to the source-backed or imported symbols
    /// once header collection has registered them, so `applyContractEffects`
    /// can branch on the passed-in condition or narrow the nullable argument.
    func patchSourceBackedPreconditionContractEffects(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let lazyMessageType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let preconditionFunctions: [(name: String, parameterTypes: [TypeID])] = [
            ("require", [types.booleanType]),
            ("require", [types.booleanType, lazyMessageType]),
            ("check", [types.booleanType]),
            ("check", [types.booleanType, lazyMessageType]),
            ("assert", [types.booleanType]),
            ("assert", [types.booleanType, lazyMessageType]),
        ]

        for entry in preconditionFunctions {
            let functionName = interner.intern(entry.name)
            let functionFQName = kotlinPkg + [functionName]
            // KUU-2673: attach the effect once the imported candidates
            // materialize instead of decoding their signatures eagerly.
            let patchContractEffect = {
                guard let symbol = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
                    guard let symbol = symbols.symbol(symbolID),
                          symbol.kind == .function,
                          // Symbols loaded from a precompiled stdlib library artifact
                          // (`--stdlib-library`, used by Scripts/diff_kotlinc.sh) carry
                          // both `.importedLibrary` and `.synthetic`, so only exclude
                          // synthetic placeholders that are NOT backed by an import.
                          !symbol.flags.contains(.synthetic) || symbol.flags.contains(.importedLibrary),
                          let signature = symbols.functionSignature(for: symbolID)
                    else {
                        return false
                    }
                    return signature.receiverType == nil
                        && signature.parameterTypes == entry.parameterTypes
                        && signature.returnType == types.unitType
                }) else {
                    return
                }
                guard let signature = symbols.functionSignature(for: symbol),
                      !signature.valueParameterSymbols.isEmpty
                else {
                    return
                }
                symbols.setContractNonNullEffect(
                    ContractNonNullEffect(
                        parameterSymbol: signature.valueParameterSymbols[0],
                        appliesOnAnyReturn: true
                    ),
                    for: symbol
                )
            }
            if !symbols.deferWorkUntilImportedMemberMaterializes(at: functionFQName, work: patchContractEffect) {
                patchContractEffect()
            }
        }

        // KUU-1091: `requireNotNull`/`checkNotNull` declare
        // `contract { returns() implies (value != null) }` in the bundled source,
        // but `ContractNonNullEffect` is not serialized into `.kklib` metadata,
        // so symbols imported from a precompiled stdlib artifact still need the
        // effect attached here. Their `value` parameter is a generic `T?`, so
        // they are matched by name and arity rather than concrete parameter
        // types: one `value` parameter, optionally followed by the
        // `lazyMessage: () -> Any` parameter.
        let notNullFunctionNames = ["requireNotNull", "checkNotNull"]
        for name in notNullFunctionNames {
            let functionFQName = kotlinPkg + [interner.intern(name)]
            let patchContractEffects = {
                for symbol in symbols.lookupAll(fqName: functionFQName) {
                    guard let symbolInfo = symbols.symbol(symbol),
                          symbolInfo.kind == .function,
                          !symbolInfo.flags.contains(.synthetic) || symbolInfo.flags.contains(.importedLibrary),
                          let signature = symbols.functionSignature(for: symbol),
                          signature.receiverType == nil,
                          !signature.valueParameterSymbols.isEmpty
                    else {
                        continue
                    }
                    let arityMatches = switch signature.parameterTypes.count {
                    case 1:
                        true
                    case 2:
                        signature.parameterTypes[1] == lazyMessageType
                    default:
                        false
                    }
                    // The first parameter must be the nullable `value` — a Boolean
                    // first parameter would route to condition narrowing instead.
                    guard arityMatches,
                          signature.parameterTypes[0] != types.booleanType else {
                        continue
                    }
                    symbols.setContractNonNullEffect(
                        ContractNonNullEffect(
                            parameterSymbol: signature.valueParameterSymbols[0],
                            appliesOnAnyReturn: true
                        ),
                        for: symbol
                    )
                }
            }
            if !symbols.deferWorkUntilImportedMemberMaterializes(at: functionFQName, work: patchContractEffects) {
                patchContractEffects()
            }
        }
    }

    func resolveNumberClassSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]? = nil
    ) {
        let kotlinPkg = kotlinPkg ?? ensureKotlinPackage(symbols: symbols, interner: interner)
        let numberName = interner.intern("Number")
        let numberFQName = kotlinPkg + [numberName]

        if let numberSymbol = symbols.lookup(fqName: numberFQName) {
            types.numberClassSymbol = numberSymbol
            return
        }

        guard let anySymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("Any")]) else { return }

        let numberSymbol = ensureClassSymbol(
            named: "Number",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.synthetic, .abstractType], for: numberSymbol)
        symbols.setDirectSupertypes([anySymbol], for: numberSymbol)
        types.setNominalDirectSupertypes([anySymbol], for: numberSymbol)
        types.numberClassSymbol = numberSymbol
    }

    /// Resolve the source-backed or imported kotlin.Unit object while
    /// preserving the compiler's builtin Unit value representation.
    func resolveUnitClassSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]? = nil
    ) {
        let kotlinPkg = kotlinPkg ?? ensureKotlinPackage(symbols: symbols, interner: interner)
        let unitName = BuiltinTypeNames(interner: interner).unit
        let unitFQName = kotlinPkg + [unitName]
        if let unitSymbol = symbols.lookupAll(fqName: unitFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .object
        }) {
            types.unitClassSymbol = unitSymbol
        }
    }

    func ensureInterfaceSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        visibility: Visibility = .public
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .interface, name: internedName, fqName: fqName,
            declSite: nil, visibility: visibility, flags: [.synthetic]
        )
    }

    func ensureClassSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        // A factory function may share the class FQName (for example,
        // `kotlin.concurrent.AtomicIntArray(Int)` or a Kotlin `class Foo` +
        // `fun Foo(...)` pair). Prefer an existing nominal class over the
        // first callable that shadows it.
        if let existing = symbols.lookupAll(fqName: fqName).first(where: { id in
            symbols.symbol(id)?.kind == .class
        }) {
            return existing
        }
        return symbols.define(
            kind: .class,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    func ensureEnumClassSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .enumClass,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    func ensureAnnotationClassSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .annotationClass,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func ensureKotlinPackage(symbols: SymbolTable, interner: StringInterner) -> [InternedString] {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("kotlin"), fqName: kotlinPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinPkg
    }

    private func ensureKotlinPropertiesPackage(symbols: SymbolTable, interner: StringInterner) -> [InternedString] {
        let kotlinPropertiesPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("properties")]
        if symbols.lookup(fqName: kotlinPropertiesPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("properties"), fqName: kotlinPropertiesPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinPropertiesPkg
    }

    func ensurePackage(
        path: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for component in path {
            let interned = interner.intern(component)
            fqName.append(interned)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: interned,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }
}
