import Foundation

extension DataFlowSemaPhase {
    func registerPrimaryConstructorPropertyAnnotations(
        for classDecl: ClassDecl,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        sourceManager: SourceManager?,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        lexicalEnclosingFQNames: [[InternedString]] = []
    ) {
        guard let file = ast.file(for: classDecl.range.start.file) else { return }
        let filesByID = Dictionary(uniqueKeysWithValues: ast.sortedFiles.map { ($0.fileID.rawValue, $0) })
        for parameter in classDecl.primaryConstructorParams where parameter.isProperty && !parameter.annotations.isEmpty {
            guard let propertyID = classDecl.memberProperties.first(where: {
                guard case let .propertyDecl(property) = ast.arena.decl($0) else { return false }
                return property.isSynthesizedPrimaryConstructorProperty && property.name == parameter.name
            }), let propertySymbol = bindings.declSymbols[propertyID],
                  bindings.primaryConstructorPropertyAnnotations[propertySymbol] == nil
            else { continue }
            let enclosingName = Array((symbols.symbol(propertySymbol)?.fqName ?? []).dropLast())
            var resolvedNames: [String: String] = [:]
            let annotations = parameter.annotations.filter { annotation in
                guard annotation.useSiteTarget == nil || annotation.useSiteTarget?.lowercased() == "property",
                      let annotationSymbol = resolveAnnotationSymbol(
                          named: annotation.name, in: file, symbols: symbols, interner: interner, types: types,
                          enclosingFQName: enclosingName, lexicalEnclosingFQNames: lexicalEnclosingFQNames
                      ), let targets = annotationTargets(
                          for: annotationSymbol, symbols: symbols, filesByID: filesByID, interner: interner
                      ), targets.contains("PROPERTY")
                else { return false }
                // Kotlin's default primary-constructor site prefers the value
                // parameter when both VALUE_PARAMETER and PROPERTY apply.
                if annotation.useSiteTarget == nil && targets.contains("VALUE_PARAMETER") { return false }
                if let usage = annotation.usageID, let symbol = symbols.symbol(annotationSymbol) {
                    resolvedNames[usage] = symbol.fqName.map(interner.resolve).joined(separator: ".")
                }
                return true
            }
            bindings.primaryConstructorPropertyAnnotations[propertySymbol] = annotations
            // The synthesized property's AST range is the whole class. Limit
            // @Suppress to this parameter's annotations/default initializer.
            let annotationTokens = parameter.annotations.flatMap { $0.constructionTokens ?? [] }
            let parameterRange = annotationTokens.first.flatMap { first in
                annotationTokens.last.map { last in
                    SourceRange(start: first.range.start,
                        end: parameter.defaultValue.flatMap { ast.arena.exprRange($0)?.end } ?? last.range.end)
                }
            }
            registerAnnotations(
                annotations, symbol: propertySymbol, declRange: parameterRange,
                sourceFileID: file.fileID, sourceFile: file, sourceManager: sourceManager,
                interner: interner, symbols: symbols, diagnostics: diagnostics
            )
            // Registration now runs after headers, so preserve the exact
            // classifier even for qualified relative names and nested aliases.
            let records = symbols.annotations(for: propertySymbol).map { annotation in
                MetadataAnnotationRecord(
                    annotationFQName: annotation.usageID.flatMap { resolvedNames[$0] } ?? annotation.annotationFQName,
                    arguments: annotation.arguments, useSiteTarget: annotation.useSiteTarget,
                    retention: annotation.retention, usageID: annotation.usageID,
                    factorySymbol: annotation.factorySymbol, factoryLinkName: annotation.factoryLinkName
                )
            }
            symbols.setAnnotations(records, for: propertySymbol)
        }
    }

    func validateAnnotationTargets(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let filesByID = Dictionary(uniqueKeysWithValues: ast.sortedFiles.map { ($0.fileID.rawValue, $0) })

        for file in ast.sortedFiles {
            validateFileAnnotationTargets(
                file: file,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )

            for declID in file.topLevelDecls {
                validateAnnotationTargets(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID,
                    isTopLevel: true
                )
            }
        }
    }

    private func validateFileAnnotationTargets(
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        guard !file.annotations.isEmpty else {
            return
        }

        for annotation in file.annotations {
            validateAnnotationTarget(
                annotation: annotation,
                site: .file,
                ownerRange: file.range,
                decl: nil,
                file: file,
                propertySymbol: nil,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        }
    }

    private func validateAnnotationTargets(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile],
        isTopLevel: Bool = false
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        let symbolID = bindings.declSymbols[declID]
        let ownerSymbol = symbolID.flatMap { symbols.symbol($0) }

        for annotation in decl.annotations {
            guard let site = annotationUsageSite(for: annotation, on: decl, ownerSymbol: ownerSymbol) else {
                continue
            }
            validateAnnotationTarget(
                annotation: annotation,
                site: site,
                ownerRange: decl.range,
                decl: decl,
                file: file,
                propertySymbol: ownerSymbol?.kind == .property ? symbolID : nil,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID,
                isTopLevel: isTopLevel
            )
        }

        validateTypeAnnotationTargets(
            in: decl,
            file: file,
            ast: ast,
            symbols: symbols,
            diagnostics: diagnostics,
            interner: interner,
            filesByID: filesByID
        )

        switch decl {
        case let .classDecl(classDecl):
            validateMemberAnnotationTargets(
                declIDs: classDecl.memberFunctions + classDecl.memberProperties + classDecl.nestedClasses + classDecl.nestedObjects,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
            if let companion = classDecl.companionObject {
                validateAnnotationTargets(
                    declID: companion,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
            // Validate primary constructor annotations
            for annotation in classDecl.primaryConstructorAnnotations {
                validateAnnotationTarget(
                    annotation: annotation,
                    site: .constructor,
                    ownerRange: decl.range,
                    decl: decl,
                    file: file,
                    propertySymbol: nil,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
            // Validate primary constructor value parameter annotations
            for param in classDecl.primaryConstructorParams {
                validateValueParamAnnotations(
                    param: param, ownerDecl: decl, file: file,
                    symbols: symbols, diagnostics: diagnostics,
                    interner: interner, filesByID: filesByID
                )
            }
            // Validate secondary constructor annotations and their parameters
            for ctor in classDecl.secondaryConstructors {
                for annotation in ctor.annotations {
                    validateAnnotationTarget(
                        annotation: annotation,
                        site: .constructor,
                        ownerRange: decl.range,
                        decl: decl,
                        file: file,
                        propertySymbol: nil,
                        symbols: symbols,
                        diagnostics: diagnostics,
                        interner: interner,
                        filesByID: filesByID
                    )
                }
                for param in ctor.valueParams {
                    validateValueParamAnnotations(
                        param: param, ownerDecl: decl, file: file,
                        symbols: symbols, diagnostics: diagnostics,
                        interner: interner, filesByID: filesByID
                    )
                }
            }
            // Validate enum entry annotations
            for entry in classDecl.enumEntries {
                for annotation in entry.annotations {
                    validateAnnotationTarget(
                        annotation: annotation,
                        site: .enumEntry,
                        ownerRange: decl.range,
                        decl: decl,
                        file: file,
                        propertySymbol: nil,
                        symbols: symbols,
                        diagnostics: diagnostics,
                        interner: interner,
                        filesByID: filesByID
                    )
                }
            }
        case let .interfaceDecl(interfaceDecl):
            validateMemberAnnotationTargets(
                declIDs: interfaceDecl.memberFunctions + interfaceDecl.memberProperties + interfaceDecl.nestedClasses + interfaceDecl.nestedObjects,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
            if let companion = interfaceDecl.companionObject {
                validateAnnotationTargets(
                    declID: companion,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
        case let .objectDecl(objectDecl):
            validateMemberAnnotationTargets(
                declIDs: objectDecl.memberFunctions + objectDecl.memberProperties + objectDecl.nestedClasses + objectDecl.nestedObjects,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        case let .funDecl(funDecl):
            for param in funDecl.valueParams {
                validateValueParamAnnotations(
                    param: param, ownerDecl: decl, file: file,
                    symbols: symbols, diagnostics: diagnostics,
                    interner: interner, filesByID: filesByID
                )
            }
        case let .propertyDecl(property):
            for accessor in [property.getter, property.setter].compactMap({ $0 }) {
                for annotation in accessor.annotations {
                    validateAnnotationTarget(
                        annotation: annotation,
                        site: accessor.kind == .getter ? .getter : .setter,
                        ownerRange: accessor.range, decl: decl, file: file,
                        propertySymbol: symbolID, symbols: symbols,
                        diagnostics: diagnostics, interner: interner,
                        filesByID: filesByID
                    )
                }
            }
        case .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    /// Validates annotations on a value parameter, mapping use-site targets to the
    /// appropriate `AnnotationUsageSite` rather than blindly using `.valueParameter`.
    ///
    /// Kotlin allows `@field:Anno`, `@get:Anno`, `@set:Anno`, `@param:Anno`, and
    /// `@setparam:Anno` on primary-constructor parameters. Each must be validated
    /// against the corresponding target kind, not the `VALUE_PARAMETER` target.
    private func validateValueParamAnnotations(
        param: ValueParamDecl,
        ownerDecl: Decl,
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        for annotation in param.annotations {
            let site: AnnotationUsageSite
            switch annotation.useSiteTarget?.lowercased() {
            case nil:
                site = param.isProperty ? .constructorPropertyParameter : .valueParameter
            case "param", "setparam":
                site = .valueParameter
            case "field":
                site = .paramField
            case "get":
                site = .getter
            case "set":
                site = .setter
            case "property":
                site = .property(explicitUseSiteTarget: true)
            case "delegate":
                site = .delegate
            default:
                site = .valueParameter
            }
            validateAnnotationTarget(
                annotation: annotation,
                site: site,
                ownerRange: ownerDecl.range,
                decl: ownerDecl,
                file: file,
                propertySymbol: nil,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        }
    }

    private func validateMemberAnnotationTargets(
        declIDs: [DeclID],
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        for declID in declIDs {
            validateAnnotationTargets(
                declID: declID,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        }
    }

    private func validateAnnotationTarget(
        annotation: AnnotationNode,
        site: AnnotationUsageSite,
        ownerRange: SourceRange?,
        decl: Decl?,
        file: ASTFile,
        propertySymbol: SymbolID?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile],
        isTopLevel: Bool = false
    ) {
        guard let annotationSymbolID = resolveAnnotationSymbol(
            named: annotation.name,
            in: file,
            symbols: symbols,
            interner: interner
        ), let annotationSymbol = symbols.symbol(annotationSymbolID),
              annotationSymbol.kind == .annotationClass
        else {
            return
        }

        if case .getter = site,
           symbols.annotations(for: annotationSymbolID).contains(where: {
               KnownCompilerAnnotation.requiresOptIn.matches($0.annotationFQName)
           }) {
            diagnostics.error(
                "KSWIFTK-SEMA-OPT-IN-GETTER",
                "Opt-in requirement marker annotation cannot be used on getter.",
                range: ownerRange
            )
            return
        }

        guard let allowedTargets = annotationTargets(
            for: annotationSymbolID,
            symbols: symbols,
            filesByID: filesByID,
            interner: interner
        ) else {
            return
        }

        guard annotationTarget(
            site: site,
            allowedTargets: allowedTargets,
            decl: decl,
            propertySymbol: propertySymbol,
            symbols: symbols
        ) else {
            diagnostics.error(
                "KSWIFTK-SEMA-ANNOTATION-TARGET",
                annotationTargetMessage(
                    annotationName: annotation.name,
                    site: site
                ),
                range: ownerRange
            )
            return
        }

        let expectRefinementFQName = ["kotlin", "experimental", "ExpectRefinement"].map {
            interner.intern($0)
        }
        if annotationSymbol.fqName == expectRefinementFQName,
           !isTopLevel || !isExpectDeclaration(decl)
        {
            diagnostics.error(
                "KSWIFTK-SEMA-EXPECT-REFINEMENT",
                "Only top-level 'expect' declarations can be annotated with '@ExpectRefinement'.",
                range: ownerRange
            )
        }
    }

    private func isExpectDeclaration(_ decl: Decl?) -> Bool {
        guard let decl else {
            return false
        }
        switch decl {
        case let .classDecl(classDecl):
            return classDecl.modifiers.contains(.expect)
        case let .interfaceDecl(interfaceDecl):
            return interfaceDecl.modifiers.contains(.expect)
        case let .objectDecl(objectDecl):
            return objectDecl.modifiers.contains(.expect)
        default:
            return false
        }
    }

    private func annotationUsageSite(
        for annotation: AnnotationNode,
        on decl: Decl,
        ownerSymbol: SemanticSymbol?
    ) -> AnnotationUsageSite? {
        let useSiteTarget = annotation.useSiteTarget?.lowercased()
        switch decl {
        case .classDecl, .interfaceDecl, .objectDecl:
            guard useSiteTarget == nil else {
                return nil
            }
            return .classLike(ownerSymbol?.kind ?? fallbackClassLikeKind(for: decl))
        case .funDecl:
            guard useSiteTarget == nil else {
                return nil
            }
            return .function
        case .propertyDecl:
            switch useSiteTarget {
            case nil:
                return .property(explicitUseSiteTarget: false)
            case "property":
                return .property(explicitUseSiteTarget: true)
            case "field":
                return .field
            case "delegate":
                return .delegate
            case "get":
                return .getter
            case "set":
                return .setter
            default:
                return nil
            }
        case .typeAliasDecl:
            guard useSiteTarget == nil else {
                return nil
            }
            return .typeAlias
        case .enumEntryDecl:
            guard useSiteTarget == nil else { return nil }
            return .enumEntry
        }
    }

    private func fallbackClassLikeKind(for decl: Decl) -> SymbolKind {
        switch decl {
        case .interfaceDecl:
            return .interface
        case .objectDecl:
            return .object
        default:
            return .class
        }
    }

    private func annotationTargets(
        for annotationSymbol: SymbolID,
        symbols: SymbolTable,
        filesByID: [Int32: ASTFile],
        interner: StringInterner
    ) -> Set<String>? {
        guard let symbol = symbols.symbol(annotationSymbol),
              symbol.kind == .annotationClass
        else {
            return nil
        }

        var sawTargetMeta = false
        var allowedTargets: Set<String> = []
        for meta in symbols.annotations(for: annotationSymbol) {
            guard isTargetMetaAnnotation(
                meta,
                for: annotationSymbol,
                symbols: symbols,
                filesByID: filesByID,
                interner: interner
            ) else {
                continue
            }
            sawTargetMeta = true
            allowedTargets.formUnion(parseAnnotationTargets(from: meta.arguments))
        }

        // Kotlin's default annotation target set includes every declaration
        // target except FILE. In particular, opt-in marker annotations without
        // an explicit @Target must not become file annotations.
        return sawTargetMeta ? allowedTargets : Self.defaultDeclarationAnnotationTargets
    }

    private static let defaultDeclarationAnnotationTargets: Set<String> = [
        "CLASS",
        "ANNOTATION_CLASS",
        "TYPE_PARAMETER",
        "PROPERTY",
        "FIELD",
        "LOCAL_VARIABLE",
        "VALUE_PARAMETER",
        "CONSTRUCTOR",
        "FUNCTION",
        "PROPERTY_GETTER",
        "PROPERTY_SETTER",
        "TYPE",
        "EXPRESSION",
        "TYPEALIAS",
    ]

    private func isTargetMetaAnnotation(
        _ annotation: MetadataAnnotationRecord,
        for annotationSymbol: SymbolID,
        symbols: SymbolTable,
        filesByID: [Int32: ASTFile],
        interner: StringInterner
    ) -> Bool {
        let builtInTargetFQName: [InternedString] = [
            "kotlin",
            "annotation",
            "Target",
        ].map { interner.intern($0) }
        if annotation.annotationFQName == KnownCompilerAnnotation.target.qualifiedName {
            return true
        }

        guard let sourceFileID = symbols.sourceFileID(for: annotationSymbol),
              let sourceFile = filesByID[sourceFileID.rawValue]
        else {
            return false
        }

        guard let resolvedSymbolID = resolveAnnotationSymbol(
            named: annotation.annotationFQName,
            in: sourceFile,
            symbols: symbols,
            interner: interner
        ), let resolvedSymbol = symbols.symbol(resolvedSymbolID)
        else {
            return false
        }

        return resolvedSymbol.fqName == builtInTargetFQName
    }

    private func parseAnnotationTargets(from arguments: [String]) -> Set<String> {
        let knownTargets: Set<String> = [
            "CLASS",
            "ANNOTATION_CLASS",
            "TYPE_PARAMETER",
            "PROPERTY",
            "FIELD",
            "LOCAL_VARIABLE",
            "VALUE_PARAMETER",
            "CONSTRUCTOR",
            "FUNCTION",
            "PROPERTY_GETTER",
            "PROPERTY_SETTER",
            "TYPE",
            "EXPRESSION",
            "FILE",
            "TYPEALIAS",
        ]

        var parsed: Set<String> = []
        for argument in arguments {
            let value = SemaAnnotationArgument.value(argument)
            let tokens = value.split { character in
                !(character.isLetter || character.isNumber || character == "_")
            }
            for token in tokens {
                let candidate = String(token).uppercased()
                if knownTargets.contains(candidate) {
                    parsed.insert(candidate)
                }
            }
        }
        return parsed
    }

    private func annotationTarget(
        site: AnnotationUsageSite,
        allowedTargets: Set<String>,
        decl: Decl?,
        propertySymbol: SymbolID?,
        symbols: SymbolTable
    ) -> Bool {
        switch site {
        case let .classLike(kind):
            if allowedTargets.contains("CLASS") {
                return true
            }
            return kind == .annotationClass && allowedTargets.contains("ANNOTATION_CLASS")
        case .function:
            return allowedTargets.contains("FUNCTION")
        case .constructor:
            return allowedTargets.contains("CONSTRUCTOR")
        case .valueParameter:
            return allowedTargets.contains("VALUE_PARAMETER")
        case .constructorPropertyParameter:
            return !allowedTargets.isDisjoint(with: ["VALUE_PARAMETER", "PROPERTY", "FIELD"])
        case .enumEntry:
            return allowedTargets.contains("FIELD") || allowedTargets.contains("CLASS")
        case let .property(explicitUseSiteTarget):
            if allowedTargets.contains("PROPERTY") {
                return true
            }
            guard !explicitUseSiteTarget,
                  let propertyDecl = decl.flatMap(propertyDecl(from:)),
                  propertyAllowsFieldTarget(propertyDecl)
            else {
                return false
            }
            return allowedTargets.contains("FIELD")
        case .getter:
            return allowedTargets.contains("PROPERTY_GETTER")
        case .setter:
            return allowedTargets.contains("PROPERTY_SETTER")
        case .field:
            guard let propertyDecl = decl.flatMap(propertyDecl(from:)),
                  propertyAllowsFieldTarget(propertyDecl)
            else {
                return false
            }
            return allowedTargets.contains("FIELD")
        case .paramField:
            // Constructor parameter backing field — always has a backing field
            // (val/var params always generate a field), so skip PropertyDecl guard.
            return allowedTargets.contains("FIELD")
        case .delegate:
            guard let propertySymbol,
                  symbols.delegateStorageSymbol(for: propertySymbol) != nil
            else {
                return false
            }
            return allowedTargets.contains("FIELD")
        case .file:
            return allowedTargets.contains("FILE")
        case .type:
            return allowedTargets.contains("TYPE")
        case .typeAlias:
            return allowedTargets.contains("TYPEALIAS")
        }
    }

    private func annotationTargetMessage(
        annotationName: String,
        site: AnnotationUsageSite
    ) -> String {
        let targetDescription = annotationTargetDescription(for: site)
        return "Annotation '\(annotationName)' is not applicable to \(targetDescription)."
    }

    private func annotationTargetDescription(
        for site: AnnotationUsageSite
    ) -> String {
        switch site {
        case .classLike(let kind):
            switch kind {
            case .annotationClass:
                return "an annotation class declaration"
            case .enumClass:
                return "an enum class declaration"
            case .interface:
                return "an interface declaration"
            case .object:
                return "an object declaration"
            default:
                return "a class declaration"
            }
        case .function:
            return "a function"
        case .constructor:
            return "a constructor"
        case .valueParameter:
            return "a value parameter"
        case .constructorPropertyParameter:
            return "a constructor property parameter"
        case .enumEntry:
            return "an enum entry"
        case .property:
            return "a property"
        case .getter:
            return "a property getter"
        case .setter:
            return "a property setter"
        case .field:
            return "a backing field"
        case .paramField:
            return "a constructor parameter's backing field"
        case .delegate:
            return "a delegate storage field"
        case .file:
            return "the file"
        case .type:
            return "a type usage"
        case .typeAlias:
            return "a type alias declaration"
        }
    }

    private func propertyDecl(from decl: Decl?) -> PropertyDecl? {
        guard case let .propertyDecl(propertyDecl)? = decl else {
            return nil
        }
        return propertyDecl
    }

    private func propertyAllowsFieldTarget(_ propertyDecl: PropertyDecl) -> Bool {
        if propertyDecl.receiverType != nil {
            return false
        }
        if propertyDecl.explicitBackingField != nil {
            return true
        }
        if propertyDecl.delegateExpression != nil {
            return false
        }
        if propertyDecl.modifiers.contains(.abstract) {
            return false
        }
        let isGetterOnlyComputed = propertyDecl.getter != nil
            && propertyDecl.setter == nil
            && propertyDecl.initializer == nil
            && !propertyDecl.isSynthesizedPrimaryConstructorProperty
        if isGetterOnlyComputed {
            return false
        }
        return propertyDecl.initializer != nil
            || propertyDecl.getter != nil
            || propertyDecl.setter != nil
            || propertyDecl.isSynthesizedPrimaryConstructorProperty
    }

    private enum AnnotationUsageSite {
        case classLike(SymbolKind)
        case function
        case constructor
        case valueParameter
        case constructorPropertyParameter
        case enumEntry
        case property(explicitUseSiteTarget: Bool)
        case getter
        case setter
        case field
        /// Like `.field` but applies to a constructor parameter's backing field —
        /// always valid for `FIELD` target without requiring a `PropertyDecl`.
        case paramField
        case delegate
        case file
        case type
        case typeAlias
    }
}

private extension DataFlowSemaPhase {
    func validateTypeAnnotationTargets(
        in decl: Decl,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        switch decl {
        case let .classDecl(classDecl):
            for superType in classDecl.superTypeEntries {
                validateTypeAnnotationTargets(
                    typeRefID: superType.typeRef,
                    ownerRange: classDecl.range,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
            for param in classDecl.primaryConstructorParams {
                if let type = param.type {
                    validateTypeAnnotationTargets(typeRefID: type, ownerRange: classDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
                }
            }
        case let .interfaceDecl(interfaceDecl):
            for superType in interfaceDecl.superTypes {
                validateTypeAnnotationTargets(typeRefID: superType, ownerRange: interfaceDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .funDecl(funDecl):
            if let receiverType = funDecl.receiverType {
                validateTypeAnnotationTargets(typeRefID: receiverType, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            for param in funDecl.valueParams {
                if let type = param.type {
                    validateTypeAnnotationTargets(typeRefID: type, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
                }
            }
            if let returnType = funDecl.returnType {
                validateTypeAnnotationTargets(typeRefID: returnType, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .propertyDecl(propertyDecl):
            if let receiverType = propertyDecl.receiverType {
                validateTypeAnnotationTargets(typeRefID: receiverType, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            if let type = propertyDecl.type {
                validateTypeAnnotationTargets(typeRefID: type, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            if let fieldType = propertyDecl.explicitBackingField?.type {
                validateTypeAnnotationTargets(typeRefID: fieldType, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .typeAliasDecl(typeAliasDecl):
            if let underlyingType = typeAliasDecl.underlyingType {
                validateTypeAnnotationTargets(typeRefID: underlyingType, ownerRange: typeAliasDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case .objectDecl, .enumEntryDecl:
            break
        }
    }

    func validateTypeAnnotationTargets(
        typeRefID: TypeRefID,
        ownerRange: SourceRange?,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return
        }

        switch typeRef {
        case let .named(_, args, _):
            for arg in args {
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    validateTypeAnnotationTargets(typeRefID: inner, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
                case .star:
                    break
                }
            }
        case let .functionType(_, receiver, params, returnType, _, _):
            if let receiver {
                validateTypeAnnotationTargets(typeRefID: receiver, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            for param in params {
                validateTypeAnnotationTargets(typeRefID: param, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            validateTypeAnnotationTargets(typeRefID: returnType, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
        case let .intersection(parts):
            for part in parts {
                validateTypeAnnotationTargets(typeRefID: part, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .annotated(base, annotations):
            for annotation in annotations {
                validateAnnotationTarget(
                    annotation: annotation,
                    site: .type,
                    ownerRange: ownerRange,
                    decl: nil,
                    file: file,
                    propertySymbol: nil,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
            validateTypeAnnotationTargets(typeRefID: base, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
        }
    }
}
