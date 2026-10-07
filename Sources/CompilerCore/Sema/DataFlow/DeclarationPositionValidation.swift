
extension DataFlowSemaPhase {
    /// KUU-1407: reject declaration positions, modifier combinations, and
    /// declaration-kind constraints that Kotlin/JVM reports as compile
    /// errors but KSwiftK previously accepted silently.
    ///
    /// `DeclarationPositionValidator` covers the decl-level rules
    /// (modifiers, positions, member recursion). This pass additionally
    /// performs the checks that need type resolution or the symbol table:
    /// enum superclassing, annotation member types, and orphan `actual`s.
    func validateDeclarationPositions(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine?,
        interner: StringInterner,
        sourceManager: SourceManager
    ) {
        let validator = DeclarationPositionValidator(
            astArena: ast.arena,
            interner: interner,
            diagnostics: diagnostics
        )
        for file in ast.sortedFiles {
            if sourceManager.origin(of: file.fileID)?.isBundledStdlib == true {
                continue
            }
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

    /// Recursively applies the checks that require `SymbolTable`/`TypeSystem`.
    /// `ownerPath` is the fully qualified path of the lexical scope the
    /// declaration appears in (package plus enclosing declaration names).
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
            }
        case .interfaceDecl(let interfaceDecl):
            let declPath = ownerPath + [interfaceDecl.name]
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

    /// `enum class` may only implement interfaces — extending a class is an
    /// error on JVM ("enum classes cannot extend classes").
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

    /// Annotation class `val` parameters must have a permitted type:
    /// primitives, `String`, `KClass`, other annotations, enums, and arrays
    /// of those. Everything else is rejected on JVM.
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
            if segments == ["kotlin", "reflect", "KClass"] {
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

    /// `actual` declarations without a matching `expect` are silently
    /// accepted today; JVM rejects them (and KSwiftK's expect/actual
    /// pairing check only inspects `expect` symbols).
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
