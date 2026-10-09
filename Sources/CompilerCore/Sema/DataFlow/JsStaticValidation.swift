import Foundation

/// Validates Kotlin/JS `@JsStatic` source compatibility and preserves its
/// member intent without emitting JavaScript static entries.
extension DataFlowSemaPhase {
    func validateJsStaticDeclarations(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        globalOptInMarkerNames: [String]
    ) {
        for file in ast.sortedFiles {
            for annotation in file.annotations where isJsStaticAnnotation(
                annotation,
                in: file,
                symbols: symbols,
                interner: interner
            ) {
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
            for declID in file.topLevelDecls {
                validateJsStaticDeclaration(
                    declID,
                    isMember: false,
                    isClassCompanionMember: false,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }
        }
    }

    private func validateJsStaticDeclaration(
        _ declID: DeclID,
        isMember: Bool,
        isClassCompanionMember: Bool,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        globalOptInMarkerNames: [String]
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        var annotations = decl.annotations
        if case let .propertyDecl(property) = decl {
            annotations.append(contentsOf: property.getter?.annotations ?? [])
            annotations.append(contentsOf: property.setter?.annotations ?? [])
        }
        for annotation in annotations where isJsStaticAnnotation(
            annotation,
            in: file,
            symbols: symbols,
            interner: interner
        ) {
            validateExperimentalAnnotationOptIn(
                for: annotation,
                in: file,
                scopeSymbol: bindings.declSymbols[declID],
                range: decl.range,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                globalOptInMarkerNames: globalOptInMarkerNames
            )
        }
        validateJsStaticAnnotationArguments(
            in: decl,
            file: file,
            symbols: symbols,
            diagnostics: diagnostics,
            interner: interner
        )

        switch decl {
        case let .funDecl(function):
            guard function.annotations.contains(where: {
                isJsStaticAnnotation($0, in: file, symbols: symbols, interner: interner)
            }) else {
                return
            }
            validateJsStaticReceiver(
                isMember: isMember,
                isClassCompanionMember: isClassCompanionMember,
                range: function.range,
                diagnostics: diagnostics
            )
            let functionVisibility = bindings.declSymbols[declID]
                .flatMap { symbols.symbol($0)?.visibility }
                ?? visibility(from: function.modifiers)
            if functionVisibility != .public {
                diagnostics.error(
                    "KSWIFTK-SEMA-JS-STATIC-ON-NON-PUBLIC-MEMBER",
                    "Only public members of class companion objects can be annotated with '@JsStatic'.",
                    range: function.range
                )
            }

        case let .propertyDecl(property):
            let propertySymbol = bindings.declSymbols[declID]
            let propertyVisibility = propertySymbol.flatMap { symbols.symbol($0)?.visibility }
                ?? visibility(from: property.modifiers)

            var usages: [(annotation: AnnotationNode, site: JsStaticAnnotationSite)] = []
            for annotation in property.annotations {
                let site: JsStaticAnnotationSite?
                switch annotation.useSiteTarget?.lowercased() {
                case nil, "property": site = .property
                case "get": site = .getter
                case "set": site = .setter
                default: site = nil
                }
                if let site, !usages.contains(where: { $0.annotation == annotation && $0.site == site }) {
                    usages.append((annotation, site))
                }
            }
            for accessor in [property.getter, property.setter].compactMap({ $0 }) {
                let site: JsStaticAnnotationSite = accessor.kind == .getter ? .getter : .setter
                for annotation in accessor.annotations where !usages.contains(where: {
                    $0.annotation == annotation && $0.site == site
                }) {
                    usages.append((annotation, site))
                }
            }

            for usage in usages where isJsStaticAnnotation(
                usage.annotation,
                in: file,
                symbols: symbols,
                interner: interner
            ) {
                let range: SourceRange
                let annotatedVisibility: Visibility
                switch usage.site {
                case .property:
                    range = property.range
                    annotatedVisibility = minimumVisibility(
                        propertyVisibility,
                        getter: property.getter?.visibility,
                        setter: property.setter?.visibility
                    )
                case .getter:
                    range = property.getter?.range ?? property.range
                    annotatedVisibility = property.getter?.visibility ?? propertyVisibility
                case .setter:
                    range = property.setter?.range ?? property.range
                    annotatedVisibility = property.setter?.visibility ?? propertyVisibility
                }

                validateJsStaticReceiver(
                    isMember: isMember,
                    isClassCompanionMember: isClassCompanionMember,
                    range: range,
                    diagnostics: diagnostics
                )
                if annotatedVisibility != .public {
                    diagnostics.error(
                        "KSWIFTK-SEMA-JS-STATIC-ON-NON-PUBLIC-MEMBER",
                        "Only public members of class companion objects can be annotated with '@JsStatic'.",
                        range: range
                    )
                }
                if usage.site == .property, property.modifiers.contains(.const) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-JS-STATIC-ON-CONST",
                        "'@JsStatic' annotation is useless for const.",
                        range: range
                    )
                }
            }

        case let .classDecl(classDecl):
            validateJsStaticMembers(
                classDecl.memberFunctions + classDecl.memberProperties,
                inClassCompanion: false,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                globalOptInMarkerNames: globalOptInMarkerNames
            )
            let companion = classDecl.companionObject
            for nestedID in classDecl.nestedClasses + classDecl.nestedObjects where nestedID != companion {
                validateJsStaticDeclaration(
                    nestedID,
                    isMember: false,
                    isClassCompanionMember: false,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }
            if let companion {
                validateJsStaticDeclaration(
                    companion,
                    isMember: true,
                    isClassCompanionMember: true,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }

        case let .interfaceDecl(interfaceDecl):
            validateJsStaticMembers(
                interfaceDecl.memberFunctions + interfaceDecl.memberProperties,
                inClassCompanion: false,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                globalOptInMarkerNames: globalOptInMarkerNames
            )
            let companion = interfaceDecl.companionObject
            for nestedID in interfaceDecl.nestedClasses + interfaceDecl.nestedObjects where nestedID != companion {
                validateJsStaticDeclaration(
                    nestedID,
                    isMember: false,
                    isClassCompanionMember: false,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }
            if let companion {
                validateJsStaticDeclaration(
                    companion,
                    isMember: true,
                    isClassCompanionMember: true,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }

        case let .objectDecl(objectDecl):
            validateJsStaticMembers(
                objectDecl.memberFunctions + objectDecl.memberProperties,
                inClassCompanion: isClassCompanionMember,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                globalOptInMarkerNames: globalOptInMarkerNames
            )
            for nestedID in objectDecl.nestedClasses + objectDecl.nestedObjects {
                validateJsStaticDeclaration(
                    nestedID,
                    isMember: false,
                    isClassCompanionMember: false,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    globalOptInMarkerNames: globalOptInMarkerNames
                )
            }

        case .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    private func validateJsStaticMembers(
        _ members: [DeclID],
        inClassCompanion: Bool,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        globalOptInMarkerNames: [String]
    ) {
        for memberID in members {
            validateJsStaticDeclaration(
                memberID,
                isMember: true,
                isClassCompanionMember: inClassCompanion,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                globalOptInMarkerNames: globalOptInMarkerNames
            )
        }
    }

    private func validateJsStaticReceiver(
        isMember: Bool,
        isClassCompanionMember: Bool,
        range: SourceRange,
        diagnostics: DiagnosticEngine
    ) {
        guard isMember, !isClassCompanionMember else {
            return
        }
        diagnostics.error(
            "KSWIFTK-SEMA-JS-STATIC-NOT-IN-CLASS-COMPANION",
            "Only members of class companion objects can be annotated with '@JsStatic'.",
            range: range
        )
    }

    private func isJsStaticAnnotation(
        _ annotation: AnnotationNode,
        in file: ASTFile,
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
        return symbols.symbol(symbol)?.fqName.map(interner.resolve).joined(separator: ".") == "kotlin.js.JsStatic"
    }

    private func validateJsStaticAnnotationArguments(
        in decl: Decl,
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let annotations: [AnnotationNode]
        switch decl {
        case let .propertyDecl(property):
            annotations = property.annotations
                + (property.getter?.annotations ?? [])
                + (property.setter?.annotations ?? [])
        default:
            annotations = decl.annotations
        }

        var reported: [AnnotationNode] = []
        for annotation in annotations where !annotation.arguments.isEmpty && !reported.contains(annotation) {
            guard let symbol = resolveAnnotationSymbol(
                named: annotation.name,
                in: file,
                symbols: symbols,
                interner: interner
            ), let fqName = symbols.symbol(symbol)?.fqName.map(interner.resolve).joined(separator: ".")
            else {
                continue
            }

            let annotationName: String
            switch fqName {
            case "kotlin.js.JsStatic": annotationName = "JsStatic"
            case "kotlin.js.ExperimentalJsStatic": annotationName = "ExperimentalJsStatic"
            default: continue
            }
            reported.append(annotation)
            diagnostics.error(
                "KSWIFTK-SEMA-JS-ANNOTATION-TOO-MANY-ARGUMENTS",
                "Annotation '@\(annotationName)' does not accept arguments.",
                range: decl.range
            )
        }
    }

    private func minimumVisibility(
        _ visibility: Visibility,
        getter: Visibility?,
        setter: Visibility?
    ) -> Visibility {
        [visibility, getter ?? visibility, setter ?? visibility].first(where: { $0 != .public }) ?? .public
    }
}

private enum JsStaticAnnotationSite: Equatable {
    case property
    case getter
    case setter
}
