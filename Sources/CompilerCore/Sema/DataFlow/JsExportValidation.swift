import Foundation

/// Performs the native front-end portion of Kotlin/JS `@JsExport` checking.
/// This records and validates export intent; it does not emit JavaScript
/// module exports or unmangled JS entry points.
extension DataFlowSemaPhase {
    func validateJsExportDeclarations(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        globalOptInMarkerNames: [String]
    ) {
        var externalTypes: Set<SymbolID> = []
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                collectExternalTypeSymbols(
                    declID: declID,
                    ast: ast,
                    bindings: bindings,
                    into: &externalTypes
                )
            }
        }

        for file in ast.sortedFiles {
            for annotation in file.annotations {
                if let annotationSymbol = resolveAnnotationSymbol(
                    named: annotation.name,
                    in: file,
                    symbols: symbols,
                    interner: interner
                ), isJsExportAnnotationClass(annotationSymbol, symbols: symbols, interner: interner) {
                    validateExperimentalAnnotationOptIn(
                        for: annotation,
                        in: file,
                        scopeSymbol: nil,
                        range: file.range,
                        symbols: symbols,
                        diagnostics: diagnostics,
                        interner: interner,
                        globalOptInMarkerNames: globalOptInMarkerNames
                    )
                }
                validateJsExportAnnotationArguments(
                    annotation,
                    in: file,
                    range: file.range,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }

            let exportsFileDeclarations = file.annotations.contains { annotation in
                guard let annotationSymbol = resolveAnnotationSymbol(
                    named: annotation.name,
                    in: file,
                    symbols: symbols,
                    interner: interner
                ) else {
                    return false
                }
                return isJsExportAnnotationClass(annotationSymbol, symbols: symbols, interner: interner)
            }

            for declID in file.topLevelDecls {
                validateJsExportDeclaration(
                    declID: declID,
                    file: file,
                    isTopLevel: true,
                    exportsFileDeclarations: exportsFileDeclarations,
                    ast: ast,
                    bindings: bindings,
                    symbols: symbols,
                    types: types,
                    externalTypes: externalTypes,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }
        }
    }

    private func validateJsExportDeclaration(
        declID: DeclID,
        file: ASTFile,
        isTopLevel: Bool,
        exportsFileDeclarations: Bool,
        ast: ASTModule,
        bindings: BindingTable,
        symbols: SymbolTable,
        types: TypeSystem,
        externalTypes: Set<SymbolID>,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        globalOptInMarkerNames: [String]
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }

        for annotation in declarationAnnotations(for: decl) {
            if let annotationSymbol = resolveAnnotationSymbol(
                named: annotation.name,
                in: file,
                symbols: symbols,
                interner: interner
            ), isJsExportAnnotationClass(annotationSymbol, symbols: symbols, interner: interner) {
                validateExperimentalAnnotationOptIn(
                    for: annotation,
                    in: file,
                    scopeSymbol: bindings.declSymbols[declID],
                    range: jsExportAnnotationOwnerRange(for: decl),
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }
            validateJsExportAnnotationArguments(
                annotation,
                in: file,
                range: jsExportAnnotationOwnerRange(for: decl),
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        let symbolID = bindings.declSymbols[declID]
        let explicitlyExported = symbolID.map {
            symbols.annotations(for: $0).contains {
                $0.annotationFQName == "kotlin.js.JsExport"
            }
        } ?? false
        let isExported = explicitlyExported || (isTopLevel && exportsFileDeclarations)

        if isExported, let symbolID, let symbol = symbols.symbol(symbolID) {
            switch decl {
            case .funDecl:
                validateExportedFunction(
                    symbolID,
                    symbolName: interner.resolve(symbol.name),
                    symbols: symbols,
                    types: types,
                    externalTypes: externalTypes,
                    diagnostics: diagnostics,
                    interner: interner
                )
            case .propertyDecl:
                if let propertyType = symbols.propertyType(for: symbolID) {
                    validateExportedType(
                        propertyType,
                        position: "property '\(interner.resolve(symbol.name))'",
                        allowUnit: false,
                        symbols: symbols,
                        types: types,
                        externalTypes: externalTypes,
                        diagnostics: diagnostics,
                        range: symbol.declSite,
                        interner: interner
                    )
                }
            case .classDecl, .interfaceDecl, .objectDecl:
                validateExportedClassMembers(
                    of: symbolID,
                    symbols: symbols,
                    types: types,
                    externalTypes: externalTypes,
                    diagnostics: diagnostics,
                    interner: interner
                )
            case .typeAliasDecl, .enumEntryDecl:
                break
            }
        }

        for childID in nestedJsExportDeclarationIDs(in: decl) {
            validateJsExportDeclaration(
                declID: childID,
                file: file,
                isTopLevel: false,
                exportsFileDeclarations: false,
                ast: ast,
                bindings: bindings,
                symbols: symbols,
                types: types,
                externalTypes: externalTypes,
                diagnostics: diagnostics,
                interner: interner,
                globalOptInMarkerNames: globalOptInMarkerNames
            )
        }
    }

    private func validateJsExportAnnotationArguments(
        _ annotation: AnnotationNode,
        in file: ASTFile,
        range: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard !annotation.arguments.isEmpty,
              let annotationSymbol = resolveAnnotationSymbol(
                  named: annotation.name,
                  in: file,
                  symbols: symbols,
                  interner: interner
              ), let annotationFQName = symbols.symbol(annotationSymbol)?.fqName.map(interner.resolve).joined(separator: ".")
        else {
            return
        }

        let annotationName: String
        switch annotationFQName {
        case "kotlin.js.JsExport": annotationName = "JsExport"
        case "kotlin.js.ExperimentalJsExport": annotationName = "ExperimentalJsExport"
        default: return
        }

        diagnostics.error(
            "KSWIFTK-SEMA-JS-ANNOTATION-TOO-MANY-ARGUMENTS",
            "Annotation '@\(annotationName)' does not accept arguments.",
            range: range
        )
    }

    private func jsExportAnnotationOwnerRange(for decl: Decl) -> SourceRange {
        switch decl {
        case let .classDecl(value): value.range
        case let .interfaceDecl(value): value.range
        case let .objectDecl(value): value.range
        case let .funDecl(value): value.range
        case let .propertyDecl(value): value.range
        case let .typeAliasDecl(value): value.range
        case let .enumEntryDecl(value): value.range
        }
    }

    private func validateExportedClassMembers(
        of classSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        externalTypes: Set<SymbolID>,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for member in symbols.allSymbols()
            where symbols.parentSymbol(for: member.id) == classSymbol && member.visibility == .public
        {
            switch member.kind {
            case .constructor:
                guard let signature = symbols.functionSignature(for: member.id) else {
                    continue
                }
                for (index, parameterType) in signature.parameterTypes.enumerated() {
                    validateExportedType(
                        parameterType,
                        position: "constructor parameter \(index + 1) of '\(interner.resolve(member.name))'",
                        allowUnit: false,
                        symbols: symbols,
                        types: types,
                        externalTypes: externalTypes,
                        diagnostics: diagnostics,
                        range: member.declSite,
                        interner: interner
                    )
                }
            case .function:
                validateExportedFunction(
                    member.id,
                    symbolName: interner.resolve(member.name),
                    symbols: symbols,
                    types: types,
                    externalTypes: externalTypes,
                    diagnostics: diagnostics,
                    interner: interner
                )
            case .property:
                if let propertyType = symbols.propertyType(for: member.id) {
                    validateExportedType(
                        propertyType,
                        position: "property '\(interner.resolve(member.name))'",
                        allowUnit: false,
                        symbols: symbols,
                        types: types,
                        externalTypes: externalTypes,
                        diagnostics: diagnostics,
                        range: member.declSite,
                        interner: interner
                    )
                }
            default:
                continue
            }
        }
    }

    private func validateExportedFunction(
        _ function: SymbolID,
        symbolName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        externalTypes: Set<SymbolID>,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let symbol = symbols.symbol(function),
              let signature = symbols.functionSignature(for: function)
        else {
            return
        }

        if signature.isSuspend {
            diagnostics.error(
                "KSWIFTK-SEMA-JS-EXPORT-WRONG-DECLARATION",
                "Suspend function '\(symbolName)' cannot be exported to JavaScript.",
                range: symbol.declSite
            )
        }

        for (index, parameterType) in signature.parameterTypes.enumerated() {
            validateExportedType(
                parameterType,
                position: "parameter \(index + 1) of '\(symbolName)'",
                allowUnit: false,
                symbols: symbols,
                types: types,
                externalTypes: externalTypes,
                diagnostics: diagnostics,
                range: symbol.declSite,
                interner: interner
            )
        }
        validateExportedType(
            signature.returnType,
            position: "return type of '\(symbolName)'",
            allowUnit: true,
            symbols: symbols,
            types: types,
            externalTypes: externalTypes,
            diagnostics: diagnostics,
            range: symbol.declSite,
            interner: interner
        )
    }

    private func validateExportedType(
        _ type: TypeID,
        position: String,
        allowUnit: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        externalTypes: Set<SymbolID>,
        diagnostics: DiagnosticEngine,
        range: SourceRange?,
        interner: StringInterner
    ) {
        guard !isJavaScriptExportableType(
            type,
            allowUnit: allowUnit,
            symbols: symbols,
            types: types,
            externalTypes: externalTypes,
            interner: interner,
            visited: []
        ) else {
            return
        }
        diagnostics.warning(
            "KSWIFTK-SEMA-JS-EXPORT-NON-EXPORTABLE-TYPE",
            "The \(position) type '\(displayType(type, symbols: symbols, types: types, interner: interner))' is not exportable to JavaScript.",
            range: range
        )
    }

    private func isJavaScriptExportableType(
        _ type: TypeID,
        allowUnit: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        externalTypes: Set<SymbolID>,
        interner: StringInterner,
        visited: Set<TypeID>
    ) -> Bool {
        guard !visited.contains(type) else {
            return true
        }
        var nestedVisited = visited
        nestedVisited.insert(type)

        switch types.kind(of: type) {
        case .unit:
            return allowUnit
        case .nullableUnit, .nothing, .error, .kClassType, .intersection:
            return false
        case .any, .stringStruct, .typeParam:
            return true
        case let .primitive(primitive, _):
            switch primitive {
            case .boolean, .byte, .short, .int, .float, .double:
                return true
            case .char, .long, .uint, .ulong, .ubyte, .ushort:
                return false
            }
        case let .classType(classType):
            let fqn = symbols.symbol(classType.classSymbol)?.fqName.map(interner.resolve) ?? []
            let joinedName = fqn.joined(separator: ".")
            if ["kotlin.BooleanArray", "kotlin.ByteArray", "kotlin.ShortArray", "kotlin.IntArray",
                "kotlin.FloatArray", "kotlin.DoubleArray"].contains(joinedName)
            {
                return true
            }
            if joinedName == "kotlin.Array" {
                return classType.args.allSatisfy { argument in
                    guard let argumentType = exportedTypeArgument(argument) else {
                        return false
                    }
                    return isJavaScriptExportableType(
                        argumentType,
                        allowUnit: false,
                        symbols: symbols,
                        types: types,
                        externalTypes: externalTypes,
                        interner: interner,
                        visited: nestedVisited
                    )
                }
            }
            let isExported = symbols.annotations(for: classType.classSymbol).contains {
                $0.annotationFQName == "kotlin.js.JsExport"
            }
            guard isExported || externalTypes.contains(classType.classSymbol) else {
                return false
            }
            return classType.args.allSatisfy { argument in
                guard let argumentType = exportedTypeArgument(argument) else {
                    return false
                }
                return isJavaScriptExportableType(
                    argumentType,
                    allowUnit: false,
                    symbols: symbols,
                    types: types,
                    externalTypes: externalTypes,
                    interner: interner,
                    visited: nestedVisited
                )
            }
        case let .functionType(functionType):
            let allTypes = functionType.contextReceivers
                + (functionType.receiver.map { [$0] } ?? [])
                + functionType.params
            return allTypes.allSatisfy {
                isJavaScriptExportableType(
                    $0,
                    allowUnit: false,
                    symbols: symbols,
                    types: types,
                    externalTypes: externalTypes,
                    interner: interner,
                    visited: nestedVisited
                )
            } && isJavaScriptExportableType(
                functionType.returnType,
                allowUnit: true,
                symbols: symbols,
                types: types,
                externalTypes: externalTypes,
                interner: interner,
                visited: nestedVisited
            )
        }
    }

    private func exportedTypeArgument(_ argument: TypeArg) -> TypeID? {
        switch argument {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            nil
        }
    }

    private func displayType(
        _ type: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> String {
        switch types.kind(of: type) {
        case .unit: "Unit"
        case .nullableUnit: "Unit?"
        case .nothing: "Nothing"
        case .any: "Any"
        case .stringStruct: "String"
        case let .primitive(primitive, _): primitive.kotlinName
        case let .classType(classType):
            symbols.symbol(classType.classSymbol)?.fqName.map(interner.resolve).joined(separator: ".") ?? "<type>"
        case .typeParam: "type parameter"
        case .functionType: "function type"
        case .intersection: "intersection type"
        case .kClassType: "KClass"
        case .error: "<error>"
        }
    }

    private func isJsExportAnnotationClass(
        _ annotation: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        symbols.symbol(annotation)?.fqName.map(interner.resolve).joined(separator: ".") == "kotlin.js.JsExport"
    }

    private func collectExternalTypeSymbols(
        declID: DeclID,
        ast: ASTModule,
        bindings: BindingTable,
        into externalTypes: inout Set<SymbolID>
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        let isExternal: Bool = switch decl {
        case let .classDecl(value): value.modifiers.contains(.external)
        case let .interfaceDecl(value): value.modifiers.contains(.external)
        case let .objectDecl(value): value.modifiers.contains(.external)
        default: false
        }
        if isExternal, let symbol = bindings.declSymbols[declID] {
            externalTypes.insert(symbol)
        }
        for childID in nestedJsExportDeclarationIDs(in: decl) {
            collectExternalTypeSymbols(
                declID: childID,
                ast: ast,
                bindings: bindings,
                into: &externalTypes
            )
        }
    }

    private func nestedJsExportDeclarationIDs(in decl: Decl) -> [DeclID] {
        switch decl {
        case let .classDecl(value):
            value.memberFunctions + value.memberProperties + value.nestedClasses + value.nestedObjects
        case let .interfaceDecl(value):
            value.memberFunctions + value.memberProperties + value.nestedClasses + value.nestedObjects
        case let .objectDecl(value):
            value.memberFunctions + value.memberProperties + value.nestedClasses + value.nestedObjects
        default:
            []
        }
    }
}
