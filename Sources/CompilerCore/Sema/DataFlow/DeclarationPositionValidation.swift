
extension DataFlowSemaPhase {
    func validateDeclarationPositions(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine?,
        interner: StringInterner,
        sourceManager: SourceManager,
        fullValueClassesEnabled: Bool = false
    ) {
        let symbolToDecl = Dictionary(
            bindings.declSymbols.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        for file in ast.sortedFiles {
            if sourceManager.origin(of: file.fileID)?.isBundledStdlib == true {
                continue
            }
            var jvmInlineAnnotationNames: Set<String> = ["JvmInline", "kotlin.jvm.JvmInline"]
            for importDecl in file.imports where !importDecl.isWildcard
                && importDecl.path.map(interner.resolve).joined(separator: ".") == "kotlin.jvm.JvmInline"
            {
                jvmInlineAnnotationNames.insert(interner.resolve(importDecl.alias ?? importDecl.path.last!))
            }
            let validator = DeclarationPositionValidator(
                astArena: ast.arena,
                interner: interner,
                diagnostics: diagnostics,
                fullValueClassesEnabled: fullValueClassesEnabled,
                jvmInlineAnnotationNames: jvmInlineAnnotationNames,
                inheritedPropertyVisibility: { declID in
                    self.inheritedPropertyVisibility(
                        forPropertyDecl: declID,
                        ast: ast, symbols: symbols, bindings: bindings,
                        symbolToDecl: symbolToDecl
                    )
                }
            )
            for declID in file.topLevelDecls {
                validator.validate(declID: declID, site: .file)
                validateSemanticDeclRules(
                    declID: declID,
                    ownerPath: file.packageFQName,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
        validateOrphanActualDeclarations(
            symbols: symbols,
            diagnostics: diagnostics,
            sourceManager: sourceManager
        )
    }

    /// KUU-4119: resolves the visibility an `override` property without its own
    /// visibility modifier inherits from the nearest overridden member.
    /// Returns nil when no overridden property can be found — the accessor
    /// check then treats the effective visibility as unknown rather than
    /// wrongly assuming `public`.
    private func inheritedPropertyVisibility(
        forPropertyDecl declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        symbolToDecl: [SymbolID: DeclID]
    ) -> Visibility? {
        guard let symbolID = bindings.declSymbols[declID],
              let symbol = symbols.symbol(symbolID),
              symbol.kind == .property,
              let ownerID = symbols.parentSymbol(for: symbolID),
              let baseID = nearestOverriddenProperty(named: symbol.name, owner: ownerID, symbols: symbols)
        else {
            return nil
        }
        return effectivePropertyVisibility(
            of: baseID,
            visited: [symbolID],
            ast: ast, symbols: symbols, symbolToDecl: symbolToDecl
        )
    }

    /// The effective visibility of a property symbol: a source-declared
    /// `override` without its own visibility modifier recurses into the member
    /// it overrides; anything else carries its declared visibility directly.
    private func effectivePropertyVisibility(
        of symbolID: SymbolID,
        visited: Set<SymbolID>,
        ast: ASTModule,
        symbols: SymbolTable,
        symbolToDecl: [SymbolID: DeclID]
    ) -> Visibility? {
        guard let symbol = symbols.symbol(symbolID) else {
            return nil
        }
        guard let declID = symbolToDecl[symbolID],
              let decl = ast.arena.decl(declID),
              case let .propertyDecl(propertyDecl) = decl
        else {
            // Imported or synthetic members already carry their effective
            // visibility on the symbol record.
            return symbol.visibility
        }
        guard propertyDecl.modifiers.contains(.override),
              propertyDecl.modifiers.isDisjoint(with: [.private, .internal, .protected, .public])
        else {
            return Visibility(modifiers: propertyDecl.modifiers)
        }
        guard let ownerID = symbols.parentSymbol(for: symbolID),
              let baseID = nearestOverriddenProperty(named: propertyDecl.name, owner: ownerID, symbols: symbols),
              !visited.contains(baseID)
        else {
            return nil
        }
        return effectivePropertyVisibility(
            of: baseID,
            visited: visited.union([baseID]),
            ast: ast, symbols: symbols, symbolToDecl: symbolToDecl
        )
    }

    /// Walks `ownerID`'s supertypes in declaration order for the nearest
    /// property member named `name`, mirroring the branch pruning of
    /// `nearestOverriddenFunctionCandidates`: a supertype that declares the
    /// member supplies it and shallower ancestors are never reached.
    /// Properties cannot overload, so a non-private name match is always the
    /// overridden member.
    private func nearestOverriddenProperty(
        named name: InternedString,
        owner ownerID: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID? {
        var visited: Set<SymbolID> = [ownerID]
        var stack = Array(symbols.directSupertypes(for: ownerID).reversed())
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            guard symbols.symbol(current) != nil else { continue }
            if let match = symbols.declaredChildren(of: current).first(where: { childID in
                guard let child = symbols.symbol(childID) else { return false }
                return child.kind == .property && child.name == name && child.visibility != .private
            }) {
                return match
            }
            stack.append(contentsOf: symbols.directSupertypes(for: current).reversed())
        }
        return nil
    }

    private func validateSemanticDeclRules(
        declID: DeclID,
        ownerPath: [InternedString],
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine?,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        switch decl {
        case .classDecl(let classDecl):
            let declPath = ownerPath + [classDecl.name]
            if classDecl.modifiers.contains(.enumModifier) {
                validateEnumSupertypes(
                    classDecl, ownerPath: ownerPath, file: file,
                    ast: ast, symbols: symbols, types: types,
                    diagnostics: diagnostics, interner: interner
                )
            }
            if classDecl.modifiers.contains(.annotationClass) {
                validateAnnotationParameterTypes(
                    classDecl, ownerPath: ownerPath, file: file,
                    ast: ast, symbols: symbols, types: types,
                    diagnostics: diagnostics, interner: interner
                )
            }
            for member in classDecl.memberFunctions + classDecl.memberProperties
                + classDecl.nestedClasses + classDecl.nestedObjects
                + (classDecl.companionObject.map { [$0] } ?? [])
            {
                validateSemanticDeclRules(
                    declID: member, ownerPath: declPath, file: file,
                    ast: ast, symbols: symbols, types: types,
                    diagnostics: diagnostics, interner: interner
                )
            }
            for entry in classDecl.enumEntries {
                for member in entry.memberFunctions + entry.memberProperties {
                    validateSemanticDeclRules(
                        declID: member, ownerPath: declPath, file: file,
                        ast: ast, symbols: symbols, types: types,
                        diagnostics: diagnostics, interner: interner
                    )
                }
                for member in entry.nestedClasses {
                    validateSemanticDeclRules(
                        declID: member, ownerPath: declPath + [entry.name], file: file,
                        ast: ast, symbols: symbols, types: types,
                        diagnostics: diagnostics, interner: interner
                    )
                }
            }
        case .interfaceDecl(let interfaceDecl):
            let declPath = ownerPath + [interfaceDecl.name]
            validateInterfaceSupertypes(
                interfaceDecl, ownerPath: ownerPath, file: file,
                ast: ast, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner
            )
            for member in interfaceDecl.memberFunctions + interfaceDecl.memberProperties
                + interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                + (interfaceDecl.companionObject.map { [$0] } ?? [])
            {
                validateSemanticDeclRules(
                    declID: member, ownerPath: declPath, file: file,
                    ast: ast, symbols: symbols, types: types,
                    diagnostics: diagnostics, interner: interner
                )
            }
        case .objectDecl(let objectDecl):
            let declPath = ownerPath + [objectDecl.name]
            for member in objectDecl.memberFunctions + objectDecl.memberProperties
                + objectDecl.nestedClasses + objectDecl.nestedObjects
            {
                validateSemanticDeclRules(
                    declID: member, ownerPath: declPath, file: file,
                    ast: ast, symbols: symbols, types: types,
                    diagnostics: diagnostics, interner: interner
                )
            }
        case .funDecl, .propertyDecl, .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    private func validateEnumSupertypes(
        _ enumDecl: ClassDecl,
        ownerPath: [InternedString],
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine?,
        interner: StringInterner
    ) {
        for entry in enumDecl.superTypeEntries {
            guard let resolved = resolveTypeRef(
                entry.typeRef,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                relativeOwnerFQName: ownerPath,
                currentPackageFQName: file.packageFQName,
                imports: file.imports
            ),
                case .classType(let classType) = types.kind(of: resolved),
                let superSymbol = symbols.symbol(classType.classSymbol),
                superSymbol.kind == .class || superSymbol.kind == .enumClass
            else {
                continue
            }
            diagnostics?.error(
                "KSWIFTK-SEMA-0405",
                "enum classes cannot extend classes.",
                range: enumDecl.range
            )
        }
    }

    private func validateInterfaceSupertypes(
        _ interfaceDecl: InterfaceDecl,
        ownerPath: [InternedString],
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine?,
        interner: StringInterner
    ) {
        // kotlinc rejects `interface J : SomeClass` with
        // "an interface cannot extend a class". Interfaces may only list
        // interface supertypes. Annotation classes produce their own
        // diagnostic elsewhere, so only nominal class kinds are reported here.
        for superTypeRefID in interfaceDecl.superTypes {
            guard let resolved = resolveTypeRef(
                superTypeRefID,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                relativeOwnerFQName: ownerPath,
                currentPackageFQName: file.packageFQName,
                imports: file.imports
            ),
                case .classType(let classType) = types.kind(of: resolved),
                let superSymbol = symbols.symbol(classType.classSymbol)
            else {
                continue
            }
            switch superSymbol.kind {
            case .class, .enumClass, .object:
                diagnostics?.error(
                    "KSWIFTK-SEMA-0438",
                    "an interface cannot extend a class.",
                    range: interfaceDecl.range
                )
            default:
                continue
            }
        }
    }

    private func validateAnnotationParameterTypes(
        _ annotationDecl: ClassDecl,
        ownerPath: [InternedString],
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine?,
        interner: StringInterner
    ) {
        for param in annotationDecl.primaryConstructorParams {
            guard param.isProperty, !param.isMutableProperty,
                  let typeRefID = param.type,
                  let resolved = resolveTypeRef(
                      typeRefID,
                      ast: ast,
                      symbols: symbols,
                      types: types,
                      interner: interner,
                      relativeOwnerFQName: ownerPath,
                      currentPackageFQName: file.packageFQName,
                      imports: file.imports
                  ),
                  resolved != types.errorType
            else {
                continue
            }
            if !isLegalAnnotationMemberType(resolved, symbols: symbols, types: types, interner: interner) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0411",
                    "invalid type of annotation member.",
                    range: annotationDecl.range
                )
            }
        }
    }

    private func isLegalAnnotationMemberType(
        _ type: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> Bool {
        switch types.kind(of: type) {
        case .primitive(_, let nullability), .stringStruct(let nullability):
            return nullability == .nonNull
        case .kClassType:
            return true
        case .classType(let classType):
            guard classType.nullability == .nonNull,
                  let symbol = symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            let segments = symbol.fqName.map { interner.resolve($0) }
            // `KClass` is an interface in the bundled stdlib, so match it by
            // fqName regardless of the nominal kind.
            if symbol.fqName == KnownCompilerNames(interner: interner).kotlinReflectKClassFQName {
                return true
            }
            switch symbol.kind {
            case .enumClass, .annotationClass:
                return true
            case .class:
                guard segments.count == 2, segments[0] == "kotlin" else {
                    return false
                }
                if segments[1] == "Array",
                   let firstArg = classType.args.first,
                   case .invariant(let element) = firstArg
                {
                    return isLegalAnnotationMemberType(
                        element, symbols: symbols, types: types, interner: interner
                    )
                }
                return Self.primitiveArrayTypeNames.contains(segments[1])
            default:
                return false
            }
        default:
            return false
        }
    }

    private static let primitiveArrayTypeNames: Set<String> = [
        "IntArray", "LongArray", "ShortArray", "ByteArray",
        "BooleanArray", "CharArray", "FloatArray", "DoubleArray",
        "UIntArray", "ULongArray", "UShortArray", "UByteArray",
    ]

    /// JVM rejects `actual` declarations without a matching `expect`, and
    /// KSwiftK's expect/actual pairing check only inspects `expect` symbols.
    private func validateOrphanActualDeclarations(
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine?,
        sourceManager: SourceManager
    ) {
        for symbol in symbols.allSymbols() {
            guard symbol.flags.contains(.actualDeclaration),
                  let declSite = symbol.declSite,
                  sourceManager.origin(of: declSite.start.file)?.isBundledStdlib != true
            else {
                continue
            }
            // Members of an `actual` nominal pair implicitly through their
            // owner; explicit `actual` on them is legal Kotlin.
            if let parentID = symbols.parentSymbol(for: symbol.id),
               symbols.symbol(parentID)?.flags.contains(.actualDeclaration) == true
            {
                continue
            }
            let hasExpectCounterpart = symbols.lookupAll(fqName: symbol.fqName).contains { candidateID in
                symbols.symbol(candidateID)?.flags.contains(.expectDeclaration) == true
            }
            if !hasExpectCounterpart {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0410",
                    "actual declaration has no corresponding expected declaration.",
                    range: declSite
                )
            }
        }
    }
}
