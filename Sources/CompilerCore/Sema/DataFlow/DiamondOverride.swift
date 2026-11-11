
extension DataFlowSemaPhase {
    private struct DiamondDispatchKey: Hashable, CustomStringConvertible {
        let name: InternedString
        // Member-extension overloads may differ only by their extension
        // receiver; nil for ordinary members, whose signature receiverType is
        // the dispatch receiver and would split one declaration per owner.
        let extensionReceiverType: TypeID?
        let contextReceiverTypes: [TypeID]
        let contextParameterTypes: [TypeID]
        let parameterTypes: [TypeID]
        let isSuspend: Bool
        /// Properties and functions share a name but never collide in JVM
        /// dispatch; keep them in separate key spaces.
        let isProperty: Bool

        var description: String {
            return "\(name):\(parameterTypes.count)"
        }
    }

    private struct DiamondImplementation {
        let implementationID: SymbolID
        let directInterfaceID: SymbolID
        let ownerInterfaceID: SymbolID
        let inheritanceDepth: Int
        let isConcrete: Bool
    }

    private struct DiamondConflict {
        let key: DiamondDispatchKey
        let providerIDs: [SymbolID]
        /// True when a concrete superclass member competes with an interface
        /// implementation; kotlinc reports "inherits multiple implementations"
        // instead of "inherits multiple interface methods" in that case.
        let involvesSuperclassImplementation: Bool
    }

    func validateDiamondOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedFiles: Set<FileID> = []
    ) {
        let declBySymbol = Dictionary(
            bindings.declSymbols.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        var visited = Set<DeclID>()
        for file in ast.sortedFiles where !importedFiles.contains(file.fileID) {
            for declID in file.topLevelDecls {
                validateDiamondOverridesForDecl(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    declBySymbol: declBySymbol,
                    visited: &visited,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
    }

    /// Local classes and anonymous objects live behind expression nodes whose
    /// member symbols are only bound during body type checking, so the
    /// header-time pass above cannot see them. TypeCheckSemaPhase calls this
    /// once bodies have been checked.
    func validateDeferredDiamondOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let declBySymbol = Dictionary(
            bindings.declSymbols.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        var visited = Set<DeclID>()
        for expr in ast.arena.exprs {
            let nestedDeclID: DeclID?
            switch expr {
            case let .objectLiteral(_, declID, _): nestedDeclID = declID
            case let .localNominalDecl(declID, _): nestedDeclID = declID
            default: nestedDeclID = nil
            }
            if let nestedDeclID {
                validateDiamondOverridesForDecl(
                    declID: nestedDeclID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    declBySymbol: declBySymbol,
                    visited: &visited,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
    }

    private func validateDiamondOverridesForDecl(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        declBySymbol: [SymbolID: DeclID],
        visited: inout Set<DeclID>,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard visited.insert(declID).inserted,
              let symbol = bindings.declSymbols[declID],
              let decl = ast.arena.decl(declID),
              let symbolInfo = symbols.symbol(symbol)
        else {
            return
        }

        recurseDiamondValidation(
            decl: decl, ast: ast, symbols: symbols,
            bindings: bindings, declBySymbol: declBySymbol,
            visited: &visited, diagnostics: diagnostics, interner: interner
        )

        // Kotlinc requires an override from every nominal kind that inherits a
        // conflicting pair: concrete and abstract classes, objects and even
        // interfaces. Abstract decls still escape the check when every provider
        // is abstract — such a collision produces no conflict below and stays
        // on the abstract-member path for concrete classes.
        guard symbolInfo.kind == .class || symbolInfo.kind == .object
                || symbolInfo.kind == .interface
        else {
            return
        }

        let conflicts = collectDiamondConflicts(
            for: symbol,
            symbols: symbols,
            declBySymbol: declBySymbol,
            ast: ast
        )
        guard !conflicts.isEmpty else { return }

        let overriddenKeys = collectDiamondOverrideKeys(
            for: decl,
            ownerSymbol: symbol,
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            interner: interner
        )

        emitDiamondDiagnostics(
            conflicts: conflicts,
            overriddenKeys: overriddenKeys,
            symbolInfo: symbolInfo,
            decl: decl,
            symbols: symbols,
            diagnostics: diagnostics,
            interner: interner
        )
    }

    private func recurseDiamondValidation(
        decl: Decl,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        declBySymbol: [SymbolID: DeclID],
        visited: inout Set<DeclID>,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        var nestedIDs: [DeclID] = []
        switch decl {
        case let .classDecl(classDecl):
            nestedIDs = classDecl.nestedClasses + classDecl.nestedObjects
            nestedIDs += [classDecl.companionObject, classDecl.companionBlockObject].compactMap { $0 }
        case let .interfaceDecl(ifaceDecl):
            nestedIDs = ifaceDecl.nestedClasses + ifaceDecl.nestedObjects
            nestedIDs += [ifaceDecl.companionObject, ifaceDecl.companionBlockObject].compactMap { $0 }
        case let .objectDecl(objectDecl):
            nestedIDs = objectDecl.nestedClasses + objectDecl.nestedObjects
        default: return
        }
        for nestedDeclID in nestedIDs {
            validateDiamondOverridesForDecl(
                declID: nestedDeclID, ast: ast, symbols: symbols,
                bindings: bindings, declBySymbol: declBySymbol,
                visited: &visited, diagnostics: diagnostics, interner: interner
            )
        }
    }

    /// Considers transitive interface inheritance and follows Kotlin's rules:
    /// 1. Only the most specific implementation (deepest override) for each method name
    /// 2. Conflicts occur only when multiple most specific implementations exist
    /// 3. Methods inherited from a common ancestor don't conflict if not overridden
    private func collectDiamondConflicts(
        for symbol: SymbolID,
        symbols: SymbolTable,
        declBySymbol: [SymbolID: DeclID],
        ast: ASTModule
    ) -> [DiamondConflict] {
        let directSupertypes = symbols.directSupertypes(for: symbol)
        let interfaceSupertypes = directSupertypes
            .filter { symbols.symbol($0)?.kind == .interface }
            .sorted(by: { $0.rawValue < $1.rawValue })

        let concreteSuperclassMembers = collectConcreteSuperclassMembers(
            for: symbol,
            symbols: symbols
        )

        // A single direct interface still conflicts when a concrete superclass
        // member supplies a competing implementation for the same signature.
        guard !interfaceSupertypes.isEmpty,
              interfaceSupertypes.count >= 2 || !concreteSuperclassMembers.isEmpty
        else { return [] }

        var mostSpecificImpls: [DiamondDispatchKey: [DiamondImplementation]] = [:]

        for directInterfaceID in interfaceSupertypes {
            var visited: Set<SymbolID> = []
            var queue: [(SymbolID, Int)] = [(directInterfaceID, 0)]

            while !queue.isEmpty {
                let (currentInterfaceID, depth) = queue.removeFirst()
                guard visited.insert(currentInterfaceID).inserted else { continue }
                guard symbols.symbol(currentInterfaceID) != nil else { continue }

                for childID in symbols.declaredChildren(of: currentInterfaceID) {
                    guard let childSym = symbols.symbol(childID),
                          childSym.kind == .function || childSym.kind == .property,
                          // Private interface members are not inherited, so
                          // they never compete in the diamond rule — same
                          // exclusion the superclass side already applies.
                          childSym.visibility != .private
                    else { continue }

                    let key = makeDiamondDispatchKey(for: childID, symbols: symbols)
                    mostSpecificImpls[key, default: []].append(DiamondImplementation(
                        implementationID: childID,
                        directInterfaceID: directInterfaceID,
                        ownerInterfaceID: currentInterfaceID,
                        inheritanceDepth: depth,
                        isConcrete: diamondProviderIsConcrete(
                            childID,
                            symbols: symbols,
                            declBySymbol: declBySymbol,
                            ast: ast
                        )
                    ))
                }

                let parentInterfaces = symbols.directSupertypes(for: currentInterfaceID)
                    .filter { symbols.symbol($0)?.kind == .interface }
                    .sorted(by: { $0.rawValue < $1.rawValue })

                queue.append(contentsOf: parentInterfaces.map { ($0, depth + 1) })
            }
        }

        let ownerInterfaceIDs = Set(mostSpecificImpls.values.flatMap { implementations in
            implementations.map(\.ownerInterfaceID)
        })
        let inheritedInterfacesByOwner = ownerInterfaceIDs.reduce(into: [SymbolID: Set<SymbolID>]()) {
            inheritedByOwner, ownerInterfaceID in
            inheritedByOwner[ownerInterfaceID] = inheritedInterfaceIDs(
                of: ownerInterfaceID,
                symbols: symbols
            )
        }

        var conflicts: [DiamondConflict] = []
        for (key, implementations) in mostSpecificImpls {
            // A declaration in a subinterface replaces the matching default
            // inherited from its parent, even when the class also lists that
            // parent interface directly. Such candidates are one override
            // chain, not an ambiguous pair of implementations.
            let effectiveImplementations = implementations.filter { candidate in
                !implementations.contains { other in
                    guard candidate.implementationID != other.implementationID,
                          let otherSymbol = symbols.symbol(other.implementationID),
                          otherSymbol.flags.contains(.overrideMember)
                    else {
                        return false
                    }
                    return inheritedInterfacesByOwner[other.ownerInterfaceID]?
                        .contains(candidate.ownerInterfaceID) == true
                }
            }
            guard !effectiveImplementations.isEmpty else { continue }

            let superclassMembers = concreteSuperclassMembers[key] ?? []
            // A superclass member that itself overrides the interface
            // declaration already resolves that implementation; only
            // uncovered interface defaults still compete with the class side.
            let uncoveredImplementations = effectiveImplementations.filter { implementation in
                !isCoveredBySuperclassImplementation(
                    implementation,
                    superclassMembers: superclassMembers,
                    symbols: symbols
                )
            }

            // Depth 0 means the direct interface provides the implementation,
            // which is more specific than defaults inherited from ancestors.
            let minDepth = uncoveredImplementations.map(\.inheritanceDepth).min() ?? 0
            let mostSpecific = uncoveredImplementations.filter { $0.inheritanceDepth == minDepth }

            var implGroups: [SymbolID: Set<SymbolID>] = [:]
            for implementation in mostSpecific {
                implGroups[implementation.implementationID, default: []].insert(implementation.directInterfaceID)
            }

            // A concrete superclass member plus any uncovered concrete
            // interface implementation is the "inherits multiple
            // implementations" case; it replaces the interface-methods
            // diagnostic for the same signature (kotlinc reports only the
            // former).
            let involvesSuperclassImplementation = !superclassMembers.isEmpty
                && uncoveredImplementations.contains(where: \.isConcrete)
            if involvesSuperclassImplementation {
                conflicts.append(DiamondConflict(
                    key: key,
                    providerIDs: superclassMembers + uncoveredImplementations.map(\.implementationID),
                    involvesSuperclassImplementation: true
                ))
                continue
            }

            if implGroups.count > 1 {
                let conflictingInterfaces = implGroups.values.reduce(into: Set<SymbolID>()) { acc, interfaces in
                    acc.formUnion(interfaces)
                }
                // An abstract-only collision is reported by the
                // abstract-member check instead; the diamond rule fires once
                // at least one side supplies a concrete implementation.
                if conflictingInterfaces.count >= 2,
                   mostSpecific.contains(where: \.isConcrete) {
                    conflicts.append(DiamondConflict(
                        key: key,
                        providerIDs: conflictingInterfaces.sorted(by: { $0.rawValue < $1.rawValue }),
                        involvesSuperclassImplementation: false
                    ))
                }
            }
        }

        return conflicts.sorted {
            if $0.key.name != $1.key.name {
                return $0.key.name.rawValue < $1.key.name.rawValue
            }
            if $0.key.parameterTypes.count != $1.key.parameterTypes.count {
                return $0.key.parameterTypes.count < $1.key.parameterTypes.count
            }
            return $0.providerIDs.lexicographicallyPrecedes($1.providerIDs, by: { $0.rawValue < $1.rawValue })
        }
    }

    /// The diamond rule arbitrates between competing Kotlin implementations.
    /// A provider is concrete only when it carries a real Kotlin body — a
    /// bodiless declaration (abstract member, `external` function or a
    /// `@KsSymbolName` runtime bridge) stays on the contract side even though
    /// header collection keeps such bridges non-abstract for dispatch.
    private func diamondProviderIsConcrete(
        _ implementationID: SymbolID,
        symbols: SymbolTable,
        declBySymbol: [SymbolID: DeclID],
        ast: ASTModule
    ) -> Bool {
        guard let info = symbols.symbol(implementationID),
              !info.flags.contains(.abstractType)
        else {
            return false
        }
        if let declID = declBySymbol[implementationID],
           let decl = ast.arena.decl(declID),
           case let .funDecl(funDecl) = decl {
            return funDecl.body != .unit
        }
        return symbols.externalLinkName(for: implementationID) == nil
    }

    private func emitDiamondDiagnostics(
        conflicts: [DiamondConflict],
        overriddenKeys: Set<DiamondDispatchKey>,
        symbolInfo: SemanticSymbol,
        decl: Decl,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let declRange = extractDeclRange(decl)
        let className = diamondDisplayName(for: symbolInfo.id, symbols: symbols, interner: interner)
        let kindKeyword: String
        switch symbolInfo.kind {
        case .interface: kindKeyword = "interface"
        case .object: kindKeyword = "object"
        default: kindKeyword = "class"
        }
        for conflict in conflicts {
            guard !overriddenKeys.contains(conflict.key) else {
                continue
            }
            let memberName = interner.resolve(conflict.key.name)
            let reason = conflict.involvesSuperclassImplementation
                ? "inherits multiple implementations for it."
                : "inherits multiple interface methods for it."
            let msg = "\(kindKeyword) '\(className)' must override '\(memberName)' "
                + "because it \(reason)"
            diagnostics.error("KSWIFTK-SEMA-0171", msg, range: declRange)
        }
    }

    /// Renders the nominal name the way kotlinc prints it: the package prefix
    /// is dropped while enclosing-declaration segments stay (`Outer.Inner`).
    private func diamondDisplayName(
        for symbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        // Anonymous object literals print as '<anonymous>' in kotlinc.
        if symbols.symbol(symbol)?.flags.contains(.objectLiteralType) == true {
            return "<anonymous>"
        }
        var segments: [String] = []
        var current: SymbolID? = symbol
        while let symbolID = current, let info = symbols.symbol(symbolID) {
            switch info.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                segments.append(interner.resolve(info.name))
                current = symbols.parentSymbol(for: symbolID)
            default:
                current = nil
            }
        }
        return segments.reversed().joined(separator: ".")
    }

    private func inheritedInterfaceIDs(
        of childInterfaceID: SymbolID,
        symbols: SymbolTable
    ) -> Set<SymbolID> {
        var visited: Set<SymbolID> = [childInterfaceID]
        var queue = symbols.directSupertypes(for: childInterfaceID)
        var inherited: Set<SymbolID> = []
        while !queue.isEmpty {
            let currentInterfaceID = queue.removeFirst()
            guard visited.insert(currentInterfaceID).inserted,
                  symbols.symbol(currentInterfaceID)?.kind == .interface
            else {
                continue
            }
            inherited.insert(currentInterfaceID)
            queue.append(contentsOf: symbols.directSupertypes(for: currentInterfaceID))
        }
        return inherited
    }

    private func collectDiamondOverrideKeys(
        for decl: Decl,
        ownerSymbol: SymbolID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        interner: StringInterner
    ) -> Set<DiamondDispatchKey> {
        var overriddenKeys: Set<DiamondDispatchKey> = []

        let memberFunctions: [DeclID]
        let memberProperties: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            memberFunctions = classDecl.memberFunctions
            memberProperties = classDecl.memberProperties
        case let .objectDecl(objectDecl):
            memberFunctions = objectDecl.memberFunctions
            memberProperties = objectDecl.memberProperties
        case let .interfaceDecl(interfaceDecl):
            memberFunctions = interfaceDecl.memberFunctions
            memberProperties = interfaceDecl.memberProperties
        default:
            return overriddenKeys
        }

        for memberDeclID in memberFunctions + memberProperties {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  let memberSymbol = bindings.declSymbols[memberDeclID]
            else {
                continue
            }
            let hasOverrideModifier: Bool
            switch memberDecl {
            case let .funDecl(funDecl):
                hasOverrideModifier = funDecl.modifiers.contains(.override)
            case let .propertyDecl(propertyDecl):
                hasOverrideModifier = propertyDecl.modifiers.contains(.override)
            default:
                hasOverrideModifier = false
            }
            guard hasOverrideModifier else { continue }
            overriddenKeys.insert(makeDiamondDispatchKey(for: memberSymbol, symbols: symbols))
        }

        // `ULongRange.isEmpty`/`UIntRange.isEmpty` are source-backed on the
        // bundled declarations. Both built-in declarations also implement
        // ClosedRange and OpenEndRange, so those concrete members resolve the
        // shared interface override while the nominal owners move to source.
        let unsignedRangeFQNames: Set<[InternedString]> = [
            [
                interner.intern("kotlin"),
                interner.intern("ranges"),
                interner.intern("ULongRange"),
            ],
            [
                interner.intern("kotlin"),
                interner.intern("ranges"),
                interner.intern("UIntRange"),
            ],
        ]
        if let ownerFQName = symbols.symbol(ownerSymbol)?.fqName,
           unsignedRangeFQNames.contains(ownerFQName) {
            let isEmptyName = interner.intern("isEmpty")
            for memberID in symbols.children(of: ownerSymbol) {
                guard let extensionSymbol = symbols.symbol(memberID) else { continue }
                guard extensionSymbol.kind == .function,
                      !extensionSymbol.flags.contains(.synthetic),
                      extensionSymbol.name == isEmptyName,
                      symbols.parentSymbolIfKnown(for: extensionSymbol.id) == ownerSymbol
                else {
                    continue
                }
                overriddenKeys.insert(makeDiamondDispatchKey(for: extensionSymbol.id, symbols: symbols))
            }
        }

        return overriddenKeys
    }

    private func collectConcreteSuperclassMembers(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> [DiamondDispatchKey: [SymbolID]] {
        var members: [DiamondDispatchKey: [SymbolID]] = [:]
        var visited: Set<SymbolID> = [symbol]
        var queue = symbols.directSupertypes(for: symbol)
            .filter {
                guard let superSym = symbols.symbol($0) else { return false }
                return superSym.kind == .class || superSym.kind == .enumClass || superSym.kind == .object
            }

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted,
                  symbols.symbol(current) != nil
            else {
                continue
            }

            for childID in symbols.declaredChildren(of: current) {
                guard let childSym = symbols.symbol(childID),
                      (childSym.kind == .function || childSym.kind == .property),
                      !childSym.flags.contains(.abstractType),
                      childSym.visibility != .private
                else {
                    continue
                }
                let key = makeDiamondDispatchKey(for: childID, symbols: symbols)
                if !(members[key] ?? []).contains(childID) {
                    members[key, default: []].append(childID)
                }
            }

            let nextSuperclasses = symbols.directSupertypes(for: current).filter {
                guard let superSym = symbols.symbol($0) else { return false }
                return superSym.kind == .class || superSym.kind == .enumClass || superSym.kind == .object
            }
            queue.append(contentsOf: nextSuperclasses)
        }

        return members
    }

    /// A superclass member resolves an interface implementation when it is
    /// itself an `override` whose owner inherits that interface — the same
    /// situation kotlinc accepts without a further override on the class
    /// (e.g. `open class S : ID { override fun f() }` then `class C : S(), ID`).
    private func isCoveredBySuperclassImplementation(
        _ implementation: DiamondImplementation,
        superclassMembers: [SymbolID],
        symbols: SymbolTable
    ) -> Bool {
        guard !superclassMembers.isEmpty else { return false }
        for memberID in superclassMembers {
            guard let memberSym = symbols.symbol(memberID),
                  memberSym.flags.contains(.overrideMember),
                  let ownerID = symbols.parentSymbol(for: memberID)
            else {
                continue
            }
            if transitiveInterfaceSupertypes(of: ownerID, symbols: symbols)
                .contains(implementation.ownerInterfaceID) {
                return true
            }
        }
        return false
    }

    /// All interfaces reachable through the full supertype graph. Unlike
    /// `inheritedInterfaceIDs` this keeps traversing through class supertypes,
    /// which matters when the override's owner inherits the interface via a
    /// superclass rather than declaring it directly.
    private func transitiveInterfaceSupertypes(
        of symbol: SymbolID,
        symbols: SymbolTable
    ) -> Set<SymbolID> {
        var visited: Set<SymbolID> = [symbol]
        var queue = symbols.directSupertypes(for: symbol)
        var inherited: Set<SymbolID> = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted,
                  let info = symbols.symbol(current)
            else {
                continue
            }
            if info.kind == .interface {
                inherited.insert(current)
            }
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }
        return inherited
    }

    private func makeDiamondDispatchKey(
        for methodSymbol: SymbolID,
        symbols: SymbolTable
    ) -> DiamondDispatchKey {
        let methodName = symbols.symbol(methodSymbol)?.name ?? InternedString(rawValue: -1)
        let signature = symbols.functionSignature(for: methodSymbol)
        let extensionReceiverType = symbols.memberExtensionOwnerSymbol(for: methodSymbol) != nil
            ? signature?.receiverType
            : nil
        return DiamondDispatchKey(
            name: methodName,
            extensionReceiverType: extensionReceiverType,
            contextReceiverTypes: signature?.contextReceiverTypes ?? [],
            contextParameterTypes: signature?.contextParameterTypes ?? [],
            parameterTypes: signature?.parameterTypes ?? [],
            isSuspend: signature?.isSuspend ?? false,
            isProperty: symbols.symbol(methodSymbol)?.kind == .property
        )
    }

    private func extractDeclRange(_ decl: Decl) -> SourceRange? {
        switch decl {
        case let .classDecl(classDecl): classDecl.range
        case let .objectDecl(objectDecl): objectDecl.range
        case let .interfaceDecl(interfaceDecl): interfaceDecl.range
        default: nil
        }
    }
}
