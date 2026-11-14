import Foundation

// CLASS-005: Validate open/final/override modifier constraints.
// In Kotlin, classes are final by default. Subclassing a non-open
// (non-abstract, non-sealed, non-interface) class is an error.
// Overriding a final member is an error. Hiding a parent member
// without the `override` modifier is an error.

/// Lightweight context to avoid passing many parameters.
struct OpenFinalOverrideContext {
    let ast: ASTModule
    let symbols: SymbolTable
    let bindings: BindingTable
    let types: TypeSystem
    let diagnostics: DiagnosticEngine
    let interner: StringInterner
    let compilationModuleFQN: InternedString
    /// Reverse of `bindings.declSymbols`, used to tell whether an inherited
    /// member's type came from inference (its declaration carries no
    /// annotation) or was spelled explicitly.
    let declBySymbol: [SymbolID: DeclID]
}

/// Selects which inherited members participate in an override type check.
/// Checks that ran during the header pass must skip parents whose type was
/// still an inference placeholder (`.explicitOnly`); the deferred pass then
/// re-checks exactly those pairs (`.inferredOnly`) once the inferred parent
/// types are published.
private enum OFOParentTypeFilter {
    case all
    case explicitOnly
    case inferredOnly
}

extension DataFlowSemaPhase {
    func validateOpenFinalOverride(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        compilationModuleName: String,
        precompiledFiles: Set<FileID> = []
    ) {
        let ctx = OpenFinalOverrideContext(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            compilationModuleFQN: interner.intern(compilationModuleName),
            declBySymbol: Dictionary(
                bindings.declSymbols.map { ($0.value, $0.key) },
                uniquingKeysWith: { first, _ in first }
            )
        )
        for file in ast.sortedFiles where !precompiledFiles.contains(file.fileID) {
            for declID in file.topLevelDecls {
                validateOFODecl(declID, ctx: ctx)
            }
        }
    }

    /// Expression-body overrides have placeholder return types during the
    /// header pass. Validate their covariance after type checking publishes the
    /// inferred signatures.
    func validateInferredOverrideReturnTypes(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        compilationModuleName: String
    ) {
        let ctx = OpenFinalOverrideContext(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            compilationModuleFQN: interner.intern(compilationModuleName),
            declBySymbol: Dictionary(
                bindings.declSymbols.map { ($0.value, $0.key) },
                uniquingKeysWith: { first, _ in first }
            )
        )

        var visited = Set<DeclID>()
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateInferredOverrideReturnTypes(in: declID, ctx: ctx, visited: &visited)
            }
        }
        // Object literals and local nominal declarations are not reachable
        // from topLevelDecls — their decls live behind expression nodes whose
        // members are bound lazily during body checking.
        for expr in ast.arena.exprs {
            switch expr {
            case let .objectLiteral(_, declID, _):
                if let declID {
                    validateInferredOverrideReturnTypes(in: declID, ctx: ctx, visited: &visited)
                }
            case let .localNominalDecl(declID, _):
                validateInferredOverrideReturnTypes(in: declID, ctx: ctx, visited: &visited)
            default:
                continue
            }
        }
    }

    private func validateInferredOverrideReturnTypes(
        in declID: DeclID,
        ctx: OpenFinalOverrideContext,
        visited: inout Set<DeclID>
    ) {
        guard visited.insert(declID).inserted,
              let declaration = ctx.ast.arena.decl(declID) else { return }

        let memberFunctions: [DeclID]
        let nestedDeclarations: [DeclID]
        switch declaration {
        case let .classDecl(classDecl):
            memberFunctions = classDecl.memberFunctions
            nestedDeclarations = classDecl.nestedClasses + classDecl.nestedObjects
                + (classDecl.companionObject.map { [$0] } ?? [])
            if let ownerSymbol = ctx.bindings.declSymbols[declID],
               ctx.symbols.symbol(ownerSymbol)?.kind == .enumClass
            {
                // Enum-entry body properties can infer their type from an
                // initializer or custom getter. Their header type is only a
                // placeholder, so check abstract completeness after body
                // type checking has published the inferred property types.
                validateEnumEntryAbstractCompleteness(
                    classDecl,
                    ownerSymbol: ownerSymbol,
                    ctx: ctx
                )
            }
            for entry in classDecl.enumEntries {
                for memberDeclID in entry.memberFunctions {
                    validateInferredOverrideReturnType(of: memberDeclID, ctx: ctx)
                    validateExplicitOverrideReturnTypeAgainstInferredParent(of: memberDeclID, ctx: ctx)
                }
                for nestedDeclID in entry.nestedClasses {
                    validateInferredOverrideReturnTypes(in: nestedDeclID, ctx: ctx, visited: &visited)
                }
            }
        case let .interfaceDecl(interfaceDecl):
            memberFunctions = interfaceDecl.memberFunctions
            nestedDeclarations = interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                + (interfaceDecl.companionObject.map { [$0] } ?? [])
        case let .objectDecl(objectDecl):
            memberFunctions = objectDecl.memberFunctions
            nestedDeclarations = objectDecl.nestedClasses + objectDecl.nestedObjects
        default:
            return
        }

        for memberDeclID in memberFunctions {
            validateInferredOverrideReturnType(of: memberDeclID, ctx: ctx)
            validateExplicitOverrideReturnTypeAgainstInferredParent(of: memberDeclID, ctx: ctx)
        }
        for nestedDeclID in nestedDeclarations {
            validateInferredOverrideReturnTypes(in: nestedDeclID, ctx: ctx, visited: &visited)
        }
    }

    private func validateInferredOverrideReturnType(
        of declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) {
        validateDeferredOverrideReturnType(
            of: declID,
            requireInferredReturn: true,
            parentFilter: .all,
            ctx: ctx
        )
    }

    /// `override fun f(): T` members checked at header time compared against
    /// the parent's placeholder when the parent return type was inferred.
    /// Re-check those pairs now that inference has published the real type.
    private func validateExplicitOverrideReturnTypeAgainstInferredParent(
        of declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) {
        validateDeferredOverrideReturnType(
            of: declID,
            requireInferredReturn: false,
            parentFilter: .inferredOnly,
            ctx: ctx
        )
    }

    private func validateDeferredOverrideReturnType(
        of declID: DeclID,
        requireInferredReturn: Bool,
        parentFilter: OFOParentTypeFilter,
        ctx: OpenFinalOverrideContext
    ) {
        guard case let .funDecl(function)? = ctx.ast.arena.decl(declID),
              (function.returnType == nil) == requireInferredReturn,
              function.modifiers.contains(.override),
              let memberSymbol = ctx.bindings.declSymbols[declID],
              let member = ctx.symbols.symbol(memberSymbol),
              let ownerSymbol = ctx.symbols.parentSymbol(for: memberSymbol),
              let signature = ctx.symbols.functionSignature(for: memberSymbol)
        else {
            return
        }
        if requireInferredReturn {
            guard case let .expr(bodyExprID, _) = function.body,
                  let bodyType = ctx.bindings.exprType(for: bodyExprID),
                  bodyType != ctx.types.errorType
            else { return }
        }

        let parent: OFOInheritedMember?
        if member.flags.contains(.memberExtension) {
            parent = findInheritedFunction(
                named: function.name,
                for: ownerSymbol,
                childMember: memberSymbol,
                requireMatchingSignature: true,
                ctx: ctx
            )
        } else {
            parent = findInheritedMember(
                named: function.name,
                for: ownerSymbol,
                symbols: ctx.symbols,
                kind: .function,
                parameterTypes: signature.parameterTypes,
                childMember: memberSymbol,
                types: ctx.types
            )
        }
        guard let parent,
              let parentSymbol = ctx.symbols.symbol(parent.memberID),
              isMemberOverridable(parentSymbol, parent: parent)
        else { return }

        if (member.flags.contains(.memberExtension) || parentSymbol.flags.contains(.memberExtension)),
           !overrideFunctionSignatureMatches(
               childMember: memberSymbol,
               parentMember: parent.memberID,
               childOwner: ownerSymbol,
               requireCovariantReturn: false,
               ctx: ctx
           ) {
            return
        }

        validateReturnTypeCovariance(
            childReturnType: signature.returnType,
            parentSymbol: parentSymbol,
            memberName: function.name,
            memberRange: function.range,
            ownerSymbol: ownerSymbol,
            parentFilter: parentFilter,
            ctx: ctx
        )
    }

    /// `override` properties whose type is inferred from an initializer,
    /// delegate, or custom getter (`override var x = ...`) still carry the
    /// `anyType` placeholder during the header pass, so the OFO property-type
    /// check skips them. Re-validate the inferred type against the overridden
    /// property once type checking has published the final property types.
    func validateInferredPropertyTypeOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        compilationModuleName: String
    ) {
        let ctx = OpenFinalOverrideContext(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            compilationModuleFQN: interner.intern(compilationModuleName),
            declBySymbol: Dictionary(
                bindings.declSymbols.map { ($0.value, $0.key) },
                uniquingKeysWith: { first, _ in first }
            )
        )

        var visited = Set<DeclID>()
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateInferredPropertyTypeOverrides(in: declID, ctx: ctx, visited: &visited)
            }
        }
        // Object literals and local nominal declarations are not reachable
        // from topLevelDecls — their decls live behind expression nodes whose
        // members are bound lazily during body checking.
        for expr in ast.arena.exprs {
            switch expr {
            case let .objectLiteral(_, declID, _):
                if let declID {
                    validateInferredPropertyTypeOverrides(in: declID, ctx: ctx, visited: &visited)
                }
            case let .localNominalDecl(declID, _):
                validateInferredPropertyTypeOverrides(in: declID, ctx: ctx, visited: &visited)
            default:
                continue
            }
        }
    }

    private func validateInferredPropertyTypeOverrides(
        in declID: DeclID,
        ctx: OpenFinalOverrideContext,
        visited: inout Set<DeclID>
    ) {
        guard visited.insert(declID).inserted,
              let declaration = ctx.ast.arena.decl(declID) else { return }

        let memberProperties: [DeclID]
        let nestedDeclarations: [DeclID]
        switch declaration {
        case let .classDecl(classDecl):
            memberProperties = classDecl.memberProperties
            nestedDeclarations = classDecl.nestedClasses + classDecl.nestedObjects
                + (classDecl.companionObject.map { [$0] } ?? [])
            for entry in classDecl.enumEntries {
                for memberDeclID in entry.memberProperties {
                    validateDeferredValVarMutabilityOverride(of: memberDeclID, ctx: ctx)
                    validateInferredPropertyTypeOverride(of: memberDeclID, ctx: ctx)
                    validateExplicitPropertyTypeOverrideAgainstInferredParent(of: memberDeclID, ctx: ctx)
                }
                for nestedDeclID in entry.nestedClasses {
                    validateInferredPropertyTypeOverrides(in: nestedDeclID, ctx: ctx, visited: &visited)
                }
            }
        case let .interfaceDecl(interfaceDecl):
            memberProperties = interfaceDecl.memberProperties
            nestedDeclarations = interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                + (interfaceDecl.companionObject.map { [$0] } ?? [])
        case let .objectDecl(objectDecl):
            memberProperties = objectDecl.memberProperties
            nestedDeclarations = objectDecl.nestedClasses + objectDecl.nestedObjects
        default:
            return
        }

        for memberDeclID in memberProperties {
            validateDeferredValVarMutabilityOverride(of: memberDeclID, ctx: ctx)
            validateInferredPropertyTypeOverride(of: memberDeclID, ctx: ctx)
            validateExplicitPropertyTypeOverrideAgainstInferredParent(of: memberDeclID, ctx: ctx)
        }
        for nestedDeclID in nestedDeclarations {
            validateInferredPropertyTypeOverrides(in: nestedDeclID, ctx: ctx, visited: &visited)
        }
    }

    /// `override var x: T` members checked at header time compared against
    /// the parent's placeholder when the parent property type was inferred.
    /// Re-check those pairs now that inference has published the real type —
    /// both for the missed rejection and for the resolved parent name in the
    /// diagnostic.
    private func validateExplicitPropertyTypeOverrideAgainstInferredParent(
        of declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) {
        guard case let .propertyDecl(prop)? = ctx.ast.arena.decl(declID),
              prop.type != nil,
              prop.modifiers.contains(.override),
              let memberSymbol = ctx.bindings.declSymbols[declID],
              let memberSym = ctx.symbols.symbol(memberSymbol),
              memberSym.kind == .property,
              let ownerSymbol = ctx.symbols.parentSymbol(for: memberSymbol),
              let childType = ctx.symbols.propertyType(for: memberSymbol),
              childType != ctx.types.errorType,
              !typeContainsAnyTypeParam(childType, types: ctx.types)
        else { return }

        // The header pass already reported when an explicit parent fails —
        // only report failures that are new against inferred parents.
        if firstPropertyTypeMismatch(
            memberName: prop.name,
            childType: childType,
            childIsVar: memberSym.flags.contains(.mutable),
            ownerSymbol: ownerSymbol,
            parentFilter: .explicitOnly,
            ctx: ctx
        ) != nil {
            return
        }

        checkPropertyTypeAgainstInherited(
            memberName: prop.name,
            memberRange: prop.range,
            childType: childType,
            childIsVar: memberSym.flags.contains(.mutable),
            ownerSymbol: ownerSymbol,
            parentFilter: .inferredOnly,
            ctx: ctx
        )
    }

    /// Header-time `validateValVarMutabilityOverride` skips pairs where the
    /// child's or parent's property type was inferred, because kotlinc renders
    /// the full property signatures in this diagnostic. Re-check those pairs
    /// now that inference has published both types.
    private func validateDeferredValVarMutabilityOverride(
        of declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) {
        guard case let .propertyDecl(prop)? = ctx.ast.arena.decl(declID),
              prop.modifiers.contains(.override),
              let memberSymbol = ctx.bindings.declSymbols[declID],
              let memberSym = ctx.symbols.symbol(memberSymbol),
              memberSym.kind == .property,
              !memberSym.flags.contains(.mutable),
              let ownerSymbol = ctx.symbols.parentSymbol(for: memberSymbol)
        else { return }

        validateValVarMutabilityOverride(
            memberName: prop.name,
            memberRange: prop.range,
            ownerSymbol: ownerSymbol,
            memberSymbol: memberSymbol,
            ctx: ctx,
            inferredOnly: true
        )
    }

    private func validateInferredPropertyTypeOverride(
        of declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) {
        guard case let .propertyDecl(prop)? = ctx.ast.arena.decl(declID),
              prop.type == nil,
              prop.modifiers.contains(.override),
              prop.initializer != nil || prop.delegateExpression != nil
                || prop.getter != nil,
              let memberSymbol = ctx.bindings.declSymbols[declID],
              let memberSym = ctx.symbols.symbol(memberSymbol),
              memberSym.kind == .property,
              let ownerSymbol = ctx.symbols.parentSymbol(for: memberSymbol),
              let childType = ctx.symbols.propertyType(for: memberSymbol),
              childType != ctx.types.errorType,
              !typeContainsAnyTypeParam(childType, types: ctx.types)
        else { return }

        checkPropertyTypeAgainstInherited(
            memberName: prop.name,
            memberRange: prop.range,
            childType: childType,
            childIsVar: memberSym.flags.contains(.mutable),
            ownerSymbol: ownerSymbol,
            parentFilter: .all,
            ctx: ctx
        )
    }

    /// Declarations bound lazily inside bodies — anonymous object literals
    /// (`object : A() { ... }`) and local nominal declarations (`class`,
    /// `interface`, named `object` in function/property bodies) — are never
    /// reached by the main OFO walk over `topLevelDecls`, so their members
    /// received no override validation at all: `override` on a nonexistent
    /// member, `val`-over-`var`, type-mismatched and hidden (missing
    /// `override`) members were all accepted. Run the same member checks
    /// once their symbols and types have been published.
    func validateBodyNestedDeclOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        compilationModuleName: String
    ) {
        let ctx = OpenFinalOverrideContext(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            compilationModuleFQN: interner.intern(compilationModuleName),
            declBySymbol: Dictionary(
                bindings.declSymbols.map { ($0.value, $0.key) },
                uniquingKeysWith: { first, _ in first }
            )
        )
        var visited = Set<DeclID>()
        for expr in ast.arena.exprs {
            switch expr {
            case let .objectLiteral(_, declID, _):
                if let declID {
                    validateBodyNestedDeclOverrides(in: declID, ctx: ctx, visited: &visited)
                }
            case let .localNominalDecl(declID, _):
                validateBodyNestedDeclOverrides(in: declID, ctx: ctx, visited: &visited)
            default:
                continue
            }
        }
    }

    private func validateBodyNestedDeclOverrides(
        in declID: DeclID,
        ctx: OpenFinalOverrideContext,
        visited: inout Set<DeclID>
    ) {
        guard visited.insert(declID).inserted,
              let ownerSymbol = ctx.bindings.declSymbols[declID],
              let decl = ctx.ast.arena.decl(declID),
              let info = extractDeclInfo(decl)
        else { return }

        validateMemberOverrides(info.memberFunctions, symbol: ownerSymbol, ctx: ctx)
        validateMemberOverrides(info.memberProperties, symbol: ownerSymbol, ctx: ctx)
        for nestedDeclID in info.nestedDecls {
            validateBodyNestedDeclOverrides(in: nestedDeclID, ctx: ctx, visited: &visited)
        }
    }

    private func validateOFODecl(
        _ declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) {
        guard let symbol = ctx.bindings.declSymbols[declID],
              let decl = ctx.ast.arena.decl(declID),
              ctx.symbols.symbol(symbol) != nil
        else {
            return
        }

        let info = extractDeclInfo(decl)
        guard let info else { return }

        for nestedID in info.nestedDecls {
            validateOFODecl(nestedID, ctx: ctx)
        }

        if let range = info.declRange {
            validateSupertypesAreOpen(
                symbol: symbol,
                declRange: range,
                ctx: ctx
            )
        }

        // DATA-CTOR: Validate that data class primary constructor params are all val/var.
        if case let .classDecl(classDecl) = decl,
           classDecl.modifiers.contains(.data) {
            validateDataClassConstructorParams(classDecl: classDecl, ctx: ctx)
            validateDataClassCopyVisibilityMigration(
                classDecl: classDecl,
                symbol: symbol,
                ctx: ctx
            )
        }

        validateMemberOverrides(
            info.memberFunctions,
            symbol: symbol,
            ctx: ctx
        )
        validateMemberOverrides(
            info.memberProperties,
            symbol: symbol,
            ctx: ctx
        )

        if case let .classDecl(classDecl) = decl,
           let ownerSym = ctx.symbols.symbol(symbol),
           ownerSym.kind == .enumClass {
            for entry in classDecl.enumEntries {
                validateEnumEntryMemberOverrides(
                    entry: entry,
                    ownerSymbol: symbol,
                    ctx: ctx
                )
                // Entry bodies are anonymous subclasses of the enum class:
                // their members hide or override the enum's own members and
                // everything the enum inherits, so they need the same member
                // checks as any other class body (KUU-4161). Member symbols
                // are parented to the entry's `.field` symbol, which the
                // inherited-member scans resolve to the enum class.
                let entryFQName = ownerSym.fqName + [entry.name]
                guard let entrySymbol = ctx.symbols.lookupAll(fqName: entryFQName).first(where: { candidate in
                    ctx.symbols.symbol(candidate)?.kind == .field
                        && ctx.symbols.parentSymbol(for: candidate) == symbol
                }) else {
                    continue
                }
                validateMemberOverrides(
                    entry.memberFunctions + entry.memberProperties,
                    symbol: entrySymbol,
                    ctx: ctx
                )
            }
        }

        if case let .interfaceDecl(interfaceDecl) = decl {
            validateInterfaceProtectedMembers(interfaceDecl, ctx: ctx)
        }
    }

    /// Every enum entry is a concrete variant of the enum class, so it must
    /// implement each abstract member that the enum class still owes.
    private func validateEnumEntryAbstractCompleteness(
        _ classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard let owner = ctx.symbols.symbol(ownerSymbol) else { return }
        let ownerName = owner.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")

        let declaredMemberDeclIDs = classDecl.memberFunctions + classDecl.memberProperties
        let declaredMembers = declaredMemberDeclIDs.compactMap { ctx.bindings.declSymbols[$0] }
        var requirements = declaredMembers.filter {
            ctx.symbols.symbol($0)?.flags.contains(.abstractType) == true
        }

        let inheritedRequirements = unimplementedAbstractMembers(
            for: ownerSymbol,
            overriddenMembers: [],
            delegatedInterfaces: ctx.symbols.delegatedInterfaces(forClass: ownerSymbol),
            symbols: ctx.symbols,
            types: ctx.types,
            interner: ctx.interner
        )
        for inherited in inheritedRequirements {
            let satisfyingDeclID = declaredMemberDeclIDs.first { declID in
                guard let member = ctx.bindings.declSymbols[declID] else { return false }
                return enumMemberOverridesAbstractMember(
                    member, inherited,
                    memberDeclID: declID,
                    ownerSymbol: ownerSymbol,
                    ctx: ctx
                )
            }
            if let satisfyingDeclID,
               let enumMember = ctx.bindings.declSymbols[satisfyingDeclID]
            {
                if ctx.symbols.symbol(enumMember)?.flags.contains(.abstractType) == true {
                    requirements.append(enumMember)
                }
            } else {
                requirements.append(inherited)
            }
        }

        var seenRequirements: Set<SymbolID> = []
        requirements = requirements.filter { seenRequirements.insert($0).inserted }

        for entry in classDecl.enumEntries {
            for requirement in requirements {
                guard !enumEntryImplementsAbstractMember(
                    requirement,
                    entry: entry,
                    ownerSymbol: ownerSymbol,
                    ctx: ctx
                ), let abstractMember = ctx.symbols.symbol(requirement)
                else {
                    continue
                }
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Enum entry '\(ownerName).\(ctx.interner.resolve(entry.name))' does not implement abstract member '\(ctx.interner.resolve(abstractMember.name))'.",
                    range: entry.range
                )
            }
        }
    }

    private func enumMemberOverridesAbstractMember(
        _ member: SymbolID,
        _ abstractMember: SymbolID,
        memberDeclID: DeclID,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        guard ctx.symbols.symbol(member)?.flags.contains(.overrideMember) == true else {
            return false
        }
        switch ctx.symbols.symbol(member)?.kind {
        case .function:
            return overrideFunctionSignatureMatches(
                childMember: member,
                parentMember: abstractMember,
                childOwner: ownerSymbol,
                requireCovariantReturn: false,
                ctx: ctx
            )
        case .property:
            let childTypeIsInferred: Bool
            if case let .propertyDecl(property) = ctx.ast.arena.decl(memberDeclID) {
                childTypeIsInferred = property.type == nil
            } else {
                childTypeIsInferred = false
            }
            return enumPropertyOverrideMatches(
                childMember: member,
                abstractMember: abstractMember,
                childOwner: ownerSymbol,
                childTypeIsInferred: childTypeIsInferred,
                ctx: ctx
            )
        default:
            return false
        }
    }

    /// Enum entry bodies subclass the enum class, so an entry member sees
    /// the enum class's own members plus everything it inherits as override
    /// targets — the same surface `validateOverrideTarget` scans for named
    /// owners, except `validateMemberOverrides` never runs on entry decls.
    /// Without this pass an entry could silently hide a supertype member
    /// without `override`, or spell `override` against nothing / against a
    /// final member (KUU-3748, KUU-4170).
    private func validateEnumEntryMemberOverrides(
        entry: EnumEntryDecl,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard let ownerSym = ctx.symbols.symbol(ownerSymbol) else { return }
        for memberDeclID in entry.memberFunctions + entry.memberProperties {
            guard let memberDecl = ctx.ast.arena.decl(memberDeclID),
                  let memberMeta = extractMemberMeta(
                      memberDecl,
                      declID: memberDeclID,
                      ctx: ctx
                  )
            else { continue }
            let candidates = enumEntryOverrideCandidates(
                memberName: memberMeta.name,
                memberDeclID: memberDeclID,
                ownerSymbol: ownerSymbol,
                ownerSym: ownerSym,
                ctx: ctx
            )
            if memberMeta.hasOverride {
                validateEnumEntryOverrideTarget(
                    candidates: candidates,
                    memberName: memberMeta.name,
                    memberRange: memberMeta.range,
                    memberDeclID: memberDeclID,
                    ownerSymbol: ownerSymbol,
                    ctx: ctx
                )
            } else if let parent = candidates.first {
                // A member spelled without `override` hides the nearest
                // signature-matching supertype member — the enum class's
                // own members are nearer than anything it inherits, which
                // is also the order kotlinc names them in (KUU-4170).
                let name = ctx.interner.resolve(memberMeta.name)
                let parentName = ctx.interner.resolve(parent.ownerName)
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-OVERRIDE",
                    "'\(name)' hides member of supertype '\(parentName)' "
                        + "and needs an 'override' modifier.",
                    range: memberMeta.range
                )
            }
        }
    }

    /// Signature-matching override candidates for an enum-entry member in
    /// nearest-first order: the enum class's own declared members (the
    /// entry's anonymous class subclasses the enum class) followed by
    /// everything the enum class inherits. Properties and functions are
    /// separate override namespaces (KUU-4106): a property can never
    /// target a same-named function and vice versa, and a same-named
    /// overload with a different signature is a different member.
    private func enumEntryOverrideCandidates(
        memberName: InternedString,
        memberDeclID: DeclID,
        ownerSymbol: SymbolID,
        ownerSym: SemanticSymbol,
        ctx: OpenFinalOverrideContext
    ) -> [OFOInheritedMember] {
        let memberSymbol = ctx.bindings.declSymbols[memberDeclID]
        guard let memberSym = memberSymbol.flatMap({ ctx.symbols.symbol($0) }),
              memberSym.kind == .function || memberSym.kind == .property
        else { return [] }
        let memberIsFunction = memberSym.kind == .function

        func signatureMatches(_ candidateID: SymbolID) -> Bool {
            guard let candidate = ctx.symbols.symbol(candidateID) else { return false }
            guard let memberSymbol else { return false }
            if memberIsFunction {
                guard candidate.kind == .function,
                      ctx.symbols.functionSignature(for: memberSymbol) != nil
                else { return false }
                return overrideFunctionSignatureMatches(
                    childMember: memberSymbol,
                    parentMember: candidateID,
                    childOwner: ownerSymbol,
                    requireCovariantReturn: false,
                    ctx: ctx
                )
            }
            guard candidate.kind == .property else { return false }
            return propertyMemberSignatureMatches(
                childMember: memberSymbol,
                parentMember: candidateID,
                childOwner: ownerSymbol,
                ctx: ctx
            )
        }

        var results: [OFOInheritedMember] = []
        var seen: Set<SymbolID> = []

        for childID in ctx.symbols.declaredChildren(of: ownerSymbol) {
            guard childID != memberSymbol,
                  let child = ctx.symbols.symbol(childID),
                  child.fqName == ownerSym.fqName + [child.name],
                  child.name == memberName,
                  child.kind == .function || child.kind == .property,
                  child.visibility != .private,
                  !child.flags.contains(.extensionMemberAlias)
            else { continue }
            // An expect-declared member only mirrors the name: judge the
            // match against the linked actual declaration instead.
            let resolvedChildID = resolveInheritedMember(childID, symbols: ctx.symbols)
            guard !seen.contains(resolvedChildID),
                  signatureMatches(resolvedChildID)
            else { continue }
            seen.insert(resolvedChildID)
            results.append(OFOInheritedMember(
                memberID: resolvedChildID,
                ownerName: ownerSym.name,
                ownerIsInterface: false
            ))
        }
        for parent in findAllInheritedMembers(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        ) {
            guard let parentSym = ctx.symbols.symbol(parent.memberID),
                  parentSym.visibility != .private,
                  !parentSym.flags.contains(.extensionMemberAlias),
                  !seen.contains(parent.memberID),
                  signatureMatches(parent.memberID)
            else { continue }
            seen.insert(parent.memberID)
            results.append(parent)
        }
        return results
    }

    /// An `override` in an enum entry body is invalid when it targets any
    /// non-overridable member reachable from the entry's anonymous class:
    /// the enum class's own members (the entry subclasses the enum class)
    /// plus the members it inherits. A single final match rejects the
    /// override even when another same-named overridable member exists,
    /// matching kotlinc ('X' in 'Y' is final and cannot be overridden).
    /// With no signature-matching target at all the override is reported
    /// as 'overrides nothing' under the same completeness gates
    /// `validateOverrideTarget` applies (KUU-4170).
    private func validateEnumEntryOverrideTarget(
        candidates: [OFOInheritedMember],
        memberName: InternedString,
        memberRange: SourceRange,
        memberDeclID: DeclID,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard !candidates.isEmpty else {
            let memberSym = ctx.bindings.declSymbols[memberDeclID]
                .flatMap { ctx.symbols.symbol($0) }
            if memberSym?.kind == .function {
                if hasSourceBackedInheritedFunction(
                    named: memberName,
                    for: ownerSymbol,
                    ctx: ctx
                ) || (hasCompleteInheritedMemberIndex(for: ownerSymbol, ctx: ctx)
                    && !hasInheritedFunctionNamesake(
                        named: memberName,
                        for: ownerSymbol,
                        ctx: ctx
                    )) {
                    diagnoseOverrideNothing(
                        memberName: memberName,
                        memberRange: memberRange,
                        ctx: ctx
                    )
                }
            } else if hasCompleteInheritedMemberIndex(for: ownerSymbol, ctx: ctx) {
                diagnoseOverrideNothing(
                    memberName: memberName,
                    memberRange: memberRange,
                    ctx: ctx
                )
            }
            return
        }
        for parent in candidates {
            guard let parentSym = ctx.symbols.symbol(parent.memberID),
                  !isMemberOverridable(parentSym, parent: parent)
            else { continue }
            let name = ctx.interner.resolve(memberName)
            let ownerName = ctx.interner.resolve(parent.ownerName)
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-FINAL",
                "'\(name)' in '\(ownerName)' is final and cannot be overridden.",
                range: memberRange
            )
            return
        }
    }

    /// Whether an enum entry's own member implements the abstract
    /// requirement. The `override` modifier is not required for the
    /// completeness verdict: a signature-matching member implements the
    /// member even when it merely hides it — the missing modifier is
    /// reported separately as 'hides member of supertype' (KUU-4170,
    /// matching kotlinc which emits no abstract-member error for
    /// `enum class E : I { A { fun g() {} } }`).
    private func enumEntryImplementsAbstractMember(
        _ abstractMember: SymbolID,
        entry: EnumEntryDecl,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        for memberDeclID in entry.memberFunctions {
            guard let memberDecl = ctx.ast.arena.decl(memberDeclID),
                  case .funDecl = memberDecl,
                  let member = ctx.bindings.declSymbols[memberDeclID],
                  ctx.symbols.symbol(member)?.flags.contains(.abstractType) != true,
                  overrideFunctionSignatureMatches(
                      childMember: member,
                      parentMember: abstractMember,
                      childOwner: ownerSymbol,
                      requireCovariantReturn: false,
                      ctx: ctx
                  )
            else {
                continue
            }
            return true
        }

        for memberDeclID in entry.memberProperties {
            guard let memberDecl = ctx.ast.arena.decl(memberDeclID),
                  case .propertyDecl = memberDecl,
                  let member = ctx.bindings.declSymbols[memberDeclID],
                  ctx.symbols.symbol(member)?.flags.contains(.abstractType) != true,
                  propertyMemberSignatureMatches(
                      childMember: member,
                      parentMember: abstractMember,
                      childOwner: ownerSymbol,
                      ctx: ctx
                  )
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Signature-level property match shared by enum-entry override
    /// validation and abstract completeness: name, kind, and override
    /// family (member extension vs regular member) plus identical
    /// extension receivers. The property type and mutability stay out —
    /// a `val x: String` spelling still matches `val x: Int`, with the
    /// type conflict reported by the override checks instead (KUU-4170).
    private func propertyMemberSignatureMatches(
        childMember: SymbolID,
        parentMember: SymbolID,
        childOwner: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        guard let child = ctx.symbols.symbol(childMember),
              child.kind == .property,
              let abstract = ctx.symbols.symbol(parentMember),
              abstract.kind == .property,
              child.name == abstract.name,
              let abstractView = abstractMemberViewFromClass(
                  parentMember,
                  for: childOwner,
                  symbols: ctx.symbols,
                  types: ctx.types
              ),
              (ctx.symbols.memberExtensionOwnerSymbol(for: childMember) != nil)
                == (abstractView.extensionReceiverType != nil)
        else {
            return false
        }
        let childReceiverTypes = abstractView.extensionReceiverType != nil
            ? (ctx.symbols.extensionPropertyReceiverType(for: childMember).map { [$0] } ?? [])
            : []
        let abstractReceiverTypes = abstractView.extensionReceiverType.map { [$0] } ?? []
        return methodIdentityParameterTypesMatch(
            candidateParameterTypes: childReceiverTypes,
            interfaceParameterTypes: abstractReceiverTypes,
            types: ctx.types
        )
    }

    private func enumPropertyOverrideMatches(
        childMember: SymbolID,
        abstractMember: SymbolID,
        childOwner: SymbolID,
        childTypeIsInferred: Bool,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        guard let child = ctx.symbols.symbol(childMember),
              child.kind == .property,
              let abstract = ctx.symbols.symbol(abstractMember),
              abstract.kind == .property,
              child.name == abstract.name,
              let abstractView = abstractMemberViewFromClass(
                  abstractMember,
                  for: childOwner,
                  symbols: ctx.symbols,
                  types: ctx.types
              ),
              (ctx.symbols.memberExtensionOwnerSymbol(for: childMember) != nil)
                == (abstractView.extensionReceiverType != nil)
        else {
            return false
        }

        let childReceiver = ctx.symbols.memberExtensionOwnerSymbol(for: childMember) != nil
            ? ctx.symbols.extensionPropertyReceiverType(for: childMember)
            : nil
        let childReceiverTypes = childReceiver.map { [$0] } ?? []
        let abstractReceiverTypes = abstractView.extensionReceiverType.map { [$0] } ?? []
        guard methodIdentityParameterTypesMatch(
            candidateParameterTypes: childReceiverTypes,
            interfaceParameterTypes: abstractReceiverTypes,
            types: ctx.types
        ) else {
            return false
        }

        let childIsMutable = child.flags.contains(.mutable)
        guard childIsMutable || !abstractView.isMutable else {
            return false
        }
        // An `override val x = …` whose type is inferred carries only the
        // `Any?` placeholder at this phase — inference runs during type
        // checking. The name + override modifier already establish the
        // implementation, matching the name-based accounting
        // unimplementedAbstractMembers applies to ordinary classes via
        // collectOverriddenMemberNames.
        if childTypeIsInferred {
            return true
        }
        guard let childType = ctx.symbols.propertyType(for: childMember) else {
            return false
        }
        if abstractView.isMutable {
            return childType == abstractView.resultType
        }
        if ctx.types.typeContainsAnyTypeParam(childType)
            || ctx.types.typeContainsAnyTypeParam(abstractView.resultType)
        {
            return childType == abstractView.resultType
        }
        return ctx.types.isSubtype(childType, abstractView.resultType)
    }

    private func validateDataClassConstructorParams(
        classDecl: ClassDecl,
        ctx: OpenFinalOverrideContext
    ) {
        for param in classDecl.primaryConstructorParams {
            guard !param.isProperty else { continue }
            // This parameter lacks val/var; emit error.
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-DATA-CTOR",
                "Primary constructor of data class must only have property ('val' / 'var') parameters.",
                range: classDecl.range
            )
        }
    }

    private func validateDataClassCopyVisibilityMigration(
        classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard classDecl.hasPrimaryConstructorSyntax,
              !dataClassUsesConsistentCopyVisibility(classDecl),
              !dataClassUsesExposedCopyVisibility(classDecl)
        else {
            return
        }

        let classSymbol = ctx.symbols.symbol(symbol)
        let constructorVisibility = primaryConstructorVisibility(
            for: classDecl,
            classSymbol: classSymbol
        )
        guard constructorVisibility != .public else {
            return
        }

        let className = classSymbol?.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            ?? ctx.interner.resolve(classDecl.name)
        let visibilityName = renderVisibility(constructorVisibility)
        ctx.diagnostics.warning(
            "KSWIFTK-SEMA-DATA-COPY-VISIBILITY",
            "Data class '\(className)' has a \(visibilityName) primary constructor; generated copy() remains public unless '@ConsistentCopyVisibility' or '@ExposedCopyVisibility' is applied.",
            range: classDecl.range
        )
    }

    private func renderVisibility(_ visibility: Visibility) -> String {
        switch visibility {
        case .public:
            "public"
        case .private:
            "private"
        case .internal:
            "internal"
        case .protected:
            "protected"
        }
    }

    private struct OFODeclInfo {
        let memberFunctions: [DeclID]
        let memberProperties: [DeclID]
        let nestedDecls: [DeclID]
        let declRange: SourceRange?
    }

    private func extractDeclInfo(
        _ decl: Decl
    ) -> OFODeclInfo? {
        switch decl {
        case let .classDecl(cls):
            OFODeclInfo(
                memberFunctions: cls.memberFunctions,
                memberProperties: cls.memberProperties,
                // `nestedObjects` already contains the synthetic companion
                // block object; `companionObject` is the named companion.
                nestedDecls: cls.nestedClasses + cls.nestedObjects
                    + cls.enumEntries.flatMap(\.nestedClasses)
                    + (cls.companionObject.map { [$0] } ?? []),
                declRange: cls.range
            )
        case let .objectDecl(obj):
            OFODeclInfo(
                memberFunctions: obj.memberFunctions,
                memberProperties: obj.memberProperties,
                nestedDecls: obj.nestedClasses + obj.nestedObjects,
                declRange: obj.range
            )
        case let .interfaceDecl(iface):
            OFODeclInfo(
                memberFunctions: iface.memberFunctions,
                memberProperties: iface.memberProperties,
                nestedDecls: iface.nestedClasses + iface.nestedObjects
                    + (iface.companionObject.map { [$0] } ?? []),
                declRange: iface.range
            )
        default:
            nil
        }
    }

    private func validateSupertypesAreOpen(
        symbol: SymbolID,
        declRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        validateSupertypesAreOpen(
            directSupertypes: ctx.symbols.directSupertypes(for: symbol),
            declRange: declRange,
            symbols: ctx.symbols,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
    }

    func validateSupertypesAreOpen(
        directSupertypes: [SymbolID],
        declRange: SourceRange,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for supertypeID in directSupertypes {
            guard let sup = symbols.symbol(supertypeID) else {
                continue
            }

            // STDLIB-DATA-014: Check if attempting to inherit from a data class
            if sup.flags.contains(.dataType) {
                let name = sup.fqName
                    .map { interner.resolve($0) }
                    .joined(separator: ".")
                diagnostics.error(
                    "KSWIFTK-SEMA-DATA-INHERIT",
                    "Cannot inherit from data class '\(name)'. Data classes cannot be inherited from.",
                    range: declRange
                )
                continue
            }

            if isSubclassable(sup, interner: interner) { continue }
            let name = sup.fqName
                .map { interner.resolve($0) }
                .joined(separator: ".")
            diagnostics.error(
                "KSWIFTK-SEMA-FINAL",
                "Cannot inherit from final class '\(name)'. "
                    + "Mark it as 'open' to allow subclassing.",
                range: declRange
            )
        }
    }

    private func isSubclassable(_ sym: SemanticSymbol, interner: StringInterner) -> Bool {
        // kotlin.Any is the root superclass and must stay subclassable even if
        // the imported metadata marks it as final.
        if sym.fqName.count == 2,
           interner.resolve(sym.fqName[0]) == "kotlin",
           interner.resolve(sym.fqName[1]) == "Any"
        {
            return true
        }
        if sym.kind == .interface { return true }
        if sym.flags.contains(.abstractType) { return true }
        if sym.flags.contains(.sealedType) { return true }
        if sym.flags.contains(.openType) { return true }
        return false
    }

    private func validateMemberOverrides(
        _ memberDeclIDs: [DeclID],
        symbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        for memberDeclID in memberDeclIDs {
            guard let memberDecl = ctx.ast.arena.decl(memberDeclID),
                  let memberSymbol = ctx.bindings.declSymbols[memberDeclID]
            else { continue }

            let memberMeta = extractMemberMeta(memberDecl, declID: memberDeclID, ctx: ctx)
            guard let memberMeta else { continue }

            validateModifierCombinations(
                memberMeta: memberMeta,
                ownerSymbol: symbol,
                ctx: ctx
            )

            if memberMeta.hasOverride {
                validateOverrideTarget(
                    memberDecl: memberDecl,
                    memberName: memberMeta.name,
                    memberRange: memberMeta.range,
                    overrideRange: memberMeta.overrideRange,
                    ownerSymbol: symbol,
                    memberSymbol: memberSymbol,
                    parameterTypes: memberMeta.parameterTypes,
                    returnType: memberMeta.returnType,
                    ctx: ctx
                )
                validateValVarMutabilityOverride(
                    memberName: memberMeta.name,
                    memberRange: memberMeta.range,
                    ownerSymbol: symbol,
                    memberSymbol: memberSymbol,
                    ctx: ctx
                )
                validatePropertyTypeOverride(
                    memberDecl: memberDecl,
                    ownerSymbol: symbol,
                    memberSymbol: memberSymbol,
                    ctx: ctx
                )
                validateOverrideOpenness(
                    memberMeta: memberMeta,
                    memberSymbol: memberSymbol,
                    ctx: ctx
                )
                validateVisibilityConstraints(
                    memberMeta: memberMeta,
                    ownerSymbol: symbol,
                    memberSymbol: memberSymbol,
                    ctx: ctx
                )
                validateOverrideAccessorVisibility(
                    memberDecl: memberDecl,
                    memberSymbol: memberSymbol,
                    ownerSymbol: symbol,
                    ctx: ctx
                )
                publishImplicitOverrideMemberVisibility(
                    memberMeta: memberMeta,
                    memberSymbol: memberSymbol,
                    ownerSymbol: symbol,
                    ctx: ctx
                )
            } else {
                validateMissingOverride(
                    memberName: memberMeta.name,
                    memberRange: memberMeta.range,
                    ownerSymbol: symbol,
                    memberSymbol: memberSymbol,
                    ctx: ctx
                )
            }
        }
    }

    private struct MemberMeta {
        let name: InternedString
        let range: SourceRange
        let hasOverride: Bool
        let hasOpen: Bool
        let parameterTypes: [TypeID]?
        let returnType: TypeID?
        let hasAbstract: Bool
        let hasFinal: Bool
        let visibility: Visibility
        /// True when the declaration spells a visibility modifier; an
        /// implicit-visibility `override` inherits its effective visibility
        /// from the overridden member instead (KUU-4159).
        let hasExplicitVisibility: Bool
        let isFunction: Bool
        let overrideRange: SourceRange?
    }

    private func extractMemberMeta(
        _ decl: Decl,
        declID: DeclID,
        ctx: OpenFinalOverrideContext
    ) -> MemberMeta? {
        switch decl {
        case let .funDecl(fun):
            // Only read the return type from the function signature when there
            // is an explicit return type annotation in the source. Expression-body
            // functions without an explicit annotation store `anyType` as a
            // placeholder at header-collection time (before type checking runs).
            // Using that placeholder would produce false KSWIFTK-SEMA-OVERRIDE-RETURN
            // diagnostics because `Any` is not a subtype of the parent's specific
            // return type (e.g. Unit, String). Covariance of such functions is
            // checked after TypeCheckSemaPhase publishes their inferred returns.
            let returnType: TypeID? = if fun.returnType != nil {
                ctx.bindings.declSymbols[declID]
                    .flatMap { ctx.symbols.functionSignature(for: $0)?.returnType }
            } else {
                nil
            }
            let parameterTypes = ctx.bindings.declSymbols[declID]
                .flatMap { ctx.symbols.functionSignature(for: $0)?.parameterTypes }
            return MemberMeta(
                name: fun.name,
                range: fun.range,
                hasOverride: fun.modifiers.contains(.override),
                hasOpen: fun.modifiers.contains(.open),
                parameterTypes: parameterTypes,
                returnType: returnType,
                hasAbstract: fun.modifiers.contains(.abstract),
                hasFinal: fun.modifiers.contains(.final),
                visibility: extractVisibility(from: fun.modifiers),
                hasExplicitVisibility: explicitVisibility(fun.modifiers) != nil,
                isFunction: true,
                overrideRange: fun.overrideKeywordRange
            )
        case let .propertyDecl(prop):
            return MemberMeta(
                name: prop.name,
                range: prop.range,
                hasOverride: prop.modifiers.contains(.override),
                hasOpen: prop.modifiers.contains(.open),
                parameterTypes: nil,
                returnType: nil,
                hasAbstract: prop.modifiers.contains(.abstract),
                hasFinal: prop.modifiers.contains(.final),
                visibility: extractVisibility(from: prop.modifiers),
                hasExplicitVisibility: explicitVisibility(prop.modifiers) != nil,
                isFunction: false,
                overrideRange: prop.overrideKeywordRange
            )
        default:
            return nil
        }
    }

    private func extractVisibility(from modifiers: Modifiers) -> Visibility {
        if modifiers.contains(.private) { return .private }
        if modifiers.contains(.protected) { return .protected }
        if modifiers.contains(.internal) { return .internal }
        if modifiers.contains(.public) { return .public }
        return .public // Default visibility
    }

    private func validateVisibilityConstraints(
        memberMeta: MemberMeta,
        ownerSymbol: SymbolID,
        memberSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard memberMeta.hasOverride else { return }

        let parent = findInheritedMember(
            named: memberMeta.name,
            for: ownerSymbol,
            symbols: ctx.symbols,
            kind: memberMeta.isFunction ? .function : .property,
            parameterTypes: memberMeta.parameterTypes,
            childMember: memberMeta.isFunction ? memberSymbol : nil,
            types: ctx.types
        )
        guard let parent else { return }
        guard let parentSym = ctx.symbols.symbol(parent.memberID) else { return }

        if memberMeta.isFunction {
            validateVisibilityExpansion(
                childVisibility: memberMeta.visibility,
                childOwnerSymbol: ownerSymbol,
                parentSymbol: parentSym,
                memberName: memberMeta.name,
                memberRange: memberMeta.range,
                ctx: ctx
            )
        } else {
            // KUU-4142: kotlinc has no member-level visibility diagnostic for
            // properties — an override property's declared visibility flows to
            // its accessors, and each accessor is compared against the
            // overridden accessor instead (KSWIFTK-SEMA-0478/0479). Only the
            // cross-module compatibility rules still apply at member level.
            validateModuleBoundaryCompatibility(
                childOwnerSymbol: ownerSymbol,
                parentSymbol: parentSym,
                memberName: memberMeta.name,
                memberRange: memberMeta.range,
                ctx: ctx
            )
        }
    }

    private func visibilityToString(_ visibility: Visibility) -> String {
        switch visibility {
        case .private: return "private"
        case .protected: return "protected"
        case .internal: return "internal"
        case .public: return "public"
        }
    }

    /// KUU-4142: kotlinc checks each accessor of an `override` property
    /// against the corresponding accessor of the overridden property and
    /// reports `cannot weaken access privilege`
    /// (`CANNOT_WEAKEN_ACCESS_PRIVILEGE`) for a strictly narrower visibility
    /// or `cannot change access privilege`
    /// (`CANNOT_CHANGE_ACCESS_PRIVILEGE`) for an unordered
    /// `protected`/`internal` pairing. A wider visibility stays legal, just
    /// like widening the member itself.
    ///
    /// The override accessor's effective visibility is its own modifier when
    /// spelled, otherwise the property's explicit visibility modifier, and —
    /// when neither is spelled — the base accessor's visibility it inherits,
    /// which is trivially equal and reports nothing. Because a property's
    /// declared visibility flows to its accessors, this check also covers the
    /// member-level narrowing kotlinc reports for `protected override` style
    /// declarations (which likewise say `for 'accessor'`).
    private func validateOverrideAccessorVisibility(
        memberDecl: Decl,
        memberSymbol: SymbolID,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard case let .propertyDecl(prop) = memberDecl,
              prop.modifiers.contains(.override)
        else {
            return
        }
        guard let parent = findInheritedMember(
            named: prop.name,
            for: ownerSymbol,
            symbols: ctx.symbols,
            kind: .property
        ), let parentSym = ctx.symbols.symbol(parent.memberID) else {
            return
        }

        // KUU-4152: a `var` with no setter modifier inherits its effective
        // setter visibility — the property's own modifier when spelled,
        // otherwise the overridden setter's. Persist it on the member symbol
        // so use-site accessibility checks (and serialized metadata) see the
        // visibility the declaration-side rule resolves, instead of the
        // default-public accessor descriptor header collection produced.
        if prop.isVar, prop.setter?.visibility == nil,
           let effectiveSetterVisibility = implicitOverrideSetterVisibility(
               propertyDecl: prop,
               ownerSymbol: ownerSymbol,
               declBySymbol: ctx.declBySymbol,
               ast: ctx.ast,
               symbols: ctx.symbols
           )
        {
            ctx.symbols.setPropertySetterVisibility(effectiveSetterVisibility, for: memberSymbol)
        }

        let baseOwnerName = ctx.interner.resolve(parent.ownerName)
        let baseIsMutable: Bool
        if let baseDeclID = ctx.declBySymbol[parent.memberID],
           case let .propertyDecl(baseProp) = ctx.ast.arena.decl(baseDeclID)
        {
            baseIsMutable = baseProp.isVar
        } else {
            baseIsMutable = parentSym.flags.contains(.mutable)
        }

        var pending: [(code: String, message: String, range: SourceRange)] = []
        func consider(_ accessor: PropertyAccessorDecl?, isSetter: Bool) {
            // A fully implicit accessor — no own modifier and no explicit
            // property modifier — inherits the base accessor's visibility, so
            // it is equal by construction and there is nothing to report.
            guard let childVisibility = accessor?.visibility
                ?? explicitVisibility(prop.modifiers)
            else {
                return
            }
            guard let baseVisibility = effectiveBaseAccessorVisibility(
                of: parent.memberID,
                isSetter: isSetter,
                visited: [],
                declBySymbol: ctx.declBySymbol,
                ast: ctx.ast,
                symbols: ctx.symbols
            ) else {
                return
            }
            let code: String
            let verb: String
            switch compareOverrideVisibilities(childVisibility, baseVisibility) {
            case let order? where order < 0:
                code = "KSWIFTK-SEMA-0478"
                verb = "weaken"
            case nil:
                code = "KSWIFTK-SEMA-0479"
                verb = "change"
            default:
                return
            }
            let candidate = (
                code: code,
                message: "cannot \(verb) access privilege \(visibilityToString(childVisibility)) for 'accessor' in '\(baseOwnerName)'.",
                range: accessor?.range ?? prop.range
            )
            // kotlinc deduplicates diagnostics that share position, factory,
            // and arguments — `internal override var` on a public base, for
            // example, reports once even though both implicit accessors
            // weaken at the same modifier.
            if !pending.contains(where: {
                $0.code == candidate.code && $0.message == candidate.message && $0.range == candidate.range
            }) {
                pending.append(candidate)
            }
        }

        consider(prop.getter, isSetter: false)
        // A `val` child has no setter; a `val` base offers no setter to
        // override, so an added setter is never compared against it.
        if prop.isVar, baseIsMutable {
            consider(prop.setter, isSetter: true)
        }
        for diagnostic in pending {
            ctx.diagnostics.error(diagnostic.code, diagnostic.message, range: diagnostic.range)
        }
    }

    /// KUU-4152: the visibility an `override` property's implicit setter
    /// effectively carries — the property's own explicit modifier when
    /// spelled, otherwise the visibility the overridden setter accessor
    /// carries up the override chain. Returns nil when no overridden member
    /// resolves, leaving the descriptor's default visibility in place.
    /// Shared by the declaration-side check and by local/anonymous member
    /// header collection, whose symbols are created before the deferred
    /// body-nested override validation runs.
    func implicitOverrideSetterVisibility(
        propertyDecl prop: PropertyDecl,
        ownerSymbol: SymbolID,
        declBySymbol: [SymbolID: DeclID],
        ast: ASTModule,
        symbols: SymbolTable
    ) -> Visibility? {
        if let explicit = explicitVisibility(prop.modifiers) {
            return explicit
        }
        guard let parent = findInheritedMember(
            named: prop.name,
            for: ownerSymbol,
            symbols: symbols,
            kind: .property
        ) else {
            return nil
        }
        return effectiveBaseAccessorVisibility(
            of: parent.memberID,
            isSetter: true,
            visited: [],
            declBySymbol: declBySymbol,
            ast: ast,
            symbols: symbols
        )
    }

    /// KUU-4159: an `override` member that spells no visibility modifier
    /// inherits the overridden member's effective visibility — kotlinc
    /// resolves `override fun f()` over a `protected` base member as
    /// `protected`, and use sites reject accesses the inherited visibility
    /// does not permit. Publish the resolved value onto the member symbol so
    /// every use-site reader of `symbol.visibility` sees it; a member with an
    /// explicit modifier keeps its declared visibility untouched.
    private func publishImplicitOverrideMemberVisibility(
        memberMeta: MemberMeta,
        memberSymbol: SymbolID,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard !memberMeta.hasExplicitVisibility,
              let effective = implicitOverrideMemberVisibility(
                  kind: memberMeta.isFunction ? .function : .property,
                  name: memberMeta.name,
                  ownerSymbol: ownerSymbol,
                  parameterTypes: memberMeta.parameterTypes,
                  declBySymbol: ctx.declBySymbol,
                  ast: ctx.ast,
                  symbols: ctx.symbols,
                  childMember: memberMeta.isFunction ? memberSymbol : nil,
                  types: ctx.types
              ),
              ctx.symbols.symbol(memberSymbol)?.visibility != effective
        else {
            return
        }
        ctx.symbols.setVisibility(effective, for: memberSymbol)
    }

    /// KUU-4159: the visibility an `override` member effectively carries when
    /// its declaration spells no visibility modifier — the overridden
    /// member's effective visibility up the override chain. Returns nil when
    /// no overridden member resolves, leaving the descriptor's stored
    /// visibility in place. Shared by the declaration-side override
    /// validation and by local/anonymous member header collection, whose
    /// symbols are created before the deferred body-nested validation runs.
    func implicitOverrideMemberVisibility(
        kind: SymbolKind,
        name: InternedString,
        ownerSymbol: SymbolID,
        parameterTypes: [TypeID]?,
        declBySymbol: [SymbolID: DeclID],
        ast: ASTModule,
        symbols: SymbolTable,
        childMember: SymbolID? = nil,
        types: TypeSystem? = nil
    ) -> Visibility? {
        guard let parent = findInheritedMember(
            named: name,
            for: ownerSymbol,
            symbols: symbols,
            kind: kind,
            parameterTypes: parameterTypes,
            childMember: childMember,
            types: types
        ) else {
            return nil
        }
        return effectiveBaseMemberVisibility(
            of: parent.memberID,
            visited: [],
            declBySymbol: declBySymbol,
            ast: ast,
            symbols: symbols,
            types: types
        )
    }

    /// The visibility `symbolID`'s member effectively carries at member
    /// level: its declaration's own modifier when spelled, else — for an
    /// `override` that repeats none — the visibility inherited from the next
    /// base member up the override chain. Members with no source decl
    /// (imported, synthetic) carry the effective visibility their descriptor
    /// already stored.
    private func effectiveBaseMemberVisibility(
        of symbolID: SymbolID,
        visited: Set<SymbolID>,
        declBySymbol: [SymbolID: DeclID],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem? = nil
    ) -> Visibility? {
        guard !visited.contains(symbolID),
              let symbol = symbols.symbol(symbolID)
        else {
            return nil
        }
        guard let declID = declBySymbol[symbolID],
              let decl = ast.arena.decl(declID)
        else {
            return symbol.visibility
        }
        let modifiers: Modifiers
        switch decl {
        case let .funDecl(fun):
            modifiers = fun.modifiers
        case let .propertyDecl(prop):
            modifiers = prop.modifiers
        default:
            return symbol.visibility
        }
        if let explicit = explicitVisibility(modifiers) {
            return explicit
        }
        guard modifiers.contains(.override) else {
            return symbol.visibility
        }
        guard let ownerID = symbols.parentSymbol(for: symbolID),
              let next = findInheritedMember(
                  named: symbol.name,
                  for: ownerID,
                  symbols: symbols,
                  kind: symbol.kind,
                  parameterTypes: symbol.kind == .function
                      ? symbols.functionSignature(for: symbolID)?.parameterTypes
                      : nil,
                  childMember: symbol.kind == .function ? symbolID : nil,
                  types: types
              )
        else {
            return symbol.visibility
        }
        return effectiveBaseMemberVisibility(
            of: next.memberID,
            visited: visited.union([symbolID]),
            declBySymbol: declBySymbol,
            ast: ast,
            symbols: symbols,
            types: types
        )
    }

    /// The visibility an accessor of `symbolID`'s property effectively
    /// carries: its own modifier when spelled, else the property's explicit
    /// modifier, else — for an `override` that repeats neither — the
    /// visibility inherited from the next base accessor up the override
    /// chain. Members with no source decl (imported, synthetic) read the
    /// accessor visibility their descriptor stored, defaulting to the
    /// member's own visibility.
    private func effectiveBaseAccessorVisibility(
        of symbolID: SymbolID,
        isSetter: Bool,
        visited: Set<SymbolID>,
        declBySymbol: [SymbolID: DeclID],
        ast: ASTModule,
        symbols: SymbolTable
    ) -> Visibility? {
        guard !visited.contains(symbolID),
              let symbol = symbols.symbol(symbolID)
        else {
            return nil
        }
        guard let declID = declBySymbol[symbolID],
              case let .propertyDecl(prop) = ast.arena.decl(declID)
        else {
            if isSetter {
                return symbols.propertySetterVisibility(for: symbolID) ?? symbol.visibility
            }
            return symbol.visibility
        }
        let accessor = isSetter ? prop.setter : prop.getter
        if let explicit = accessor?.visibility {
            return explicit
        }
        if let explicit = explicitVisibility(prop.modifiers) {
            return explicit
        }
        guard prop.modifiers.contains(.override) else {
            return .public
        }
        guard let ownerID = symbols.parentSymbol(for: symbolID),
              let next = findInheritedMember(
                  named: prop.name,
                  for: ownerID,
                  symbols: symbols,
                  kind: .property
              )
        else {
            return symbol.visibility
        }
        return effectiveBaseAccessorVisibility(
            of: next.memberID,
            isSetter: isSetter,
            visited: visited.union([symbolID]),
            declBySymbol: declBySymbol,
            ast: ast,
            symbols: symbols
        )
    }

    /// The visibility spelled by a modifier set, or nil when no visibility
    /// modifier is present — distinct from `extractVisibility(from:)`, which
    /// defaults the absent case to `.public` for member-level checks.
    private func explicitVisibility(_ modifiers: Modifiers) -> Visibility? {
        if modifiers.contains(.private) { return .private }
        if modifiers.contains(.protected) { return .protected }
        if modifiers.contains(.internal) { return .internal }
        if modifiers.contains(.public) { return .public }
        return nil
    }

    /// Kotlin's `Visibilities.compare`: `private` is narrower than every
    /// visibility and `public` wider than every visibility, while `protected`
    /// and `internal` are unordered relative to each other (nil result).
    /// Negative means the child is the narrower visibility.
    private func compareOverrideVisibilities(_ child: Visibility, _ base: Visibility) -> Int? {
        if child == base { return 0 }
        if child == .private { return -1 }
        if base == .private { return 1 }
        if child == .public { return 1 }
        if base == .public { return -1 }
        return nil
    }

    private func validateModifierCombinations(
        memberMeta: MemberMeta,
        ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        // STDLIB-INHERIT-018: Validate that modifier combinations follow Kotlin rules

        let memberName = ctx.interner.resolve(memberMeta.name)

        // Rule 2: open and final are mutually exclusive
        if memberMeta.hasOverride && memberMeta.hasFinal {
            // This is actually valid (final override), so no error here
            // final override is allowed and means "override but don't allow further overriding"
        }

        // Rule 3: Check for invalid modifier combinations based on context
        guard let ownerSym = ctx.symbols.symbol(ownerSymbol) else { return }

        // Rule 3a: abstract members require an abstract owner, even if the class is open.
        // Interfaces and enum classes can declare abstract members without an abstract modifier.
        if memberMeta.hasAbstract,
           !ownerSym.flags.contains(.abstractType),
           ownerSym.kind != .interface,
           ownerSym.kind != .enumClass {
            let ownerName = ownerSym.fqName.last.map { ctx.interner.resolve($0) }
                ?? ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            let memberKindWord = memberMeta.isFunction ? "function" : "property"
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "abstract \(memberKindWord) '\(memberName)' in non-abstract class '\(ownerName)'.",
                range: memberMeta.range
            )
        }

        // Rule 3c: Check interface-specific constraints
        if ownerSym.kind == .interface {
            // Interface members cannot be final
            if memberMeta.hasFinal {
                let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                    "'\(memberName)' cannot be final in interface '\(ownerName)'. Interface members cannot be final.",
                    range: memberMeta.range
                )
            }

            // Interface members are implicitly abstract, but explicit abstract is redundant
            if memberMeta.hasAbstract {
                let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                ctx.diagnostics.warning(
                    "KSWIFTK-SEMA-REDUNDANT-MODIFIER",
                    "'\(memberName)' in interface '\(ownerName)' is implicitly abstract. 'abstract' modifier is redundant.",
                    range: memberMeta.range
                )
            }
        }

        // Rule 3d: Data classes cannot declare open members.
        if ownerSym.flags.contains(.dataType) && memberMeta.hasOpen {
            let ownerName = ownerSym.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "Data class '\(ownerName)' cannot have open members. Data classes are final by design.",
                range: memberMeta.range
            )
        }
    }

    private func validateInterfaceProtectedMembers(
        _ interfaceDecl: InterfaceDecl,
        ctx: OpenFinalOverrideContext
    ) {
        // Kotlin rejects 'protected' on every member kind declared directly in
        // an interface body: functions, properties, nested types, objects,
        // companion objects, and type aliases. Member functions and properties
        // cannot reuse the MemberMeta path because nested type declarations
        // never reach validateMemberOverrides.
        var memberDeclIDs = interfaceDecl.memberFunctions + interfaceDecl.memberProperties
            + interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
        if let companionObject = interfaceDecl.companionObject {
            memberDeclIDs.append(companionObject)
        }
        for memberDeclID in memberDeclIDs {
            guard let memberDecl = ctx.ast.arena.decl(memberDeclID),
                  let range = protectedDeclRange(memberDecl)
            else { continue }
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "modifier 'protected' is not applicable inside 'interface'.",
                range: range
            )
        }
        for typeAlias in interfaceDecl.nestedTypeAliases where typeAlias.modifiers.contains(.protected) {
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-MODIFIER-CONFLICT",
                "modifier 'protected' is not applicable inside 'interface'.",
                range: typeAlias.range
            )
        }
    }

    private func protectedDeclRange(_ decl: Decl) -> SourceRange? {
        let modifiers: Modifiers
        let range: SourceRange
        switch decl {
        case let .classDecl(classDecl):
            modifiers = classDecl.modifiers
            range = classDecl.range
        case let .interfaceDecl(interfaceDecl):
            modifiers = interfaceDecl.modifiers
            range = interfaceDecl.range
        case let .funDecl(funDecl):
            modifiers = funDecl.modifiers
            range = funDecl.range
        case let .propertyDecl(propertyDecl):
            modifiers = propertyDecl.modifiers
            range = propertyDecl.range
        case let .objectDecl(objectDecl):
            modifiers = objectDecl.modifiers
            range = objectDecl.range
        case let .typeAliasDecl(typeAliasDecl):
            modifiers = typeAliasDecl.modifiers
            range = typeAliasDecl.range
        case .enumEntryDecl:
            return nil
        }
        return modifiers.contains(.protected) ? range : nil
    }

    private func validateOverrideOpenness(
        memberMeta: MemberMeta,
        memberSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        // STDLIB-INHERIT-018: Validate that override members follow Kotlin's openness rules

        guard let memberSym = ctx.symbols.symbol(memberSymbol) else { return }
        if memberMeta.hasOverride {
            if !memberMeta.hasFinal {
                if !memberSym.flags.contains(.overrideMember) {
                    let memberName = ctx.interner.resolve(memberMeta.name)
                    ctx.diagnostics.error(
                        "KSWIFTK-SEMA-INTERNAL",
                        "Internal error: override member '\(memberName)' missing overrideMember flag.",
                        range: memberMeta.range
                    )
                }
            } else {
                if !memberSym.flags.contains(.overrideMember) || !memberSym.flags.contains(.finalMember) {
                    let memberName = ctx.interner.resolve(memberMeta.name)
                    ctx.diagnostics.error(
                        "KSWIFTK-SEMA-INTERNAL",
                        "Internal error: final override member '\(memberName)' has incorrect flags.",
                        range: memberMeta.range
                    )
                }
            }
        }
    }

    private func validateOverrideTarget(
        memberDecl: Decl,
        memberName: InternedString,
        memberRange: SourceRange,
        overrideRange: SourceRange?,
        ownerSymbol: SymbolID,
        memberSymbol: SymbolID,
        parameterTypes: [TypeID]?,
        returnType: TypeID?,
        ctx: OpenFinalOverrideContext
    ) {
        let childSymbol = ctx.symbols.symbol(memberSymbol)
        let isFunction = childSymbol?.kind == .function
        let isMemberExtension = isFunction && childSymbol?.flags.contains(.memberExtension) == true
        let parent: OFOInheritedMember?
        if isMemberExtension {
            parent = findInheritedFunction(
                named: memberName,
                for: ownerSymbol,
                childMember: memberSymbol,
                requireMatchingSignature: true,
                ctx: ctx
            ) ?? findInheritedFunction(
                named: memberName,
                for: ownerSymbol,
                childMember: memberSymbol,
                requireMatchingSignature: false,
                ctx: ctx
            )
        } else {
            parent = findInheritedMember(
                named: memberName,
                for: ownerSymbol,
                symbols: ctx.symbols,
                kind: isFunction ? .function : .property,
                parameterTypes: parameterTypes,
                childMember: isFunction ? memberSymbol : nil,
                types: ctx.types
            )
        }
        guard let parent else {
            if isFunction, !isMemberExtension {
                if findInheritedFunction(
                    named: memberName,
                    for: ownerSymbol,
                    childMember: memberSymbol,
                    requireMatchingSignature: true,
                    ctx: ctx
                ) == nil,
                   hasSourceBackedInheritedFunction(named: memberName, for: ownerSymbol, ctx: ctx)
                       || (hasCompleteInheritedMemberIndex(for: ownerSymbol, ctx: ctx)
                           && !hasInheritedFunctionNamesake(named: memberName, for: ownerSymbol, ctx: ctx)) {
                    diagnoseOverrideNothing(memberName: memberName, memberRange: overrideRange ?? memberRange, ctx: ctx)
                }
            } else if hasCompleteInheritedMemberIndex(for: ownerSymbol, ctx: ctx) {
                // memberExtension: the name-level findInheritedFunction scan
                // found no same-named function. property: the name-level
                // findInheritedMember scan found no same-named member. A
                // missing namesake is only proof of 'overrides nothing' when
                // every reachable supertype's member list is complete.
                diagnoseOverrideNothing(memberName: memberName, memberRange: overrideRange ?? memberRange, ctx: ctx)
            }
            return
        }
        guard let parentSym = ctx.symbols.symbol(parent.memberID) else {
            return
        }

        if isFunction,
           (isMemberExtension || parentSym.flags.contains(.memberExtension)),
           !overrideFunctionSignatureMatches(
               childMember: memberSymbol,
               parentMember: parent.memberID,
               childOwner: ownerSymbol,
               requireCovariantReturn: false,
               ctx: ctx
           ) {
            let name = ctx.interner.resolve(memberName)
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-OVERRIDE-SIGNATURE",
                "Override of '\(name)' has an incompatible function signature. Method type parameter bounds, extension receiver, context/value parameter types, and suspend modifier must match.",
                range: memberRange
            )
            return
        }

        if isMemberOverridable(parentSym, parent: parent) {
            // An overriding function inherits default parameter values from
            // the overridden declaration; redeclaring them is rejected by
            // kotlinc ("an overriding function is not allowed to specify
            // default values for its parameters"). This phase runs before
            // `inheritDefaultArgumentValuesForOverrides`, so a non-nil
            // `defaultValue` here always comes from the source.
            if case let .funDecl(fun) = memberDecl,
               fun.valueParams.contains(where: { $0.defaultValue != nil }) {
                let name = ctx.interner.resolve(memberName)
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-OVERRIDE-DEFAULT-ARGS",
                    "An overriding function is not allowed to specify default values for its parameters: '\(name)'.",
                    range: memberRange
                )
            }

            if let returnType = returnType {
                validateReturnTypeCovariance(
                    childReturnType: returnType,
                    parentSymbol: parentSym,
                    memberName: memberName,
                    memberRange: memberRange,
                    ownerSymbol: ownerSymbol,
                    parentFilter: .explicitOnly,
                    ctx: ctx
                )
            }

            validateExceptionTypeCovariance(
                memberName: memberName,
                memberRange: memberRange,
                ownerSymbol: ownerSymbol,
                parentSymbol: parentSym,
                ctx: ctx
            )

            return
        }

        let name = ctx.interner.resolve(memberName)
        let ownerName = ctx.interner.resolve(parent.ownerName)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-FINAL",
            "'\(name)' in '\(ownerName)' is final and cannot be overridden.",
            range: memberRange
        )
    }

    /// Enum entry bodies are anonymous subclasses of the enum class, but
    /// their member symbols are parented to the entry's `.field` symbol,
    /// which records no supertypes. Inherited-member scans treat the enum
    /// class itself as the entry's direct supertype (KUU-4161).
    private func inheritedScanSupertypes(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> [SymbolID] {
        let direct = symbols.directSupertypes(for: symbol)
        guard direct.isEmpty,
              symbols.symbol(symbol)?.kind == .field,
              let parent = symbols.parentSymbol(for: symbol),
              symbols.symbol(parent)?.kind == .enumClass
        else {
            return direct
        }
        return [parent]
    }

    private func hasSourceBackedInheritedFunction(
        named memberName: InternedString,
        for ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        var visited: Set<SymbolID> = [ownerSymbol]
        var queue = inheritedScanSupertypes(for: ownerSymbol, symbols: ctx.symbols)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted,
                  let owner = ctx.symbols.symbol(current)
            else {
                continue
            }

            for candidateID in ctx.symbols.declaredChildren(of: current) {
                guard let candidate = ctx.symbols.symbol(candidateID),
                      candidate.fqName == owner.fqName + [candidate.name],
                      candidate.kind == .function,
                      candidate.name == memberName,
                      isInheritedMember(candidate, from: owner),
                      !candidate.flags.contains(.extensionMemberAlias)
                else {
                    continue
                }
                if ctx.symbols.isSourceBackedSymbol(candidateID) {
                    return true
                }
            }

            queue.append(contentsOf: ctx.symbols.directSupertypes(for: current))
        }
        return false
    }

    /// A namesake scan is only exhaustive when every reachable supertype
    /// exposes its full member list. Source-backed declarations (including
    /// imported library records) do; the synthetic kotlin.Any stub has a
    /// fixed, known member set. Synthetic shells and nominals with pending
    /// imported metadata may hide members the BFS cannot see, so an absent
    /// namesake is not proof that the member overrides nothing.
    ///
    /// A synthetic shell claimed by a bundled/user source declaration keeps
    /// `declSite == nil` unless its FQName sits on the
    /// `shouldRestoreDeclSiteForReusableSyntheticSymbol` compatibility
    /// list, but `setSourceFileID` still marks it as source-owned — its
    /// member list then comes from the source declaration, so it counts as
    /// complete here without changing `isSourceBackedSymbol` globally
    /// (KUU-4170: bundled `kotlin.Enum` keeps enum-entry 'overrides
    /// nothing' checks alive in source-stdlib mode).
    private func hasCompleteInheritedMemberIndex(
        for ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        var visited: Set<SymbolID> = [ownerSymbol]
        var queue = inheritedScanSupertypes(for: ownerSymbol, symbols: ctx.symbols)
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            let sourceClaimedShell = ctx.symbols.sourceFileID(for: current) != nil
            if current != ctx.types.anyClassSymbol,
               !(ctx.symbols.isSourceBackedSymbol(current) || sourceClaimedShell)
                   || ctx.symbols.isUnmaterializedImportedShell(current)
                   || ctx.symbols.hasPendingImportedNominalMetadata(for: current)
                   || ctx.symbols.hasPendingImportedMetadata(for: current) {
                return false
            }
            queue.append(contentsOf: ctx.symbols.directSupertypes(for: current))
        }
        return true
    }

    /// True when any supertype declares a function with `memberName`,
    /// regardless of backing. `hasSourceBackedInheritedFunction` proves the
    /// signature-mismatch case; when no namesake exists at all the override
    /// target is missing outright (kotlinc: 'X' overrides nothing).
    private func hasInheritedFunctionNamesake(
        named memberName: InternedString,
        for ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        if findAllInheritedMembers(named: memberName, for: ownerSymbol, symbols: ctx.symbols)
            .contains(where: { ctx.symbols.symbol($0.memberID)?.kind == .function }) {
            return true
        }
        // kotlin.Any is an implicit supertype of every class, but the
        // directSupertypes BFS does not always reach it (for example a class
        // whose only declared supertype is an interface). Probe it directly so
        // 'equals'/'hashCode'/'toString' overrides are not reported as
        // overriding nothing.
        let anyFQName = [ctx.interner.intern("kotlin"), ctx.interner.intern("Any")]
        guard let anyID = ctx.symbols.lookupNominal(fqName: anyFQName),
              let anySym = ctx.symbols.symbol(anyID) else { return false }
        return ctx.symbols.declaredChildren(of: anyID).contains { childID in
            guard let child = ctx.symbols.symbol(childID) else { return false }
            return child.kind == .function
                && child.name == memberName
                && child.fqName == anySym.fqName + [child.name]
                && !child.flags.contains(.extensionMemberAlias)
        }
    }

    private func diagnoseOverrideNothing(
        memberName: InternedString,
        memberRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        let name = ctx.interner.resolve(memberName)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-OVERRIDE-NOTHING",
            "'\(name)' overrides nothing.",
            range: memberRange
        )
    }

    /// Kotlin forbids a `val` property from overriding a `var` property:
    /// the override would remove the inherited setter. The reverse
    /// (`var` overriding `val`) is legal because it only adds a setter.
    /// This check is independent of `validateOverrideTarget`'s overridability
    /// verdict: a `final var` still reports this error alongside the
    /// final-override error, matching kotlinc.
    private func validateValVarMutabilityOverride(
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        memberSymbol: SymbolID,
        ctx: OpenFinalOverrideContext,
        inferredOnly: Bool = false
    ) {
        guard let memberSym = ctx.symbols.symbol(memberSymbol),
              memberSym.kind == .property,
              !memberSym.flags.contains(.mutable)
        else { return }

        let mutableParents = findAllInheritedMembers(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        ).filter { parent in
            guard let parentSym = ctx.symbols.symbol(parent.memberID) else { return false }
            return parentSym.kind == .property && parentSym.flags.contains(.mutable)
        }
        // kotlinc reports only the first mutable parent's failure.
        guard let parent = mutableParents.first else { return }
        // A pair whose declaration type is inferred is re-checked by the
        // deferred pass once inference publishes the signatures that
        // kotlinc renders in this diagnostic.
        let deferredPair = declHasInferredType(memberSymbol, ctx: ctx)
            || declHasInferredType(parent.memberID, ctx: ctx)
        guard deferredPair == inferredOnly else { return }
        let name = ctx.interner.resolve(memberName)
        let ownerName = ctx.interner.resolve(parent.ownerName)
        let parentType = ctx.symbols.propertyType(for: parent.memberID)
        let childType = ctx.symbols.propertyType(for: memberSymbol)
        let message: String
        if let parentType, let childType {
            let parentSig = ctx.types.displayName(of: parentType, symbols: ctx.symbols, interner: ctx.interner)
            let childSig = ctx.types.displayName(of: childType, symbols: ctx.symbols, interner: ctx.interner)
            message = "'var' property 'var \(name): \(parentSig)' defined in '\(ownerName)' cannot be overridden by 'val' property 'val \(name): \(childSig)'."
        } else {
            message = "'var' property '\(name)' defined in '\(ownerName)' cannot be overridden by 'val' property."
        }
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-OVERRIDE-MUTABILITY",
            message,
            range: memberRange
        )
    }

    /// Kotlin property override type rules:
    ///   - `val` overriding `val`: the child type must be a *subtype* of the
    ///     parent's (covariant read). Widening is rejected.
    ///   - `var` overriding `val`: only the getter participates, so the same
    ///     covariance applies.
    ///   - `var` overriding `var`: the property is read AND written, so the
    ///     child type must equal the parent type (invariant) — neither
    ///     widening nor narrowing is allowed. kotlinc reports "type of 'var x'
    ///     doesn't match the type of the overridden 'var' property".
    /// A `val`-over-`var` pair is left to `validateValVarMutabilityOverride`
    /// (it is rejected for mutability reasons regardless of types).
    /// A parent type that mentions the superclass's own type parameters is
    /// first substituted through the child's concrete supertype arguments;
    /// types still parametric after substitution are skipped: those checks
    /// belong to the generic-covariance path.
    ///
    /// When the override has no explicit type annotation the symbol stores the
    /// `anyType` placeholder (see `extractMemberMeta` for the function case),
    /// which would false-positive against any concrete parent type. Such
    /// inferred-type overrides are skipped here and re-validated by
    /// `validateInferredPropertyTypeOverrides` once type checking has
    /// published the inferred property type. The same deferral applies when
    /// the *parent* type is inferred (`parentFilter: .explicitOnly` below) —
    /// the header check would compare against the parent's placeholder.
    private func validatePropertyTypeOverride(
        memberDecl: Decl,
        ownerSymbol: SymbolID,
        memberSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        guard case let .propertyDecl(prop) = memberDecl,
              prop.type != nil,
              let memberSym = ctx.symbols.symbol(memberSymbol),
              memberSym.kind == .property,
              let childType = ctx.symbols.propertyType(for: memberSymbol),
              !typeContainsAnyTypeParam(childType, types: ctx.types)
        else { return }

        checkPropertyTypeAgainstInherited(
            memberName: prop.name,
            memberRange: prop.range,
            childType: childType,
            childIsVar: memberSym.flags.contains(.mutable),
            ownerSymbol: ownerSymbol,
            parentFilter: .explicitOnly,
            ctx: ctx
        )
    }

    /// Whether the member's declared type comes from inference — its
    /// declaration has no type annotation, so header-time checks saw only a
    /// placeholder. Members without a declaration in this compilation
    /// (imported, synthetic) always have a concrete type.
    private func declHasInferredType(_ memberID: SymbolID, ctx: OpenFinalOverrideContext) -> Bool {
        guard let declID = ctx.declBySymbol[memberID],
              let decl = ctx.ast.arena.decl(declID)
        else { return false }
        switch decl {
        case let .propertyDecl(prop):
            return prop.type == nil
        case let .funDecl(function):
            return function.returnType == nil
        default:
            return false
        }
    }

    private func parentIncluded(
        _ memberID: SymbolID,
        by filter: OFOParentTypeFilter,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .explicitOnly:
            return !declHasInferredType(memberID, ctx: ctx)
        case .inferredOnly:
            return declHasInferredType(memberID, ctx: ctx)
        }
    }

    /// First inherited property whose type the override fails against, or
    /// `nil` when the override is valid against every selected parent.
    private func firstPropertyTypeMismatch(
        memberName: InternedString,
        childType: TypeID,
        childIsVar: Bool,
        ownerSymbol: SymbolID,
        parentFilter: OFOParentTypeFilter,
        ctx: OpenFinalOverrideContext
    ) -> OFOInheritedMember? {
        for parent in findAllInheritedMembers(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        ) {
            guard parentIncluded(parent.memberID, by: parentFilter, ctx: ctx),
                  let parentSym = ctx.symbols.symbol(parent.memberID),
                  parentSym.kind == .property,
                  let declaredParentType = ctx.symbols.propertyType(for: parent.memberID)
            else { continue }

            // A parent property declared over the superclass's own type
            // parameters (`open var x: T`) must be compared through the
            // child's concrete supertype arguments: `class D : Base<String>`
            // sees `x` as `String`, not `T`. Parents still mentioning type
            // parameters after substitution (e.g. `D<T> : Base<T>`) fall back
            // to the old skip — the generic-covariance path owns those.
            let parentType: TypeID
            if typeContainsAnyTypeParam(declaredParentType, types: ctx.types),
               let parentOwner = ctx.symbols.parentSymbol(for: parent.memberID),
               let liftedArgs = liftedSupertypeArgs(
                   from: ownerSymbol,
                   to: parentOwner,
                   types: ctx.types,
                   symbols: ctx.symbols
               ) {
                parentType = ctx.types.substituteNominalTypeParameters(
                    in: declaredParentType,
                    owner: parentOwner,
                    ownerArgs: liftedArgs
                )
            } else {
                parentType = declaredParentType
            }
            guard !typeContainsAnyTypeParam(parentType, types: ctx.types)
            else { continue }

            let parentIsVar = parentSym.flags.contains(.mutable)
            let getterCovariant = ctx.types.isSubtype(childType, parentType)
            let invariant = !childIsVar || !parentIsVar
                || ctx.types.isSubtype(parentType, childType)
            if getterCovariant && invariant { continue }

            return parent
        }
        return nil
    }

    private func checkPropertyTypeAgainstInherited(
        memberName: InternedString,
        memberRange: SourceRange,
        childType: TypeID,
        childIsVar: Bool,
        ownerSymbol: SymbolID,
        parentFilter: OFOParentTypeFilter,
        ctx: OpenFinalOverrideContext
    ) {
        guard let parent = firstPropertyTypeMismatch(
            memberName: memberName,
            childType: childType,
            childIsVar: childIsVar,
            ownerSymbol: ownerSymbol,
            parentFilter: parentFilter,
            ctx: ctx
        ), let parentType = ctx.symbols.propertyType(for: parent.memberID) else {
            return
        }

        let name = ctx.interner.resolve(memberName)
        let ownerName = ctx.interner.resolve(parent.ownerName)
        let parentSig = ctx.types.displayName(of: parentType, symbols: ctx.symbols, interner: ctx.interner)
        let childSig = ctx.types.displayName(of: childType, symbols: ctx.symbols, interner: ctx.interner)
        let parentKeyword = ctx.symbols.symbol(parent.memberID)?.flags.contains(.mutable) == true ? "var" : "val"
        let message: String = if childIsVar {
            // kotlinc labels the overridden property 'var' whenever the
            // child is mutable, even when the parent is a `val`.
            "type of 'var \(name): \(childSig)' doesn't match the type of the overridden 'var' property '\(parentKeyword) \(name): \(parentSig)' defined in '\(ownerName)'."
        } else {
            "type of 'val \(name): \(childSig)' is not a subtype of overridden property '\(parentKeyword) \(name): \(parentSig)' defined in '\(ownerName)'."
        }
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-OVERRIDE-TYPE",
            message,
            range: memberRange
        )
    }

    private func validateReturnTypeCovariance(
        childReturnType: TypeID,
        parentSymbol: SemanticSymbol,
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        parentFilter: OFOParentTypeFilter,
        ctx: OpenFinalOverrideContext
    ) {
        guard parentIncluded(parentSymbol.id, by: parentFilter, ctx: ctx),
              let parentSignature = ctx.symbols.functionSignature(for: parentSymbol.id)
        else {
            return
        }
        let parentReturnType = parentSignature.returnType

        if !parentSymbol.flags.contains(.memberExtension) {
            // Only same-kind members make the override target ambiguous: a
            // same-named property lives in the other override namespace and
            // must not suppress the covariance check (KUU-4106).
            let allParentMembers = findAllInheritedMembers(
                named: memberName,
                for: ownerSymbol,
                symbols: ctx.symbols
            ).filter { ctx.symbols.symbol($0.memberID)?.kind == .function }
            guard allParentMembers.count == 1 else { return }
        }

        // Enhanced covariance check for generic types
        if typeContainsAnyTypeParam(parentReturnType, types: ctx.types) ||
           typeContainsAnyTypeParam(childReturnType, types: ctx.types) {
            let parentOwnerClass = ctx.symbols.parentSymbol(for: parentSymbol.id)
            let childSignature = getFunctionMemberMatching(
                parentMember: parentSymbol,
                named: memberName,
                in: ownerSymbol,
                ctx: ctx
            ).flatMap { ctx.symbols.functionSignature(for: $0) }
            if !validateGenericReturnTypeCovariance(
                childReturnType: childReturnType,
                parentReturnType: parentReturnType,
                parentSignature: parentSignature,
                childSignature: childSignature,
                parentOwnerClass: parentOwnerClass,
                childOwnerClass: ownerSymbol,
                types: ctx.types,
                symbols: ctx.symbols
            ) {
                let name = ctx.interner.resolve(memberName)
                let parentReturnTypeStr = ctx.types.renderType(parentReturnType)
                let childReturnTypeStr = ctx.types.renderType(childReturnType)
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-OVERRIDE-RETURN",
                    "Override of '\(name)' has incompatible return type. "
                        + "Expected covariant relationship with '\(parentReturnTypeStr)' but found '\(childReturnTypeStr)'.",
                    range: memberRange
                )
            }
            return
        }

        // Child return type must be a subtype of parent return type (covariant return).
        guard !ctx.types.isSubtype(childReturnType, parentReturnType) else {
            return // Valid: child return type is a subtype of parent return type
        }

        let name = ctx.interner.resolve(memberName)
        let parentReturnTypeStr = ctx.types.renderType(parentReturnType)
        let childReturnTypeStr = ctx.types.renderType(childReturnType)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-OVERRIDE-RETURN",
            "Override of '\(name)' has incompatible return type. "
                + "Expected subtype of '\(parentReturnTypeStr)' but found '\(childReturnTypeStr)'.",
            range: memberRange
        )
    }

    private func validateExceptionTypeCovariance(
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        parentSymbol: SemanticSymbol,
        ctx: OpenFinalOverrideContext
    ) {
        guard let parentSignature = ctx.symbols.functionSignature(for: parentSymbol.id),
              let childSymbol = getFunctionMemberMatching(parentMember: parentSymbol, named: memberName, in: ownerSymbol, ctx: ctx),
              let childSignature = ctx.symbols.functionSignature(for: childSymbol) else {
            return
        }

        if !parentSymbol.flags.contains(.memberExtension) {
            // Same-named properties live in a separate override namespace
            // and do not make the function target ambiguous (KUU-4106).
            let allParentMembers = findAllInheritedMembers(
                named: memberName,
                for: ownerSymbol,
                symbols: ctx.symbols
            ).filter { ctx.symbols.symbol($0.memberID)?.kind == .function }
            guard allParentMembers.count == 1 else { return }
        }

        let parentExceptions = parentSignature.canThrow
        let childExceptions = childSignature.canThrow

        // Exception covariance check: child cannot throw more exceptions than parent
        if parentExceptions && !childExceptions {
            // This is valid - child throws fewer exceptions
            return
        }

        if !parentExceptions && childExceptions {
            // Child throws exceptions but parent doesn't - this violates covariance
            let name = ctx.interner.resolve(memberName)
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-OVERRIDE-EXCEPTION",
                "Override of '\(name)' cannot throw exceptions because overridden method does not throw.",
                range: memberRange
            )
        }

        // Note: Currently the FunctionSignature only tracks canThrow boolean, not specific exception types
        // When exception type information is added to FunctionSignature, we should enhance this check
        // to verify that child exception types are subtypes of parent exception types
    }

    private func validateGenericReturnTypeCovariance(
        childReturnType: TypeID,
        parentReturnType: TypeID,
        parentSignature: FunctionSignature,
        childSignature: FunctionSignature?,
        parentOwnerClass: SymbolID?,
        childOwnerClass: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable
    ) -> Bool {
        guard let parentOwnerClass else {
            return validateBasicGenericReturnTypeCovariance(
                childReturnType: childReturnType,
                parentReturnType: parentReturnType,
                types: types
            )
        }

        guard let liftedParentArgs = liftedSupertypeArgs(
            from: childOwnerClass,
            to: parentOwnerClass,
            types: types,
            symbols: symbols
        ) else {
            return validateBasicGenericReturnTypeCovariance(
                childReturnType: childReturnType,
                parentReturnType: parentReturnType,
                types: types
            )
        }

        let childClassArgs = classTypeParamArgs(for: childOwnerClass, types: types)
        var substitutedParentReturn = types.substituteNominalTypeParameters(
            in: parentReturnType,
            owner: parentOwnerClass,
            ownerArgs: liftedParentArgs
        )

        if let childSignature,
           let (methodSubstitution, parentTypeVarBySymbol) = alignMethodTypeParameterSubstitution(
               parentSignature: parentSignature,
               childSignature: childSignature,
               types: types
           ),
           !methodSubstitution.isEmpty
        {
            substitutedParentReturn = types.substituteTypeParameters(
                in: substitutedParentReturn,
                substitution: methodSubstitution,
                typeVarBySymbol: parentTypeVarBySymbol
            )
        }

        let substitutedChildReturn = types.substituteNominalTypeParameters(
            in: childReturnType,
            owner: childOwnerClass,
            ownerArgs: childClassArgs
        )

        return types.isSubtype(substitutedChildReturn, substitutedParentReturn)
    }

    private func liftedSupertypeArgs(
        from childOwner: SymbolID,
        to parentOwner: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable
    ) -> [TypeArg]? {
        if childOwner == parentOwner {
            return classTypeParamArgs(for: childOwner, types: types)
        }

        let childClassArgs = classTypeParamArgs(for: childOwner, types: types)

        // The child's supertype edge may resolve to either side of an
        // expect/actual pair while `parentOwner` names the other — both
        // share one FQName and one member set, so search both twins.
        var candidateOwners = [parentOwner]
        if let parentSym = symbols.symbol(parentOwner),
           parentSym.flags.contains(.expectDeclaration)
               || parentSym.flags.contains(.actualDeclaration)
        {
            let counterpartFlag: SymbolFlags = parentSym.flags.contains(.expectDeclaration)
                ? .actualDeclaration
                : .expectDeclaration
            candidateOwners += symbols.lookupAll(fqName: parentSym.fqName)
                .filter { candidateID in
                    guard candidateID != parentOwner,
                          let candidate = symbols.symbol(candidateID)
                    else { return false }
                    return candidate.kind == parentSym.kind
                        && candidate.flags.contains(counterpartFlag)
                }
                .sorted { $0.rawValue < $1.rawValue }
        }

        for ownerID in candidateOwners {
            if let lifted = types.liftedNominalSupertypeArgs(
                from: childOwner,
                childArgs: childClassArgs,
                to: ownerID
            ) {
                return lifted
            }

            let directArgs = symbols.supertypeTypeArgs(for: childOwner, supertype: ownerID)
            guard !directArgs.isEmpty else { continue }
            guard !childClassArgs.isEmpty else { return directArgs }

            return directArgs.map { arg in
                substituteTypeArgForOwner(arg, owner: childOwner, ownerArgs: childClassArgs, types: types)
            }
        }
        return nil
    }

    private func classTypeParamArgs(for owner: SymbolID, types: TypeSystem) -> [TypeArg] {
        types.nominalTypeParameterSymbols(for: owner).map { symbol in
            .invariant(types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull))))
        }
    }

    private func substituteTypeArgForOwner(
        _ arg: TypeArg,
        owner: SymbolID,
        ownerArgs: [TypeArg],
        types: TypeSystem
    ) -> TypeArg {
        switch arg {
        case let .invariant(type):
            .invariant(types.substituteNominalTypeParameters(in: type, owner: owner, ownerArgs: ownerArgs))
        case let .out(type):
            .out(types.substituteNominalTypeParameters(in: type, owner: owner, ownerArgs: ownerArgs))
        case let .in(type):
            .in(types.substituteNominalTypeParameters(in: type, owner: owner, ownerArgs: ownerArgs))
        case .star:
            .star
        }
    }

    private func alignMethodTypeParameterSubstitution(
        parentSignature: FunctionSignature,
        childSignature: FunctionSignature,
        types: TypeSystem
    ) -> ([TypeVarID: TypeID], [SymbolID: TypeVarID])? {
        let parentMethodCount = parentSignature.typeParameterSymbols.count - parentSignature.classTypeParameterCount
        let childMethodCount = childSignature.typeParameterSymbols.count - childSignature.classTypeParameterCount
        guard parentMethodCount == childMethodCount else { return nil }

        let parentMethodTypeParams = Array(parentSignature.typeParameterSymbols.suffix(parentMethodCount))
        let childMethodTypeParams = Array(childSignature.typeParameterSymbols.suffix(childMethodCount))
        let parentTypeVarBySymbol = types.makeTypeVarBySymbol(parentSignature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (parentTypeParam, childTypeParam) in zip(parentMethodTypeParams, childMethodTypeParams) {
            guard let typeVar = parentTypeVarBySymbol[parentTypeParam] else { continue }
            substitution[typeVar] = types.make(.typeParam(TypeParamType(
                symbol: childTypeParam,
                nullability: .nonNull
            )))
        }
        return (substitution, parentTypeVarBySymbol)
    }

    /// Fallback for cases where inheritance type arguments cannot be resolved.
    private func validateBasicGenericReturnTypeCovariance(
        childReturnType: TypeID,
        parentReturnType: TypeID,
        types: TypeSystem
    ) -> Bool {
        let parentKind = types.kind(of: parentReturnType)
        let childKind = types.kind(of: childReturnType)

        // Case 1: Both are the same generic class with potentially different type arguments
        if case let .classType(parentClass) = parentKind,
           case let .classType(childClass) = childKind,
           parentClass.classSymbol == childClass.classSymbol {
            return validateGenericTypeArgumentCovariance(
                childArgs: childClass.args,
                parentArgs: parentClass.args,
                types: types
            )
        }

        // Case 2: Child is a subtype of parent (for non-generic cases)
        return types.isSubtype(childReturnType, parentReturnType)
    }

    private func validateGenericTypeArgumentCovariance(
        childArgs: [TypeArg],
        parentArgs: [TypeArg],
        types: TypeSystem
    ) -> Bool {
        guard childArgs.count == parentArgs.count else { return false }

        for (childArg, parentArg) in zip(childArgs, parentArgs) {
            switch (childArg, parentArg) {
            case (.out(let childType), .out(let parentType)):
                // Both are covariant: child must be subtype of parent
                if !types.isSubtype(childType, parentType) {
                    return false
                }
            case (.in(let childType), .in(let parentType)):
                // Both are contravariant: parent must be subtype of child
                if !types.isSubtype(parentType, childType) {
                    return false
                }
            case (.invariant(let childType), .invariant(let parentType)):
                // Both are invariant: types must be equal
                if childType != parentType {
                    return false
                }
            default:
                // Mixed variances: conservative approach - reject
                return false
            }
        }

        return true
    }

    /// Child functions named `memberName` in `ownerSymbol` (overload set).
    private func childFunctions(
        named memberName: InternedString,
        in ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> [SymbolID] {
        guard ctx.symbols.symbol(ownerSymbol) != nil else { return [] }
        return ctx.symbols.declaredChildren(of: ownerSymbol).compactMap { childID -> SymbolID? in
            guard let child = ctx.symbols.symbol(childID),
                  child.name == memberName,
                  child.kind == .function
            else { return nil }
            return childID
        }
    }

    /// Pick the overriding overload whose complete signature matches the parent after alpha-alignment.
    private func getFunctionMemberMatching(
        parentMember: SemanticSymbol,
        named memberName: InternedString,
        in ownerSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> SymbolID? {
        for childID in childFunctions(named: memberName, in: ownerSymbol, ctx: ctx) {
            // Signature identity decides which overload is the override
            // target; the callers run their own return/exception checks, so
            // the return type stays out of the match (KUU-4170).
            if overrideFunctionSignatureMatches(
                childMember: childID,
                parentMember: parentMember.id,
                childOwner: ownerSymbol,
                requireCovariantReturn: false,
                ctx: ctx
            ) {
                return childID
            }
        }
        return nil
    }

    private func findInheritedFunction(
        named memberName: InternedString,
        for childOwner: SymbolID,
        childMember: SymbolID,
        requireMatchingSignature: Bool,
        ctx: OpenFinalOverrideContext
    ) -> OFOInheritedMember? {
        var visited: Set<SymbolID> = [childOwner]
        var queue = inheritedScanSupertypes(for: childOwner, symbols: ctx.symbols)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted,
                  let owner = ctx.symbols.symbol(current)
            else { continue }

            for candidateID in ctx.symbols.declaredChildren(of: current) {
                guard let candidate = ctx.symbols.symbol(candidateID),
                      candidate.fqName == owner.fqName + [candidate.name],
                      candidate.kind == .function,
                      candidate.name == memberName,
                      isInheritedMember(candidate, from: owner),
                      !candidate.flags.contains(.extensionMemberAlias)
                else { continue }

                let resolvedCandidateID = resolveInheritedMember(candidateID, symbols: ctx.symbols)
                if !requireMatchingSignature || overrideFunctionSignatureMatches(
                    childMember: childMember,
                    parentMember: resolvedCandidateID,
                    childOwner: childOwner,
                    requireCovariantReturn: false,
                    ctx: ctx
                ) {
                    return OFOInheritedMember(
                        memberID: resolvedCandidateID,
                        ownerName: owner.name,
                        ownerIsInterface: owner.kind == .interface
                    )
                }
            }

            queue.append(contentsOf: ctx.symbols.directSupertypes(for: current))
        }
        return nil
    }

    private func overrideFunctionSignatureMatches(
        childMember: SymbolID,
        parentMember: SymbolID,
        childOwner: SymbolID,
        requireCovariantReturn: Bool,
        ctx: OpenFinalOverrideContext
    ) -> Bool {
        overrideFunctionSignatureMatches(
            childMember: childMember,
            parentMember: parentMember,
            childOwner: childOwner,
            requireCovariantReturn: requireCovariantReturn,
            symbols: ctx.symbols,
            types: ctx.types
        )
    }

    /// `ctx`-free core of `overrideFunctionSignatureMatches` so member
    /// lookup helpers that only carry `symbols`/`types` (visibility
    /// inheritance, `findInheritedMember`, abstract-member completeness)
    /// can run the same check. Internal (not private) so
    /// `AbstractMemberCompleteness.swift` can share it (KUU-4170).
    func overrideFunctionSignatureMatches(
        childMember: SymbolID,
        parentMember: SymbolID,
        childOwner: SymbolID,
        requireCovariantReturn: Bool,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard let childSignature = symbols.functionSignature(for: childMember),
              let parentSignature = symbols.functionSignature(for: parentMember),
              let parentOwner = symbols.parentSymbol(for: parentMember),
              let child = symbols.symbol(childMember),
              let parent = symbols.symbol(parentMember),
              child.flags.contains(.memberExtension) == parent.flags.contains(.memberExtension),
              childSignature.isSuspend == parentSignature.isSuspend,
              methodUpperBoundsMatch(
                  source: parentSignature,
                  target: childSignature,
                  sourceOwner: parentOwner,
                  targetOwner: childOwner,
                  instanceOwner: childOwner,
                  types: types
              )
        else { return false }

        let parentMethodParameters = Array(
            parentSignature.typeParameterSymbols.dropFirst(parentSignature.classTypeParameterCount)
        )
        let childMethodParameters = Array(
            childSignature.typeParameterSymbols.dropFirst(childSignature.classTypeParameterCount)
        )
        func alignParentType(_ type: TypeID) -> TypeID {
            let specialized = specializeMethodOwnerType(
                type,
                owner: parentOwner,
                instanceOwner: childOwner,
                types: types
            )
            return alphaAlignedMethodType(
                specialized,
                sourceParameters: parentMethodParameters,
                targetParameters: childMethodParameters,
                types: types
            )
        }

        if child.flags.contains(.memberExtension) {
            guard let childReceiver = childSignature.receiverType,
                  let parentReceiver = parentSignature.receiverType,
                  methodIdentityParameterTypesMatch(
                      candidateParameterTypes: [childReceiver],
                      interfaceParameterTypes: [alignParentType(parentReceiver)],
                      types: types
                  )
            else { return false }
        }

        guard methodIdentityParameterTypesMatch(
            candidateParameterTypes: childSignature.contextReceiverTypes,
            interfaceParameterTypes: parentSignature.contextReceiverTypes.map(alignParentType),
            types: types
        ), methodIdentityParameterTypesMatch(
            candidateParameterTypes: childSignature.parameterTypes,
            interfaceParameterTypes: parentSignature.parameterTypes.map(alignParentType),
            types: types,
            allowJavaCollectionMutability: symbols.isJVMJavaMethod(parentMember)
        ) else { return false }

        guard requireCovariantReturn else { return true }
        return types.isSubtype(childSignature.returnType, alignParentType(parentSignature.returnType))
    }

    private func validateVisibilityExpansion(
        childVisibility: Visibility,
        childOwnerSymbol: SymbolID,
        parentSymbol: SemanticSymbol,
        memberName: InternedString,
        memberRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        let parentVisibility = parentSymbol.visibility

        // KUU-4153: kotlinc's `Visibilities.compare` is a partial order —
        // `private` is narrower than every visibility and `public` wider
        // than every visibility, while `protected` and `internal` are
        // unordered relative to each other. There is no exemption for
        // `internal` narrowing inside the same module: a strictly narrower
        // override reports `cannot weaken access privilege`
        // (CANNOT_WEAKEN_ACCESS_PRIVILEGE) and an unordered pairing reports
        // `cannot change access privilege` (CANNOT_CHANGE_ACCESS_PRIVILEGE),
        // the same factories the accessor-level check emits, only naming
        // the member itself rather than 'accessor'.
        let violation: (code: String, verb: String)?
        switch compareOverrideVisibilities(childVisibility, parentVisibility) {
        case let order? where order < 0:
            violation = (code: "KSWIFTK-SEMA-0478", verb: "weaken")
        case nil:
            violation = (code: "KSWIFTK-SEMA-0479", verb: "change")
        default:
            violation = nil
        }
        if let violation {
            let name = ctx.interner.resolve(memberName)
            let ownerName = resolveOwnerName(of: parentSymbol, ctx: ctx)
            ctx.diagnostics.error(
                violation.code,
                "cannot \(violation.verb) access privilege \(visibilityToString(childVisibility)) for '\(name)' in '\(ownerName)'.",
                range: memberRange
            )
            return
        }

        // An `internal` member is not visible outside its module, so an
        // override of a member declared `internal` elsewhere stays rejected
        // regardless of the visibility the child spells.
        validateModuleBoundaryCompatibility(
            childOwnerSymbol: childOwnerSymbol,
            parentSymbol: parentSymbol,
            memberName: memberName,
            memberRange: memberRange,
            ctx: ctx
        )
    }

    private func validateModuleBoundaryCompatibility(
        childOwnerSymbol: SymbolID,
        parentSymbol: SemanticSymbol,
        memberName: InternedString,
        memberRange: SourceRange,
        ctx: OpenFinalOverrideContext
    ) {
        guard let childModule = resolveModuleFQN(for: childOwnerSymbol, ctx: ctx),
              let parentModule = resolveModuleFQN(for: parentSymbol.id, ctx: ctx)
        else {
            return
        }

        guard childModule != parentModule else {
            return
        }

        let name = ctx.interner.resolve(memberName)
        let parentVisibility = parentSymbol.visibility

        if parentVisibility == .internal {
            ctx.diagnostics.error(
                "KSWIFTK-SEMA-VISIBILITY-MODULE",
                "'\(name)' cannot override internal member from another module.",
                range: memberRange
            )
            return
        }
    }

    private func resolveOwnerName(of member: SemanticSymbol, ctx: OpenFinalOverrideContext) -> String {
        if let ownerID = ctx.symbols.parentSymbol(for: member.id),
           let owner = ctx.symbols.symbol(ownerID) {
            return ctx.interner.resolve(owner.name)
        }
        return ctx.interner.resolve(member.name)
    }

    private func resolveModuleFQN(
        for symbolID: SymbolID,
        ctx: OpenFinalOverrideContext
    ) -> InternedString? {
        var current: SymbolID? = symbolID
        while let id = current {
            if let module = ctx.symbols.moduleFQN(for: id) {
                return module
            }
            // sourceFileID がある = コンパイル対象ソースのシンボル。
            // assignCompilationModuleFQNames が設定を漏らした場合のフォールバック。
            if ctx.symbols.sourceFileID(for: id) != nil {
                return ctx.compilationModuleFQN
            }
            current = ctx.symbols.parentSymbol(for: id)
        }
        return nil
    }

    private func validateMissingOverride(
        memberName: InternedString,
        memberRange: SourceRange,
        ownerSymbol: SymbolID,
        memberSymbol: SymbolID,
        ctx: OpenFinalOverrideContext
    ) {
        let name = ctx.interner.resolve(memberName)

        // Enhanced override detection with signature-aware matching

        // Find all potential parent members that could be overridden
        var allParentMembers = findAllInheritedMembers(
            named: memberName,
            for: ownerSymbol,
            symbols: ctx.symbols
        )

        // Interfaces never list kotlin.Any in directSupertypes, so the walk
        // above cannot see toString/hashCode/equals. Every interface still
        // inherits them, and kotlinc requires `override` to hide them
        // (KUU-3255). Classes reach Any through the supertype walk already;
        // keep the extra lookup interface-only so it cannot perturb lazy
        // materialization order for other decls.
        let ownerIsInterface = ctx.symbols.symbol(ownerSymbol)?.kind == .interface
        if ownerIsInterface {
            let knownMemberIDs = Set(allParentMembers.map(\.memberID))
            for anyMember in findAnyMembers(named: memberName, ctx: ctx)
            where !knownMemberIDs.contains(anyMember.memberID) {
                allParentMembers.append(anyMember)
            }
        }

        guard !allParentMembers.isEmpty else { return }

        // Hiding is signature-based, not overridability-based: kotlinc
        // reports 'hides member of supertype' for open, abstract, and final
        // parent members alike — a same-signature declaration hides whatever
        // the nearest supertype declares. Private members are not inherited,
        // so they can never be hidden; they still block the supertype walk
        // above, matching kotlinc (KUU-4170).
        let hideableParents = allParentMembers.filter { parent in
            guard let parentSym = ctx.symbols.symbol(parent.memberID) else { return false }
            return parentSym.visibility != .private
                && !parentSym.flags.contains(.extensionMemberAlias)
        }

        guard !hideableParents.isEmpty else { return }

        // Match the inherited member against the declaration currently being
        // validated. Looking at every child overload with this name makes an
        // unrelated overload appear to implement the interface member (for
        // example, StringBuilder.append(Int) after StringBuilder.append(Char)
        // is declared as an Appendable override).
        let matchingParents: [OFOInheritedMember]
        if ctx.symbols.functionSignature(for: memberSymbol) != nil {
            // Kotlin hides on name + value-parameter signature; the return
            // type is not part of the hiding check — kotlinc reports 'hides
            // member' even when the returns are incompatible — and an
            // expression body still carries the anyType placeholder at
            // header time, so covariance must not gate the match (KUU-4170).
            matchingParents = hideableParents.filter { parent in
                guard let parentSymbol = ctx.symbols.symbol(parent.memberID),
                      parentSymbol.kind == .function
                else {
                    return false
                }
                return overrideFunctionSignatureMatches(
                    childMember: memberSymbol,
                    parentMember: parent.memberID,
                    childOwner: ownerSymbol,
                    requireCovariantReturn: false,
                    ctx: ctx
                )
            }
        } else if let childSymbol = ctx.symbols.symbol(memberSymbol), childSymbol.kind == .property {
            // Extension properties can only override extension properties;
            // a same-named non-extension interface member is unrelated.
            matchingParents = hideableParents.filter { parent in
                guard let parentSymbol = ctx.symbols.symbol(parent.memberID),
                      parentSymbol.kind == .property
                else {
                    return false
                }
                return !ctx.symbols.isJVMJavaBeanProperty(parent.memberID)
                    && childSymbol.flags.contains(.memberExtension) == parentSymbol.flags.contains(.memberExtension)
            }
        } else {
            matchingParents = []
        }

        guard !matchingParents.isEmpty else { return }

        // kotlinc names the nearest supertype declaring the member — class
        // supertypes precede interfaces in declaration order — and uses the
        // same 'hides member of supertype' wording for every owner kind
        // (class, object, enum class, interface). The former
        // 'implements interface member' wording has no kotlinc counterpart
        // (KUU-4170).
        let parent = matchingParents.first { !$0.ownerIsInterface } ?? matchingParents[0]
        let parentName = ctx.interner.resolve(parent.ownerName)
        ctx.diagnostics.error(
            "KSWIFTK-SEMA-OVERRIDE",
            "'\(name)' hides member of supertype '\(parentName)' "
                + "and needs an 'override' modifier.",
            range: memberRange
        )
    }

    /// `kotlin.Any` members (`toString`/`hashCode`/`equals`) reachable for
    /// hiding checks when the supertype walk cannot reach `Any` itself —
    /// interfaces do not list it in `directSupertypes`.
    private func findAnyMembers(
        named memberName: InternedString,
        ctx: OpenFinalOverrideContext
    ) -> [OFOInheritedMember] {
        let anyFQName = [ctx.interner.intern("kotlin"), ctx.interner.intern("Any")]
        guard let anyID = ctx.symbols.lookupNominal(fqName: anyFQName),
              let anySymbol = ctx.symbols.symbol(anyID) else { return [] }
        var results: [OFOInheritedMember] = []
        for childID in ctx.symbols.declaredChildren(of: anyID) {
            guard let child = ctx.symbols.symbol(childID),
                  child.name == memberName,
                  child.kind == .function || child.kind == .property
            else { continue }
            results.append(OFOInheritedMember(
                memberID: childID,
                ownerName: anySymbol.name,
                ownerIsInterface: false
            ))
        }
        return results
    }

    /// A member is overridable when it belongs to an interface,
    /// is explicitly `open`, is `abstract`, or is a non-final
    /// `override` (override members are implicitly open in Kotlin
    /// unless also marked `final`).
    private func isMemberOverridable(
        _ sym: SemanticSymbol,
        parent: OFOInheritedMember
    ) -> Bool {
        if parent.ownerIsInterface { return true }
        if sym.flags.contains(.openType) { return true }
        if sym.flags.contains(.abstractType) { return true }
        // An override member is implicitly open unless marked final.
        if sym.flags.contains(.overrideMember), !sym.flags.contains(.finalMember) {
            return true
        }
        return false
    }

    private struct OFOInheritedMember {
        let memberID: SymbolID
        let ownerName: InternedString
        let ownerIsInterface: Bool
    }

    /// Members of same-module expect and actual declarations share the
    /// owner's FQName, so `children(ofFQName:)` yields both sides of a
    /// paired class. The expect side carries no `open`/`abstract`/`override`
    /// information — Kotlin spells those modifiers on the `actual`
    /// counterpart — so an expect-declared member must be judged through
    /// its linked actual declaration whenever the pair is available.
    /// Header-time passes run before `setExpectActualLink`, so when no link
    /// exists yet, pair the declarations positionally: a compatible
    /// expect/actual class lists the same members in the same order.
    private func resolveInheritedMember(
        _ memberID: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID {
        guard let member = symbols.symbol(memberID),
              member.flags.contains(.expectDeclaration)
        else { return memberID }
        if let linked = symbols.actualSymbol(for: memberID),
           symbols.symbol(linked)?.kind == member.kind {
            return linked
        }
        guard let expectOwnerID = symbols.parentSymbolIfKnown(for: memberID)
            ?? symbols.parentSymbol(for: memberID),
              let expectOwner = symbols.symbol(expectOwnerID),
              expectOwner.flags.contains(.expectDeclaration)
        else { return memberID }
        let actualOwnerIDs = symbols.lookupAll(fqName: expectOwner.fqName)
            .filter { candidateID in
                guard let candidate = symbols.symbol(candidateID) else { return false }
                return candidate.flags.contains(.actualDeclaration)
                    && candidate.kind == expectOwner.kind
            }
            .sorted { $0.rawValue < $1.rawValue }
        let expectSiblings = symbols.children(of: expectOwnerID).filter { candidateID in
            guard let candidate = symbols.symbol(candidateID) else { return false }
            return candidate.name == member.name && candidate.kind == member.kind
        }
        guard let position = expectSiblings.firstIndex(of: memberID)
        else { return memberID }
        for actualOwnerID in actualOwnerIDs {
            let actualSiblings = symbols.children(of: actualOwnerID).filter { candidateID in
                guard let candidate = symbols.symbol(candidateID) else { return false }
                return candidate.name == member.name && candidate.kind == member.kind
            }
            guard position < actualSiblings.count else { continue }
            return actualSiblings[position]
        }
        return memberID
    }

    private func isInheritedMember(_ member: SemanticSymbol, from owner: SemanticSymbol) -> Bool {
        owner.kind != .interface || member.visibility != .private
    }

    /// Finds the inherited member `memberName` overrides. Kotlin keeps
    /// properties and functions in separate override namespaces even when
    /// they share a name — `override val p` targets `val p`, never `fun p()`
    /// (KUU-4106). Matching only `kind` prevents a same-named final member
    /// of the other kind from masking the real override target.
    private func findInheritedMember(
        named memberName: InternedString,
        for classSymbol: SymbolID,
        symbols: SymbolTable,
        kind: SymbolKind,
        parameterTypes: [TypeID]? = nil,
        childMember: SymbolID? = nil,
        types: TypeSystem? = nil
    ) -> OFOInheritedMember? {
        var visited: Set<SymbolID> = [classSymbol]
        var queue = inheritedScanSupertypes(for: classSymbol, symbols: symbols)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            guard let sym = symbols.symbol(current) else { continue }

            for childID in symbols.declaredChildren(of: current) {
                guard let child = symbols.symbol(childID) else {
                    continue
                }
                guard child.fqName == sym.fqName + [child.name] else { continue }
                guard !child.flags.contains(.extensionMemberAlias) else { continue }
                guard isInheritedMember(child, from: sym) else { continue }
                guard child.kind == kind, child.name == memberName else {
                    continue
                }
                // An expect-declared member only mirrors the name: judge the
                // override against the linked actual declaration instead.
                let resolvedChildID = resolveInheritedMember(childID, symbols: symbols)
                // Function overloads must be matched by their parameter types;
                // name-only lookup can select a synthetic range overload before
                // the real member being overridden.
                if let parameterTypes {
                    guard inheritedSignatureMatches(
                        childMember: childMember,
                        childParameterTypes: parameterTypes,
                        parentMember: resolvedChildID,
                        childOwner: classSymbol,
                        kind: kind,
                        symbols: symbols,
                        types: types
                    ) else {
                        continue
                    }
                }
                return OFOInheritedMember(
                    memberID: resolvedChildID,
                    ownerName: sym.name,
                    ownerIsInterface: sym.kind == .interface
                )
            }

            queue.append(
                contentsOf: symbols.directSupertypes(for: current)
            )
        }
        return nil
    }

    /// Signature check behind `findInheritedMember`'s `parameterTypes`
    /// filter. With the child symbol and `TypeSystem` at hand this runs the
    /// full override-signature match, which substitutes the supertype's
    /// type arguments through the child's supertype edge (`G<T>.m(t: T)`
    /// seen from `D : G<D>` is `m(t: D)`) and alpha-aligns method type
    /// parameters. Without the child symbol it still specializes the
    /// parent's parameter types before the identity comparison; the raw
    /// `TypeID` equality remains the last resort when no `TypeSystem` is
    /// available (KUU-4170).
    private func inheritedSignatureMatches(
        childMember: SymbolID?,
        childParameterTypes: [TypeID],
        parentMember: SymbolID,
        childOwner: SymbolID,
        kind: SymbolKind,
        symbols: SymbolTable,
        types: TypeSystem?
    ) -> Bool {
        if kind == .function,
           let childMember,
           let types,
           symbols.functionSignature(for: childMember) != nil
        {
            return overrideFunctionSignatureMatches(
                childMember: childMember,
                parentMember: parentMember,
                childOwner: childOwner,
                requireCovariantReturn: false,
                symbols: symbols,
                types: types
            )
        }
        guard let parentSignature = symbols.functionSignature(for: parentMember) else {
            return false
        }
        guard let types else {
            return parentSignature.parameterTypes == childParameterTypes
        }
        let owner = symbols.parentSymbol(for: parentMember)
        let alignedParentParams = parentSignature.parameterTypes.map {
            specializeMethodOwnerType($0, owner: owner, instanceOwner: childOwner, types: types)
        }
        return methodIdentityParameterTypesMatch(
            candidateParameterTypes: childParameterTypes,
            interfaceParameterTypes: alignedParentParams,
            types: types
        )
    }

    private func typeContainsAnyTypeParam(_ typeID: TypeID, types: TypeSystem) -> Bool {
        switch types.kind(of: typeID) {
        case .typeParam:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return typeContainsAnyTypeParam(inner, types: types)
                case .star:
                    return false
                }
            }
        case let .functionType(ft):
            if ft.contextReceivers.contains(where: { typeContainsAnyTypeParam($0, types: types) }) { return true }
            if let receiver = ft.receiver, typeContainsAnyTypeParam(receiver, types: types) { return true }
            if ft.params.contains(where: { typeContainsAnyTypeParam($0, types: types) }) { return true }
            return typeContainsAnyTypeParam(ft.returnType, types: types)
        case let .intersection(parts):
            return parts.contains { typeContainsAnyTypeParam($0, types: types) }
        case let .kClassType(kct):
            return typeContainsAnyTypeParam(kct.argument, types: types)
        default:
            return false
        }
    }

    private func findAllInheritedMembers(
        named memberName: InternedString,
        for classSymbol: SymbolID,
        symbols: SymbolTable
    ) -> [OFOInheritedMember] {
        var visited: Set<SymbolID> = [classSymbol]
        var queue = inheritedScanSupertypes(for: classSymbol, symbols: symbols)
        var results: [OFOInheritedMember] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            guard let sym = symbols.symbol(current) else { continue }

            var foundAtThisLevel = false
            for childID in symbols.declaredChildren(of: current) {
                guard let child = symbols.symbol(childID) else { continue }
                guard isInheritedMember(child, from: sym) else { continue }
                let isMatch = child.kind == .function || child.kind == .property
                if isMatch, child.name == memberName {
                    // An expect-declared member resolves to its linked actual
                    // declaration; deduplicate when both sides surface here.
                    let resolvedChildID = resolveInheritedMember(childID, symbols: symbols)
                    if !results.contains(where: { $0.memberID == resolvedChildID }) {
                        results.append(OFOInheritedMember(
                            memberID: resolvedChildID,
                            ownerName: sym.name,
                            ownerIsInterface: sym.kind == .interface
                        ))
                    }
                    foundAtThisLevel = true
                }
            }

            // If this class defines the member, do not traverse its ancestors:
            // ancestor definitions are earlier overrides of the same logical member,
            // not separate overloads.  Continuing upward would inflate the count
            // and cause the guard at the call-site to skip the covariance check.
            if !foundAtThisLevel {
                queue.append(contentsOf: symbols.directSupertypes(for: current))
            }
        }
        return results
    }

}
