import Foundation

private struct AnnotationTargetResolutionContext {
    let types: TypeSystem
    let propertyValidator: DeclarationPositionValidator
    let bindings: BindingTable
    let sourceManager: SourceManager?
    var jvmTarget: JVMTarget? = nil
    var hasInferredBodies = false
    var enclosingFQName: [InternedString] = []
    var lexicalEnclosingFQNames: [[InternedString]] = []

    func within(_ owner: [InternedString]) -> Self {
        var nested = self
        nested.enclosingFQName = owner
        if !owner.isEmpty { nested.lexicalEnclosingFQNames.insert(owner, at: 0) }
        return nested
    }
}

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
        // BuildAST emits these properties in parameter order. Pair declarations
        // within this class, rather than looking up a same-named property.
        let properties = classDecl.memberProperties.compactMap { declaration -> (DeclID, PropertyDecl)? in
            guard case let .propertyDecl(property) = ast.arena.decl(declaration),
                  property.isSynthesizedPrimaryConstructorProperty else { return nil }
            return (declaration, property)
        }
        let propertyParameters = classDecl.primaryConstructorParams.enumerated().filter { $0.element.isProperty }
        for ((index, parameter), (propertyID, property)) in zip(propertyParameters, properties) {
            guard property.name == parameter.name,
                  let propertySymbol = bindings.declSymbols[propertyID] else { continue }
            if let owner = symbols.parentSymbol(for: propertySymbol),
               let constructor = symbols.symbols(atDeclSite: classDecl.range).first(where: {
                   symbols.symbol($0)?.kind == .constructor && symbols.parentSymbol(for: $0) == owner
               }), let signature = symbols.functionSignature(for: constructor),
               index < signature.parameterTypes.count {
                // The call signature stores a vararg's element type, but its
                // source parameter type is the same array as the property.
                let parameterType = parameter.isVararg
                    ? symbols.propertyType(for: propertySymbol) ?? signature.parameterTypes[index]
                    : signature.parameterTypes[index]
                bindings.primaryConstructorPropertyParameters[propertySymbol] = (
                    parameter, parameterType, constructor
                )
            }
            guard !parameter.annotations.isEmpty,
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

    /// Called after body inference so speculative diagnostics cannot discard
    /// target errors from a nominal that was already registered in that probe.
    func validateDeferredAnnotationTargets(
        ast: ASTModule, symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        diagnostics: DiagnosticEngine, interner: StringInterner,
        sourceManager: SourceManager? = nil, jvmTarget: JVMTarget? = nil
    ) {
        let pending = bindings.takePendingAnnotationTargets()
        guard !pending.isEmpty else { return }
        let filesByID = Dictionary(uniqueKeysWithValues: ast.sortedFiles.map { ($0.fileID.rawValue, $0) })
        for declID in pending.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let decl = ast.arena.decl(declID), let file = ast.file(for: decl.range.start.file) else { continue }
            let resolutionContext = AnnotationTargetResolutionContext(
                types: types,
                propertyValidator: DeclarationPositionValidator(astArena: ast.arena, interner: interner, diagnostics: nil),
                bindings: bindings,
                sourceManager: sourceManager,
                jvmTarget: jvmTarget,
                hasInferredBodies: true,
                lexicalEnclosingFQNames: pending[declID] ?? []
            )
            validateAnnotationTargets(
                declID: declID, file: file, ast: ast, symbols: symbols, bindings: bindings,
                diagnostics: diagnostics, interner: interner, filesByID: filesByID,
                resolutionContext: resolutionContext,
                isTopLevel: file.topLevelDecls.contains(declID)
            )
        }
    }

    func validateAnnotationTargets(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        sourceManager: SourceManager? = nil, jvmTarget: JVMTarget? = nil
    ) {
        let resolutionContext = AnnotationTargetResolutionContext(
            types: types,
            propertyValidator: DeclarationPositionValidator(astArena: ast.arena, interner: interner, diagnostics: nil),
            bindings: bindings,
            sourceManager: sourceManager,
            jvmTarget: jvmTarget
        )
        let filesByID = Dictionary(uniqueKeysWithValues: ast.sortedFiles.map { ($0.fileID.rawValue, $0) })

        for file in ast.sortedFiles {
            validateFileAnnotationTargets(
                file: file,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID,
                resolutionContext: resolutionContext
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
                    resolutionContext: resolutionContext,
                    isTopLevel: true
                )
            }
        }

        validateExpressionAnnotationTargets(
            ast: ast, symbols: symbols, types: types, bindings: bindings,
            diagnostics: diagnostics, interner: interner, filesByID: filesByID,
            sourceManager: sourceManager
        )
    }

    private func validateExpressionAnnotationTargets(
        ast: ASTModule, symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        diagnostics: DiagnosticEngine, interner: StringInterner, filesByID: [Int32: ASTFile],
        sourceManager: SourceManager?
    ) {
        let annotationsByExpr = ast.arena.annotatedExpressions
        let owners = ast.arena.decls.enumerated().compactMap { index, decl -> (SourceRange, [InternedString])? in
            guard let symbol = bindings.declSymbols[DeclID(rawValue: Int32(index))],
                  let owner = symbols.symbol(symbol) else { return nil }
            return (decl.range, owner.fqName)
        }
        // Type references embedded in body expressions (local declarations,
        // casts, explicit type arguments, object-literal supertypes, local
        // functions) are not reachable from the declaration walk; validate
        // their annotations with the same enclosing-decl context.
        validateBodyEmbeddedTypeAnnotations(
            ast: ast, owners: owners, types: types, bindings: bindings,
            symbols: symbols, diagnostics: diagnostics, interner: interner,
            filesByID: filesByID, sourceManager: sourceManager
        )
        guard !annotationsByExpr.isEmpty else { return }
        // Compound-assignment and inc/dec desugars mirror the leading
        // annotation onto both the operand and the rewritten assignment
        // expression; validate each source annotation occurrence once.
        var seenAnnotationUsages: Set<String> = []
        for exprID in annotationsByExpr.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let range = ast.arena.exprRange(exprID), let file = ast.file(for: range.start.file) else { continue }
            let enclosingOwners = owners.filter { $0.0.contains(range) }.sorted {
                ($0.0.end.offset - $0.0.start.offset) < ($1.0.end.offset - $1.0.start.offset)
            }.map { $0.1 }
            let resolutionContext = AnnotationTargetResolutionContext(
                types: types,
                propertyValidator: DeclarationPositionValidator(astArena: ast.arena, interner: interner, diagnostics: nil),
                bindings: bindings,
                sourceManager: sourceManager,
                enclosingFQName: enclosingOwners.first ?? [],
                lexicalEnclosingFQNames: enclosingOwners
            )
            let isFunctionLiteral: Bool
            if case .lambdaLiteral = ast.arena.expr(exprID) {
                isFunctionLiteral = true
            } else {
                isFunctionLiteral = ast.arena.isAnonymousFunction(exprID)
            }
            let annotations = annotationsByExpr[exprID] ?? []
            validateAnnotationRepeatability(
                annotations: annotations, file: file, symbols: symbols,
                diagnostics: diagnostics, interner: interner, resolutionContext: resolutionContext
            )
            for annotation in annotations {
                if let usageID = annotation.usageID, !seenAnnotationUsages.insert(usageID).inserted {
                    continue
                }
                // Register before body inference and worker creation, retaining
                // the existing diagnostic-name and severity suppression policy.
                if let symbolID = resolveAnnotationSymbol(
                    named: annotation.name, in: file, symbols: symbols, interner: interner,
                    types: types, enclosingFQName: resolutionContext.enclosingFQName,
                    lexicalEnclosingFQNames: enclosingOwners
                ), let symbol = symbols.symbol(symbolID),
                   symbol.fqName.map(interner.resolve).joined(separator: ".") == "kotlin.Suppress" {
                    let concatenatedArguments = concatenatedExpressionAnnotationArguments(annotation)
                    for (index, argument) in annotation.arguments.enumerated() where !concatenatedArguments.contains(index) {
                        guard let literal = extractKotlinStringLiteralContent(argument) else { continue }
                        let code = literal.isRaw ? literal.content : decodeKotlinStringEscapes(literal.content)
                        if !code.isEmpty { diagnostics.addSuppression(code: code, range: range) }
                    }
                }
                validateAnnotationTarget(
                    annotation: annotation, site: .expression(isFunctionLiteral: isFunctionLiteral), ownerRange: range,
                    decl: nil, file: file, propertySymbol: nil, symbols: symbols,
                    diagnostics: diagnostics, interner: interner, filesByID: filesByID,
                    resolutionContext: resolutionContext
                )
            }
        }
    }

    /// Kotlin 2.3.10 reads suppression names from literals, leaving string
    /// concatenations unsuppressed even though annotation metadata folds them.
    private func concatenatedExpressionAnnotationArguments(_ annotation: AnnotationNode) -> Set<Int> {
        guard let tokens = annotation.constructionTokens,
              let opening = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else { return [] }
        var concatenated: Set<Int> = []
        var argument = 0
        var paren = 1
        var bracket = 0
        var brace = 0
        for token in tokens.dropFirst(opening + 1) {
            switch token.kind {
            case .symbol(.comma) where paren == 1 && bracket == 0 && brace == 0:
                argument += 1
            case .symbol(.plus): concatenated.insert(argument)
            case .symbol(.lParen): paren += 1
            case .symbol(.rParen): paren -= 1
            case .symbol(.lBracket): bracket += 1
            case .symbol(.rBracket): bracket -= 1
            case .symbol(.lBrace): brace += 1
            case .symbol(.rBrace): brace -= 1
            default: break
            }
            if paren == 0 { break }
        }
        return concatenated
    }

    private func validateBodyEmbeddedTypeAnnotations(
        ast: ASTModule,
        owners: [(SourceRange, [InternedString])],
        types: TypeSystem,
        bindings: BindingTable,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile],
        sourceManager: SourceManager?
    ) {
        for (index, expr) in ast.arena.exprs.enumerated() {
            let exprID = ExprID(rawValue: Int32(index))
            var typeRefs: [TypeRefID] = []
            switch expr {
            case let .localDecl(_, _, typeAnnotation, _, _, _, _):
                if let typeAnnotation {
                    typeRefs.append(typeAnnotation)
                }
            case let .call(_, typeArgs, _, _),
                 let .memberCall(_, _, typeArgs, _, _),
                 let .safeMemberCall(_, _, typeArgs, _, _):
                typeRefs.append(contentsOf: typeArgs)
            case let .isCheck(_, type, _, _):
                typeRefs.append(type)
            case let .asCast(_, type, _, _):
                typeRefs.append(type)
            case let .objectLiteral(superTypes, _, _):
                typeRefs.append(contentsOf: superTypes)
            case let .localFunDecl(_, receiverType, valueParams, returnType, _, _, _, typeParams, _):
                if let receiverType {
                    typeRefs.append(receiverType)
                }
                typeRefs.append(contentsOf: valueParams.compactMap(\.type))
                if let returnType {
                    typeRefs.append(returnType)
                }
                for typeParam in typeParams {
                    typeRefs.append(contentsOf: typeParam.upperBounds)
                }
            case let .tryExpr(_, catchClauses, _, _):
                typeRefs.append(contentsOf: catchClauses.compactMap(\.paramType))
            case .callableRef:
                if let typeRef = ast.arena.callableRefReceiverTypeRef(for: exprID) {
                    typeRefs.append(typeRef)
                }
            default:
                break
            }
            guard !typeRefs.isEmpty,
                  let range = ast.arena.exprRange(exprID),
                  let file = ast.file(for: range.start.file) else { continue }
            let enclosingOwners = owners.filter { $0.0.contains(range) }.sorted {
                ($0.0.end.offset - $0.0.start.offset) < ($1.0.end.offset - $1.0.start.offset)
            }.map { $0.1 }
            let resolutionContext = AnnotationTargetResolutionContext(
                types: types,
                propertyValidator: DeclarationPositionValidator(astArena: ast.arena, interner: interner, diagnostics: nil),
                bindings: bindings,
                sourceManager: sourceManager,
                enclosingFQName: enclosingOwners.first ?? [],
                lexicalEnclosingFQNames: enclosingOwners
            )
            for typeRef in typeRefs {
                validateTypeAnnotationTargets(
                    typeRefID: typeRef,
                    ownerRange: range,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID,
                    resolutionContext: resolutionContext
                )
            }
        }
    }

    private func validateFileAnnotationTargets(
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile],
        resolutionContext: AnnotationTargetResolutionContext
    ) {
        guard !file.annotations.isEmpty else {
            return
        }

        validateAnnotationRepeatability(
            annotations: file.annotations, file: file, symbols: symbols,
            diagnostics: diagnostics, interner: interner, resolutionContext: resolutionContext
        )
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
                filesByID: filesByID,
                resolutionContext: resolutionContext
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
        resolutionContext: AnnotationTargetResolutionContext,
        isTopLevel: Bool = false
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        let symbolID = bindings.declSymbols[declID]
        let ownerSymbol = symbolID.flatMap { symbols.symbol($0) }
        var resolutionContext = resolutionContext
        if let ownerSymbol {
            resolutionContext.enclosingFQName = Array(ownerSymbol.fqName.dropLast())
        }
        let memberResolutionContext = resolutionContext.within(ownerSymbol?.fqName ?? [])

        let isJvmRecord = decl.annotations.contains { annotation in
            guard let annotationID = resolveAnnotationSymbol(
                named: annotation.name, in: file, symbols: symbols, interner: interner,
                types: resolutionContext.types, enclosingFQName: resolutionContext.enclosingFQName,
                lexicalEnclosingFQNames: resolutionContext.lexicalEnclosingFQNames
            ), let symbol = symbols.symbol(annotationID) else { return false }
            return symbol.fqName.map(interner.resolve) == ["kotlin", "jvm", "JvmRecord"]
        }
        if isJvmRecord, case .classDecl = decl, !resolutionContext.hasInferredBodies {
            // Accessor bodies must be resolved before a local named `field` can
            // be distinguished from a reference to a record's backing field.
            bindings.deferAnnotationTargets(declID, lexicalEnclosingFQNames: resolutionContext.lexicalEnclosingFQNames)
            return
        }
        if isJvmRecord {
            validateJvmRecordDeclaration(
                decl, ownerSymbol: ownerSymbol, file: file, ast: ast, symbols: symbols,
                bindings: bindings, diagnostics: diagnostics, interner: interner,
                resolutionContext: resolutionContext
            )
        }

        validateAnnotationRepeatability(
            annotations: decl.annotations, file: file, symbols: symbols,
            diagnostics: diagnostics, interner: interner, resolutionContext: resolutionContext
        )
        for typeParam in annotationTypeParameters(in: decl) {
            validateAnnotationRepeatability(
                annotations: typeParam.annotations, file: file, symbols: symbols,
                diagnostics: diagnostics, interner: interner, resolutionContext: resolutionContext
            )
        }

        if !resolutionContext.hasInferredBodies, !decl.annotations.isEmpty,
           case let .propertyDecl(property) = decl,
           property.explicitBackingField == nil,
           resolutionContext.propertyValidator.accessorHasBody(property.getter),
           !property.isVar || resolutionContext.propertyValidator.accessorHasBody(property.setter),
           resolutionContext.propertyValidator.accessorUsesBackingField(property.getter)
               || resolutionContext.propertyValidator.accessorUsesBackingField(property.setter)
        {
            // A local named `field` can shadow the accessor's backing field.
            // Reuse the post-inference target pass to inspect resolved bindings.
            bindings.deferAnnotationTargets(declID, lexicalEnclosingFQNames: resolutionContext.lexicalEnclosingFQNames)
            return
        }

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
                resolutionContext: resolutionContext,
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
            filesByID: filesByID,
            resolutionContext: memberResolutionContext
        )

        switch decl {
        case let .classDecl(classDecl):
            validateMemberAnnotationTargets(
                declIDs: classDecl.memberFunctions + classDecl.memberProperties
                    + classDecl.nestedClasses + classDecl.nestedObjects
                    + classDecl.enumEntries.flatMap(\.nestedClasses),
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID,
                resolutionContext: memberResolutionContext
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
                    filesByID: filesByID,
                    resolutionContext: memberResolutionContext
                )
            }
            validateAnnotationRepeatability(
                annotations: classDecl.primaryConstructorAnnotations, file: file, symbols: symbols,
                diagnostics: diagnostics, interner: interner, resolutionContext: memberResolutionContext
            )
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
                    filesByID: filesByID,
                    resolutionContext: memberResolutionContext
                )
            }
            for param in classDecl.primaryConstructorParams {
                validateValueParamAnnotations(
                    param: param, ownerDecl: decl, file: file,
                    symbols: symbols, diagnostics: diagnostics,
                    interner: interner, filesByID: filesByID, resolutionContext: memberResolutionContext
                )
            }
            for ctor in classDecl.secondaryConstructors {
                validateAnnotationRepeatability(
                    annotations: ctor.annotations, file: file, symbols: symbols,
                    diagnostics: diagnostics, interner: interner, resolutionContext: memberResolutionContext
                )
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
                        filesByID: filesByID,
                        resolutionContext: memberResolutionContext
                    )
                }
                for param in ctor.valueParams {
                    validateValueParamAnnotations(
                        param: param, ownerDecl: decl, file: file,
                        symbols: symbols, diagnostics: diagnostics,
                        interner: interner, filesByID: filesByID, resolutionContext: memberResolutionContext
                    )
                }
            }
            for entry in classDecl.enumEntries {
                validateAnnotationRepeatability(
                    annotations: entry.annotations, file: file, symbols: symbols,
                    diagnostics: diagnostics, interner: interner, resolutionContext: memberResolutionContext
                )
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
                        filesByID: filesByID,
                        resolutionContext: memberResolutionContext
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
                filesByID: filesByID,
                resolutionContext: memberResolutionContext
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
                    filesByID: filesByID,
                    resolutionContext: memberResolutionContext
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
                filesByID: filesByID,
                resolutionContext: memberResolutionContext
            )
        case let .funDecl(funDecl):
            for param in funDecl.valueParams {
                validateValueParamAnnotations(
                    param: param, ownerDecl: decl, file: file,
                    symbols: symbols, diagnostics: diagnostics,
                    interner: interner, filesByID: filesByID, resolutionContext: resolutionContext
                )
            }
        case let .propertyDecl(property):
            for accessor in [property.getter, property.setter].compactMap({ $0 }) {
                validateAnnotationRepeatability(
                    annotations: accessor.annotations, file: file, symbols: symbols,
                    diagnostics: diagnostics, interner: interner, resolutionContext: resolutionContext
                )
                for annotation in accessor.annotations {
                    validateAnnotationTarget(
                        annotation: annotation,
                        site: accessor.kind == .getter ? .getter : .setter,
                        ownerRange: accessor.range, decl: decl, file: file,
                        propertySymbol: symbolID, symbols: symbols,
                        diagnostics: diagnostics, interner: interner,
                        filesByID: filesByID,
                        resolutionContext: resolutionContext
                    )
                }
            }
        case .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    private func validateJvmRecordDeclaration(
        _ decl: Decl,
        ownerSymbol: SemanticSymbol?,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        resolutionContext: AnnotationTargetResolutionContext
    ) {
        guard case let .classDecl(record) = decl else {
            diagnostics.error("KSWIFTK-SEMA-JVM-RECORD", "@JvmRecord requires a data or full value class.", range: decl.range)
            return
        }
        func reject(_ message: String, at range: SourceRange) {
            diagnostics.error("KSWIFTK-SEMA-JVM-RECORD", message, range: range)
        }
        if let target = resolutionContext.jvmTarget, !target.supportsJvmRecords {
            reject("@JvmRecord requires JVM target 16 or later.", at: record.range)
            return
        }
        if ownerSymbol?.flags.contains(.synthetic) == true {
            reject("@JvmRecord cannot be used on a local class.", at: record.range)
            return
        }
        if record.isInner || record.modifiers.contains(.open) || record.modifiers.contains(.abstract)
            || record.modifiers.contains(.sealed) || record.modifiers.contains(.enumModifier) {
            reject("@JvmRecord requires a final, non-inner class.", at: record.range)
            return
        }
        let isFullValue = isFullValueClassDeclaration(record, imports: file.imports, enabled: true, interner: interner)
        guard record.modifiers.contains(.data) || isFullValue else {
            reject("@JvmRecord requires a data or full value class.", at: record.range)
            return
        }
        if record.primaryConstructorParams.isEmpty {
            reject("@JvmRecord requires at least one primary constructor parameter.", at: record.range)
        }
        for (index, parameter) in record.primaryConstructorParams.enumerated() {
            if parameter.isMutableProperty {
                reject("@JvmRecord constructor properties must be val.", at: record.range)
            }
            if parameter.isVararg && index != record.primaryConstructorParams.count - 1 {
                reject("Only the last @JvmRecord constructor parameter may be vararg.", at: record.range)
            }
        }
        for entry in record.superTypeEntries {
            if entry.delegateExpression != nil {
                reject("@JvmRecord cannot delegate an interface.", at: entry.range ?? record.range)
                continue
            }
            if entry.hasConstructorCallSyntax {
                reject("@JvmRecord cannot extend a class.", at: entry.range ?? record.range)
                continue
            }
            if let type = resolveTypeRef(
                entry.typeRef, ast: ast, symbols: symbols, types: resolutionContext.types,
                interner: interner, sourceManager: resolutionContext.sourceManager,
                relativeOwnerFQName: resolutionContext.enclosingFQName,
                currentPackageFQName: file.packageFQName, imports: file.imports
            ), case let .classType(classType) = resolutionContext.types.kind(of: type),
               let superSymbol = symbols.symbol(classType.classSymbol),
               superSymbol.kind == .class || superSymbol.kind == .enumClass || superSymbol.kind == .object {
                reject("@JvmRecord cannot extend a class.", at: entry.range ?? record.range)
            }
        }
        for propertyID in record.memberProperties {
            guard case let .propertyDecl(property) = ast.arena.decl(propertyID),
                  !property.isSynthesizedPrimaryConstructorProperty else { continue }
            if property.delegateExpression != nil || propertyAllowsFieldTarget(
                property, symbol: bindings.declSymbols[propertyID], symbols: symbols,
                validator: resolutionContext.propertyValidator, bindings: bindings
            ) {
                reject("@JvmRecord cannot declare additional instance fields.", at: property.range)
            }
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
        filesByID: [Int32: ASTFile],
        resolutionContext: AnnotationTargetResolutionContext
    ) {
        validateAnnotationRepeatability(
            annotations: param.annotations, file: file, symbols: symbols,
            diagnostics: diagnostics, interner: interner, resolutionContext: resolutionContext
        )
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
                filesByID: filesByID,
                resolutionContext: resolutionContext
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
        filesByID: [Int32: ASTFile],
        resolutionContext: AnnotationTargetResolutionContext
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
                filesByID: filesByID,
                resolutionContext: resolutionContext
            )
        }
    }

    private func annotationTypeParameters(in decl: Decl) -> [TypeParamDecl] {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.typeParams
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.typeParams
        case let .funDecl(function):
            function.typeParams
        case let .propertyDecl(property):
            property.typeParams
        case let .typeAliasDecl(typeAlias):
            typeAlias.typeParams
        case .objectDecl, .enumEntryDecl:
            []
        }
    }

    private func validateAnnotationRepeatability(
        annotations: [AnnotationNode],
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        resolutionContext: AnnotationTargetResolutionContext
    ) {
        guard annotations.count > 1 else { return }

        // A property and its accessors are separate annotation sites.
        var seenUseSitesByAnnotation: [SymbolID: Set<String>] = [:]
        for annotation in annotations {
            guard let annotationSymbolID = resolveAnnotationSymbol(
                named: annotation.name,
                in: file,
                symbols: symbols,
                interner: interner,
                types: resolutionContext.types,
                enclosingFQName: resolutionContext.enclosingFQName,
                lexicalEnclosingFQNames: resolutionContext.lexicalEnclosingFQNames
            ), symbols.symbol(annotationSymbolID)?.kind == .annotationClass else {
                continue
            }

            let useSiteTarget = annotation.useSiteTarget?.lowercased() ?? ""
            guard seenUseSitesByAnnotation[annotationSymbolID, default: []].insert(useSiteTarget).inserted else {
                let isRepeatable = symbols.annotations(for: annotationSymbolID).contains {
                    KnownCompilerAnnotation.repeatable.matches($0.annotationFQName)
                }
                if !isRepeatable {
                    diagnostics.error(
                        "KSWIFTK-SEMA-ANNOTATION-NOT-REPEATABLE",
                        "This annotation is not repeatable.",
                        range: annotation.constructionTokens?.first?.range
                    )
                }
                continue
            }
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
        resolutionContext: AnnotationTargetResolutionContext,
        isTopLevel: Bool = false
    ) {
        guard let annotationSymbolID = resolveAnnotationSymbol(
            named: annotation.name,
            in: file,
            symbols: symbols,
            interner: interner,
            types: resolutionContext.types,
            enclosingFQName: resolutionContext.enclosingFQName,
            lexicalEnclosingFQNames: resolutionContext.lexicalEnclosingFQNames
        ), let annotationSymbol = symbols.symbol(annotationSymbolID),
              annotationSymbol.kind == .annotationClass
        else {
            // An annotation name must resolve at every use site, including
            // declarations. Bundled stdlib sources can rely on annotations
            // omitted from the compiler's reduced surface, and built-in names
            // may be recognized by the compiler without a declaration.
            if resolutionContext.sourceManager?.origin(of: file.fileID)?.isBundledStdlib != true,
               !KnownCompilerAnnotation.isKnownBuiltInAnnotation(annotation.name) {
                diagnostics.error(
                    "KSWIFTK-SEMA-0022",
                    "Unresolved reference '\(annotation.name)'.",
                    range: annotation.constructionTokens?.first?.range ?? ownerRange
                )
            }
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
            symbols: symbols,
            propertyValidator: resolutionContext.propertyValidator,
            bindings: resolutionContext.bindings
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
        symbols: SymbolTable,
        propertyValidator: DeclarationPositionValidator,
        bindings: BindingTable
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
                  propertyAllowsFieldTarget(propertyDecl, symbol: propertySymbol, symbols: symbols,
                                            validator: propertyValidator, bindings: bindings)
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
                  propertyAllowsFieldTarget(propertyDecl, symbol: propertySymbol, symbols: symbols,
                                            validator: propertyValidator, bindings: bindings)
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
        case let .expression(isFunctionLiteral):
            return allowedTargets.contains("EXPRESSION") || (isFunctionLiteral && allowedTargets.contains("FUNCTION"))
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
        case .expression:
            return "an expression"
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

    private func propertyAllowsFieldTarget(
        _ propertyDecl: PropertyDecl,
        symbol: SymbolID?,
        symbols: SymbolTable,
        validator: DeclarationPositionValidator,
        bindings: BindingTable
    ) -> Bool {
        guard propertyDecl.receiverType == nil,
              propertyDecl.delegateExpression == nil,
              !propertyDecl.modifiers.contains(.abstract)
        else { return false }
        if let symbol {
            if symbols.symbol(symbol)?.flags.contains(.abstractType) == true { return false }
            if let owner = symbols.parentSymbol(for: symbol), symbols.symbol(owner)?.kind == .interface { return false }
        }
        if propertyDecl.explicitBackingField != nil { return true }
        let backingField = symbol.map { symbols.backingFieldSymbol(for: $0) ?? $0 }
        let usesBackingField: (ExprID) -> Bool = { expression in
            guard let backingField else { return false }
            return bindings.identifierSymbol(for: expression) == backingField
        }
        // Storage follows accessor semantics, independently of whether the
        // initializer appears here, in an init block, or in a constructor.
        return !validator.accessorHasBody(propertyDecl.getter)
            || (propertyDecl.isVar && !validator.accessorHasBody(propertyDecl.setter))
            || validator.accessorUsesBackingField(propertyDecl.getter, isBackingFieldReference: usesBackingField)
            || validator.accessorUsesBackingField(propertyDecl.setter, isBackingFieldReference: usesBackingField)
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
        case expression(isFunctionLiteral: Bool)
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
        filesByID: [Int32: ASTFile],
        resolutionContext: AnnotationTargetResolutionContext
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
                    filesByID: filesByID,
                    resolutionContext: resolutionContext
                )
            }
            let constructorParameters = classDecl.primaryConstructorParams
                + classDecl.secondaryConstructors.flatMap(\.valueParams)
            for param in constructorParameters {
                if let type = param.type {
                    validateTypeAnnotationTargets(typeRefID: type, ownerRange: classDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
                }
            }
        case let .interfaceDecl(interfaceDecl):
            for superType in interfaceDecl.superTypes {
                validateTypeAnnotationTargets(typeRefID: superType, ownerRange: interfaceDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
        case let .funDecl(funDecl):
            if let receiverType = funDecl.receiverType {
                validateTypeAnnotationTargets(typeRefID: receiverType, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
            for param in funDecl.valueParams {
                if let type = param.type {
                    validateTypeAnnotationTargets(typeRefID: type, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
                }
            }
            if let returnType = funDecl.returnType {
                validateTypeAnnotationTargets(typeRefID: returnType, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
        case let .propertyDecl(propertyDecl):
            if let receiverType = propertyDecl.receiverType {
                validateTypeAnnotationTargets(typeRefID: receiverType, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
            if let type = propertyDecl.type {
                validateTypeAnnotationTargets(typeRefID: type, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
            if let fieldType = propertyDecl.explicitBackingField?.type {
                validateTypeAnnotationTargets(typeRefID: fieldType, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
        case let .typeAliasDecl(typeAliasDecl):
            if let underlyingType = typeAliasDecl.underlyingType {
                validateTypeAnnotationTargets(typeRefID: underlyingType, ownerRange: typeAliasDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
        case let .objectDecl(objectDecl):
            for entry in objectDecl.superTypeEntries {
                validateTypeAnnotationTargets(
                    typeRefID: entry.typeRef, ownerRange: objectDecl.range,
                    file: file, ast: ast, symbols: symbols, diagnostics: diagnostics,
                    interner: interner, filesByID: filesByID, resolutionContext: resolutionContext
                )
            }
        case .enumEntryDecl:
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
        filesByID: [Int32: ASTFile],
        resolutionContext: AnnotationTargetResolutionContext
    ) {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return
        }

        switch typeRef {
        case let .named(_, args, _):
            for arg in args {
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    validateTypeAnnotationTargets(typeRefID: inner, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
                case .star:
                    break
                }
            }
        case let .functionType(_, receiver, params, returnType, _, _):
            if let receiver {
                validateTypeAnnotationTargets(typeRefID: receiver, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
            for param in params {
                validateTypeAnnotationTargets(typeRefID: param, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
            validateTypeAnnotationTargets(typeRefID: returnType, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
        case let .intersection(parts):
            for part in parts {
                validateTypeAnnotationTargets(typeRefID: part, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
            }
        case let .annotated(base, annotations):
            validateAnnotationRepeatability(
                annotations: annotations, file: file, symbols: symbols,
                diagnostics: diagnostics, interner: interner, resolutionContext: resolutionContext
            )
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
                    filesByID: filesByID,
                    resolutionContext: resolutionContext
                )
            }
            validateTypeAnnotationTargets(typeRefID: base, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID, resolutionContext: resolutionContext)
        }
    }
}
