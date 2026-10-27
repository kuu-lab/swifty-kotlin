/// Enum values stay ordinal-backed (a boxed ordinal at `Any` boundaries), so
/// an entry has no heap object to hold its fields. Each enum class instead
/// gets per-entry side storage: one global slot per (entry, stored property),
/// filled exactly once by a guarded lazy initializer (`$enumEnsureInit$`)
/// that mirrors JVM `<clinit>`: for every entry in declaration order it binds
/// the constructor arguments (by label, with defaults that may refer to
/// earlier parameters), stores the constructor properties, runs the class
/// body's property initializers and `init` blocks, then the entry body's own
/// property initializers. Property reads/writes go through the
/// `$enumConstructorProperty$<name>` / `$enumPropertySetter$<name>` helpers,
/// which switch on the ordinal and touch the matching slot.
///
/// Enums whose entries only pass literal arguments and have no `init`
/// blocks, varargs or body/entry stored properties keep the storage-free fast path:
/// the getter helper returns the literal for the receiver's ordinal.
enum EnumPropertyHelperNames {
    static let getterPrefix = "$enumConstructorProperty$"
    static let setterPrefix = "$enumPropertySetter$"
    static let ensureInitName = "$enumEnsureInit$"

    /// Caller-side placeholder callee (`<prefix><ownerID>$<property>`); the
    /// owner symbol rawValue is not stable across .kklib boundaries, so
    /// `EnumNameAccessLoweringPass` rewrites it to the ID-free helper.
    static func placeholder(
        prefix: String,
        ownerSymbol: SymbolID,
        propertyName: InternedString,
        interner: StringInterner
    ) -> InternedString {
        interner.intern("\(prefix)\(ownerSymbol.rawValue)$\(interner.resolve(propertyName))")
    }
}

extension KIRLoweringDriver {
    private struct EnumStoredProperty {
        let name: InternedString
        let type: TypeID
        let isMutable: Bool
    }

    private struct EnumEntryBodyProperty {
        let propertyIndex: Int
        let name: InternedString
        let symbol: SymbolID
        let initializer: ExprID?
        let type: TypeID
    }

    private typealias EnumEntryBodyGetterSymbols = [[InternedString: SymbolID]]

    /// The helper names are intentionally free of the owner symbol's
    /// rawValue: symbol IDs are re-assigned on .kklib import, so an ID-bearing
    /// name would make the helper's fqName unresolvable for consumers. The
    /// enum's fqName already scopes the helper, so the property name alone is
    /// unique.
    func synthesizeEnumConstructorPropertyHelperFunctions(
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx _: CompilationContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let ast = shared.ast
        let interner = shared.interner
        guard let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .enumClass,
              !classDecl.enumEntries.isEmpty
        else {
            return []
        }
        let ensureInitFQName = ownerInfo.fqName + [interner.intern(EnumPropertyHelperNames.ensureInitName)]
        guard sema.symbols.lookupAll(fqName: ensureInitFQName).isEmpty else {
            return []
        }

        let entrySymbols: [SymbolID] = classDecl.enumEntries.map { entry in
            sema.symbols.lookupAll(fqName: ownerInfo.fqName + [entry.name]).first(where: { candidate in
                sema.symbols.symbol(candidate)?.kind == .field
                    && sema.symbols.parentSymbolIfKnown(for: candidate) == ownerSymbol
            }) ?? .invalid
        }
        guard !entrySymbols.contains(.invalid) else { return [] }

        let params = classDecl.primaryConstructorParams
        let primaryConstructorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
            .first(where: { sema.symbols.symbol($0)?.kind == .constructor })
        let primaryConstructorSignature = primaryConstructorSymbol.flatMap {
            sema.symbols.functionSignature(for: $0)
        }
            ?? FunctionSignature(parameterTypes: [], returnType: sema.types.unitType, isSuspend: false)
        let entryConstructorBindings = entrySymbols.map {
            sema.bindings.enumEntryConstructorBinding(for: $0)
        }
        let argumentMappings = classDecl.enumEntries.enumerated().map { index, entry in
            if let binding = entryConstructorBindings[index],
               binding.chosenCallee == primaryConstructorSymbol
            {
                return binding.parameterMapping
            }
            guard primaryConstructorSymbol != nil else { return [:] }
            return OverloadResolver().buildParameterMapping(
                signature: primaryConstructorSignature,
                callArgs: entry.constructorArgs.map {
                    CallArg.source(
                        $0,
                        type: sema.bindings.exprTypes[$0.expr] ?? sema.types.anyType,
                        callRange: entry.range,
                        ast: ast
                    )
                },
                symbols: sema.symbols,
                typeSystem: sema.types
            ) ?? [:]
        }

        var storedProperties: [EnumStoredProperty] = []
        var storedPropertyIndexByName: [InternedString: Int] = [:]
        func addStoredProperty(_ property: EnumStoredProperty) {
            guard storedPropertyIndexByName[property.name] == nil else { return }
            storedPropertyIndexByName[property.name] = storedProperties.count
            storedProperties.append(property)
        }
        func classPropertySymbol(named name: InternedString) -> SymbolID? {
            sema.symbols.lookupAll(fqName: ownerInfo.fqName + [name])
                .first(where: { sema.symbols.symbol($0)?.kind == .property })
        }

        for param in params where param.isProperty {
            guard let propertySymbol = classPropertySymbol(named: param.name) else { continue }
            addStoredProperty(EnumStoredProperty(
                name: param.name,
                type: sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType,
                isMutable: param.isMutableProperty
            ))
        }
        var bodyStoredPropertySymbols: [InternedString: SymbolID] = [:]
        for declID in classDecl.memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl,
                  !property.isSynthesizedPrimaryConstructorProperty,
                  isPlainStoredEnumProperty(property),
                  // A `val` without initializer is assigned in an `init` block.
                  !property.modifiers.contains(.abstract),
                  let propertySymbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            bodyStoredPropertySymbols[property.name] = propertySymbol
            addStoredProperty(EnumStoredProperty(
                name: property.name,
                type: sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType,
                isMutable: property.isVar
            ))
        }
        // Enum values are represented by ordinals, so delegated-property
        // handles need per-entry side storage just like ordinary body fields.
        // Key the initialization slot by the source property symbol because
        // emitDelegatePropertyInitializer stores through that symbol.
        for declID in classDecl.memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl,
                  property.delegateExpression != nil,
                  let propertySymbol = sema.bindings.declSymbols[declID],
                  let delegateStorageSymbol = sema.symbols.delegateStorageSymbol(for: propertySymbol),
                  let storageSymbol = sema.symbols.symbol(delegateStorageSymbol)
            else {
                continue
            }
            bodyStoredPropertySymbols[storageSymbol.name] = propertySymbol
            addStoredProperty(EnumStoredProperty(
                name: storageSymbol.name,
                type: sema.types.anyType,
                isMutable: false
            ))
        }
        // Class-delegation handles (`enum class E : I by expr`) are per-entry
        // state too: an enum value is ordinal-backed and has no heap object to
        // hold the delegate, so it gets the same per-entry global slot an
        // ordinary stored property does. The delegate expression is evaluated
        // once per entry in $enumEnsureInit$, and the synthesized forwarding
        // members read the slot back through the ordinal-switch getter.
        for interfaceSymbol in sema.symbols.delegatedInterfaces(forClass: ownerSymbol) {
            guard let fieldSymbol = sema.symbols.classDelegationField(
                forClass: ownerSymbol,
                interface: interfaceSymbol
            ),
                  let fieldInfo = sema.symbols.symbol(fieldSymbol)
            else {
                continue
            }
            bodyStoredPropertySymbols[fieldInfo.name] = fieldSymbol
            addStoredProperty(EnumStoredProperty(
                name: fieldInfo.name,
                type: sema.symbols.propertyType(for: fieldSymbol) ?? sema.types.anyType,
                isMutable: false
            ))
        }
        let entryBodyProperties: [[EnumEntryBodyProperty]] = classDecl.enumEntries.map { entry in
            entry.memberProperties.enumerated().compactMap { propertyIndex, declID in
                guard let decl = ast.arena.decl(declID),
                      case let .propertyDecl(property) = decl,
                      isPlainStoredEnumProperty(property),
                      property.receiverType == nil,
                      !property.modifiers.contains(.abstract),
                      let propertySymbol = sema.bindings.declSymbols[declID]
                else {
                    return nil
                }
                let type = classPropertySymbol(named: property.name).flatMap { sema.symbols.propertyType(for: $0) }
                    ?? sema.symbols.propertyType(for: propertySymbol)
                    ?? sema.types.anyType
                return EnumEntryBodyProperty(
                    propertyIndex: propertyIndex,
                    name: property.name,
                    symbol: propertySymbol,
                    initializer: property.initializer,
                    type: type
                )
            }
        }
        let entryBodyGetterSymbols: EnumEntryBodyGetterSymbols = classDecl.enumEntries.map { entry in
            var getterSymbols: [InternedString: SymbolID] = [:]
            for declID in entry.memberProperties {
                guard let decl = ast.arena.decl(declID),
                      case let .propertyDecl(property) = decl,
                      property.getter.map({ $0.body != .unit }) == true,
                      let propertySymbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                getterSymbols[property.name] = propertySymbol
            }
            return getterSymbols
        }
        for entryProperties in entryBodyProperties {
            for property in entryProperties {
                let isMutable = classPropertySymbol(named: property.name)
                    .flatMap { sema.symbols.symbol($0)?.flags.contains(.mutable) }
                    ?? sema.symbols.symbol(property.symbol)?.flags.contains(.mutable)
                    ?? false
                addStoredProperty(EnumStoredProperty(name: property.name, type: property.type, isMutable: isMutable))
            }
        }
        for getterSymbols in entryBodyGetterSymbols {
            for (name, propertySymbol) in getterSymbols {
                let type = classPropertySymbol(named: name).flatMap { sema.symbols.propertyType(for: $0) }
                    ?? sema.symbols.propertyType(for: propertySymbol)
                    ?? sema.types.anyType
                addStoredProperty(EnumStoredProperty(name: name, type: type, isMutable: false))
            }
        }

        // Even literal/empty varargs are arrays with observable identity and
        // mutation. Pack them once in the entry initializer, never in a getter.
        // A mutable stored property likewise needs a real slot: the literal
        // path only emits getter helpers that re-lower the constructor
        // argument per read, so `var` writes (`M.P.v = 99`, property-ref
        // `set`) would have nowhere to go.
        let needsStorage = params.contains(where: \.isVararg)
            || storedProperties.contains(where: \.isMutable)
            || entryConstructorBindings.contains { binding in
                guard let chosen = binding?.chosenCallee else { return false }
                return chosen != primaryConstructorSymbol
            }
            || !classDecl.initBlocks.isEmpty
            || classDecl.enumEntries.contains(where: { !$0.initBlocks.isEmpty })
            || !bodyStoredPropertySymbols.isEmpty
            || entryBodyProperties.contains(where: { !$0.isEmpty })
            || entryBodyGetterSymbols.contains(where: { !$0.isEmpty })
            || zip(classDecl.enumEntries, argumentMappings).contains { entry, mapping in
                params.indices.contains { paramIndex in
                    if let argIndex = mapping.first(where: { $0.value == paramIndex })?.key {
                        return !isPureLiteralExpr(entry.constructorArgs[argIndex].expr, ast: ast, interner: interner)
                    }
                    guard let defaultExpr = params[paramIndex].defaultValue else { return false }
                    return !isPureLiteralExpr(defaultExpr, ast: ast, interner: interner)
                }
            }

        if !needsStorage {
            return synthesizeLiteralEnumPropertyGetters(
                classDecl: classDecl,
                ownerInfo: ownerInfo,
                argumentMappings: argumentMappings,
                storedProperties: storedProperties,
                shared: shared
            )
        }

        return synthesizeEnumEntryStorage(
            classDecl: classDecl,
            ownerInfo: ownerInfo,
            entrySymbols: entrySymbols,
            entryConstructorBindings: entryConstructorBindings,
            argumentMappings: argumentMappings,
            primaryConstructorSymbol: primaryConstructorSymbol,
            storedProperties: storedProperties,
            bodyStoredPropertySymbols: bodyStoredPropertySymbols,
            entryBodyProperties: entryBodyProperties,
            entryBodyGetterSymbols: entryBodyGetterSymbols,
            shared: shared
        )
    }

    private func isPlainStoredEnumProperty(_ property: PropertyDecl) -> Bool {
        property.delegateExpression == nil
            && property.explicitBackingField == nil
            && (property.getter?.body ?? .unit) == .unit
            && (property.setter?.body ?? .unit) == .unit
    }

    /// Literals can be re-lowered on every read without observable effects.
    private func isPureLiteralExpr(_ exprID: ExprID, ast: ASTModule, interner: StringInterner) -> Bool {
        switch ast.arena.expr(exprID) {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral,
             .doubleLiteral, .charLiteral, .boolLiteral, .stringLiteral, .nullLiteral:
            true
        case let .unaryExpr(_, operand, _):
            isPureLiteralExpr(operand, ast: ast, interner: interner)
        default:
            false
        }
    }


    private func defineEnumHelperSymbol(
        name: InternedString,
        ownerInfo: SemanticSymbol,
        declSite: SourceRange,
        sema: SemaModule
    ) -> SymbolID {
        let symbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: ownerInfo.fqName + [name],
            declSite: declSite,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        // The parent link is what lets metadata export treat this helper
        // as an enum-class member (and lets consumers resolve it).
        sema.symbols.setParentSymbol(ownerInfo.id, for: symbol)
        return symbol
    }

    private func defineEnumHelperParameter(
        named name: String,
        helperSymbol: SymbolID,
        declSite: SourceRange,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID {
        let paramName = interner.intern(name)
        let helperFQName = sema.symbols.symbol(helperSymbol)?.fqName ?? []
        let symbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: helperFQName + [paramName],
            declSite: declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setParentSymbol(helperSymbol, for: symbol)
        return symbol
    }

    private func helperFunctionExists(
        name: InternedString,
        ownerInfo: SemanticSymbol,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.lookupAll(fqName: ownerInfo.fqName + [name])
            .contains(where: { sema.symbols.symbol($0)?.kind == .function })
    }

    /// `emitCase` must end its block with a return or return `false` to fall
    /// through to the next ordinal.
    private func emitEnumOrdinalSwitch(
        receiver: KIRExprID,
        entryCount: Int,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        trapResultType: TypeID?,
        body: inout KIRLoweringEmitContext,
        emitCase: (Int, inout KIRLoweringEmitContext) -> Bool
    ) {
        let intType = sema.types.intType
        let unboxedOrdinal = emitNonThrowingCall(
            callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
            arg: receiver,
            resultType: intType,
            arena: arena,
            into: &body.instructions
        )
        for ordinal in 0 ..< entryCount {
            let ordinalExpr = arena.appendExpr(.intLiteral(Int64(ordinal)), type: intType)
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            let matchLabel = ctx.makeLoopLabel()
            let nextLabel = ctx.makeLoopLabel()
            body.append(.jumpIfEqual(lhs: unboxedOrdinal, rhs: ordinalExpr, target: matchLabel))
            body.append(.jump(nextLabel))
            body.append(.label(matchLabel))
            if !emitCase(ordinal, &body) {
                body.append(.jump(nextLabel))
            }
            body.append(.label(nextLabel))
        }
        let fallbackResult = arena.appendTemporary(type: trapResultType ?? sema.types.unitType)
        body.append(.call(
            callee: interner.intern("kk_abort_unreachable"),
            arguments: [],
            result: fallbackResult,
            canThrow: false,
            isSuperCall: false
        ))
        if trapResultType != nil {
            body.append(.returnValue(fallbackResult))
        } else {
            body.append(.returnUnit)
        }
    }

    private func appendEnumGetterHelper(
        property: EnumStoredProperty,
        ownerInfo: SemanticSymbol,
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        declIDs: inout [KIRDeclID],
        emitPrologue: (inout KIRLoweringEmitContext) -> Void = { _ in },
        emitCase: (Int, inout KIRLoweringEmitContext) -> KIRExprID?
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: ownerInfo.id, args: [], nullability: .nonNull
        )))
        let helperName = interner.intern(EnumPropertyHelperNames.getterPrefix + interner.resolve(property.name))
        guard !helperFunctionExists(name: helperName, ownerInfo: ownerInfo, sema: sema) else { return }
        let helperSymbol = defineEnumHelperSymbol(
            name: helperName, ownerInfo: ownerInfo, declSite: classDecl.range, sema: sema
        )
        let receiverParamSymbol = defineEnumHelperParameter(
            named: "$receiver", helperSymbol: helperSymbol, declSite: classDecl.range, sema: sema, interner: interner
        )
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [receiverType],
                returnType: property.type,
                isSuspend: false,
                canThrow: false,
                valueParameterSymbols: [receiverParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: helperSymbol
        )

        let helperBody = ctx.withNewScope { () -> [KIRInstruction] in
            ctx.setCurrentFunctionSymbol(helperSymbol)
            ctx.beginCallableLoweringScope()
            let receiverRef = arena.appendExpr(.symbolRef(receiverParamSymbol), type: receiverType)
            var body: KIRLoweringEmitContext = [.beginBlock]
            body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParamSymbol)))
            emitPrologue(&body)
            emitEnumOrdinalSwitch(
                receiver: receiverRef,
                entryCount: classDecl.enumEntries.count,
                sema: sema, arena: arena, interner: interner,
                trapResultType: property.type,
                body: &body
            ) { ordinal, caseBody in
                guard let value = emitCase(ordinal, &caseBody) else { return false }
                caseBody.append(.returnValue(value))
                return true
            }
            body.append(.endBlock)
            return body.instructions
        }
        let generatedDecls = ctx.drainGeneratedCallableDecls()
        declIDs.append(arena.appendDecl(.function(KIRFunction(
            symbol: helperSymbol,
            name: helperName,
            params: [KIRParameter(symbol: receiverParamSymbol, type: receiverType)],
            returnType: property.type,
            body: helperBody,
            isSuspend: false,
            isInline: false,
            sourceRange: nil
        ))))
        declIDs.append(contentsOf: generatedDecls)
    }


    private func synthesizeLiteralEnumPropertyGetters(
        classDecl: ClassDecl,
        ownerInfo: SemanticSymbol,
        argumentMappings: [[Int: Int]],
        storedProperties: [EnumStoredProperty],
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        var declIDs: [KIRDeclID] = []
        for (paramIndex, param) in classDecl.primaryConstructorParams.enumerated() where param.isProperty {
            guard let property = storedProperties.first(where: { $0.name == param.name }) else { continue }
            appendEnumGetterHelper(
                property: property,
                ownerInfo: ownerInfo,
                classDecl: classDecl,
                shared: shared,
                declIDs: &declIDs
            ) { ordinal, body in
                let entry = classDecl.enumEntries[ordinal]
                if let argIndex = argumentMappings[ordinal].first(where: { $0.value == paramIndex })?.key {
                    return lowerExpr(entry.constructorArgs[argIndex].expr, shared: shared, emit: &body)
                }
                if let defaultExpr = param.defaultValue {
                    return lowerExpr(defaultExpr, shared: shared, emit: &body)
                }
                let defaultValue = delegationDefaultValue(for: property.type, sema: sema)
                let valueExpr = arena.appendExpr(defaultValue, type: property.type)
                body.append(.constValue(result: valueExpr, value: defaultValue))
                return valueExpr
            }
        }
        return declIDs
    }


    private func synthesizeEnumEntryStorage(
        classDecl: ClassDecl,
        ownerInfo: SemanticSymbol,
        entrySymbols: [SymbolID],
        entryConstructorBindings: [CallBinding?],
        argumentMappings: [[Int: Int]],
        primaryConstructorSymbol: SymbolID?,
        storedProperties: [EnumStoredProperty],
        bodyStoredPropertySymbols: [InternedString: SymbolID],
        entryBodyProperties: [[EnumEntryBodyProperty]],
        entryBodyGetterSymbols: EnumEntryBodyGetterSymbols,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let ownerSymbol = ownerInfo.id
        var declIDs: [KIRDeclID] = []

        // Slot globals live under a pseudo-scope so they are not mistaken for
        // enum entries (direct `.field` children of the enum's fqName).
        let storageScope = ownerInfo.fqName + [interner.intern("$enumStorage")]
        func defineGlobal(_ name: String, type: TypeID) -> SymbolID {
            let interned = interner.intern(name)
            let symbol = sema.symbols.define(
                kind: .field, name: interned, fqName: storageScope + [interned],
                declSite: nil, visibility: .private, flags: [.synthetic]
            )
            declIDs.append(arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: type))))
            return symbol
        }

        // classSlots[ordinal][name] holds class-level storage (constructor and
        // body properties); entrySlots[ordinal][name] holds an entry-body
        // override, which takes precedence on reads and writes.
        var classSlots: [[InternedString: SymbolID]] = []
        var entrySlots: [[InternedString: SymbolID]] = []
        let classLevelNames = Set(
            classDecl.primaryConstructorParams.filter(\.isProperty).map(\.name)
        ).union(bodyStoredPropertySymbols.keys)
        for (ordinal, entry) in classDecl.enumEntries.enumerated() {
            let entryName = interner.resolve(entry.name)
            var slots: [InternedString: SymbolID] = [:]
            for property in storedProperties where classLevelNames.contains(property.name) {
                slots[property.name] = defineGlobal("\(entryName)$\(interner.resolve(property.name))", type: property.type)
            }
            classSlots.append(slots)
            var overrides: [InternedString: SymbolID] = [:]
            for property in entryBodyProperties[ordinal] {
                overrides[property.name] = defineGlobal(
                    "\(entryName)$body$\(interner.resolve(property.name))", type: property.type
                )
            }
            entrySlots.append(overrides)
        }
        func slot(for name: InternedString, ordinal: Int) -> SymbolID? {
            entrySlots[ordinal][name] ?? classSlots[ordinal][name]
        }

        let flagSymbol = defineGlobal("$initialized", type: sema.types.booleanType)
        let ensureInitName = interner.intern(EnumPropertyHelperNames.ensureInitName)
        let ensureInitSymbol = defineEnumHelperSymbol(
            name: ensureInitName, ownerInfo: ownerInfo, declSite: classDecl.range, sema: sema
        )
        sema.symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: sema.types.unitType, isSuspend: false),
            for: ensureInitSymbol
        )

        let ensureInitBody = ctx.withNewScope { () -> [KIRInstruction] in
            ctx.setCurrentFunctionSymbol(ensureInitSymbol)
            ctx.beginCallableLoweringScope()
            var body: KIRLoweringEmitContext = [.beginBlock]
            let boolType = sema.types.booleanType
            let trueExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
            body.append(.constValue(result: trueExpr, value: .boolLiteral(true)))
            let flagLoadExpr = arena.appendExpr(.symbolRef(flagSymbol), type: boolType)
            body.append(.loadGlobal(result: flagLoadExpr, symbol: flagSymbol))
            let doneLabel = ctx.makeLoopLabel()
            body.append(.jumpIfEqual(lhs: flagLoadExpr, rhs: trueExpr, target: doneLabel))
            // Set the flag before constructing entries so reentrant reads
            // from initializers (e.g. `init { println(id) }`) do not recurse.
            body.append(.storeGlobal(value: trueExpr, symbol: flagSymbol))
            let initializerInstructionsStart = body.count

            // KUU-3225: `$enumEnsureInit$` is the enum class's <clinit> —
            // on the JVM its supertype companions initialize before any
            // entry is constructed.
            emitSupertypeCompanionInitCalls(
                for: ownerSymbol, sema: sema, arena: arena, interner: interner,
                instructions: &body.instructions
            )

            let enumType = sema.types.make(.classType(ClassType(
                classSymbol: ownerSymbol, args: [], nullability: .nonNull
            )))
            for (ordinal, entry) in classDecl.enumEntries.enumerated() {
                let entrySymbol = entrySymbols[ordinal]
                let thisExpr = arena.appendExpr(.symbolRef(entrySymbol), type: enumType)
                body.append(.constValue(result: thisExpr, value: .symbolRef(entrySymbol)))
                ctx.setImplicitReceiver(symbol: entrySymbol, exprID: thisExpr)

                ctx.enumEntryStorageSlots = Dictionary(
                    uniqueKeysWithValues: bodyStoredPropertySymbols.compactMap { name, propertySymbol in
                        classSlots[ordinal][name].map { (propertySymbol, $0) }
                    }
                )
                if let selectedBinding = entryConstructorBindings[ordinal] {
                    let providedArguments = entry.constructorArgs.map {
                        lowerExpr($0.expr, shared: shared, emit: &body)
                    }
                    emitEnumEntryConstructorInitialization(
                        constructorSymbol: selectedBinding.chosenCallee,
                        arguments: entry.constructorArgs,
                        providedArguments: providedArguments,
                        binding: selectedBinding,
                        primaryConstructorSymbol: primaryConstructorSymbol,
                        classDecl: classDecl,
                        ownerSymbol: ownerSymbol,
                        classSlots: classSlots[ordinal],
                        storedProperties: storedProperties,
                        shared: shared,
                        body: &body
                    )
                } else if let primaryConstructorSymbol {
                    // Preserve lowering for enum declarations produced before
                    // entry bindings were recorded, while keeping primary
                    // constructor mapping consistent with Sema when present.
                    let providedArguments = entry.constructorArgs.map {
                        lowerExpr($0.expr, shared: shared, emit: &body)
                    }
                    emitEnumEntryConstructorInitialization(
                        constructorSymbol: primaryConstructorSymbol,
                        arguments: entry.constructorArgs,
                        providedArguments: providedArguments,
                        binding: CallBinding(
                            chosenCallee: primaryConstructorSymbol,
                            substitutedTypeArguments: [],
                            parameterMapping: argumentMappings[ordinal]
                        ),
                        primaryConstructorSymbol: primaryConstructorSymbol,
                        classDecl: classDecl,
                        ownerSymbol: ownerSymbol,
                        classSlots: classSlots[ordinal],
                        storedProperties: storedProperties,
                        shared: shared,
                        body: &body
                    )
                } else {
                    emitClassDelegationInitializers(
                        ownerSymbol: ownerSymbol,
                        receiverID: ctx.activeImplicitReceiverExprID()!,
                        superTypeEntries: classDecl.superTypeEntries,
                        shared: shared,
                        body: &body
                    )
                    emitClassBodyInitializers(classDecl: classDecl, shared: shared, body: &body)
                }
                ctx.enumEntryStorageSlots = [:]

                // Entry body declarations run after the enum class constructor,
                // in their source order, like an anonymous subclass initializer.
                ctx.enumEntryStorageSlots = Dictionary(
                    uniqueKeysWithValues: entryBodyProperties[ordinal].compactMap { property in
                        entrySlots[ordinal][property.name].map { (property.symbol, $0) }
                    }
                )
                let entryBodyInitOrder = entry.classBodyInitOrder.isEmpty
                    ? entry.memberProperties.indices.map(ClassBodyInitMember.property)
                        + entry.initBlocks.indices.map(ClassBodyInitMember.initBlock)
                    : entry.classBodyInitOrder
                for member in entryBodyInitOrder {
                    switch member {
                    case let .property(index):
                        guard let property = entryBodyProperties[ordinal].first(where: {
                                  $0.propertyIndex == index
                              }),
                              let initializer = property.initializer,
                              let slotSymbol = entrySlots[ordinal][property.name]
                        else {
                            continue
                        }
                        let value = lowerExpr(initializer, shared: shared, emit: &body)
                        let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: property.type)
                        body.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
                        body.append(.copy(from: value, to: slotRef))
                    case let .initBlock(index):
                        guard entry.initBlocks.indices.contains(index) else { continue }
                        emitInitBlock(entry.initBlocks[index], shared: shared, body: &body)
                    }
                }
                ctx.enumEntryStorageSlots = [:]

                ctx.clearImplicitReceiver()
            }

            // Kotlin runs the enum's companion object initializer as part of
            // the enum's <clinit>, after the enum entries. Folding the call
            // here lets every enum-API surface trigger full first-access
            // initialization by calling `$enumEnsureInit$` alone — including
            // paths the entry-reference trigger pass cannot see (the
            // synthesized values/valueOf/entries bodies and enumValues).
            if let companionSymbol = sema.symbols.companionObjectSymbolIfKnown(for: ownerSymbol),
               let companionLazyInit = ctx.objectLazyInit(for: companionSymbol)
            {
                let companionInitResult = arena.appendTemporary(type: sema.types.unitType)
                body.append(.call(
                    symbol: companionLazyInit.ensureInitSymbol,
                    callee: companionLazyInit.ensureInitName,
                    arguments: [],
                    result: companionInitResult,
                    canThrow: true
                ))
            }

            var initializerInstructions = KIRLoweringEmitContext(
                Array(body.instructions[initializerInstructionsStart..<body.endIndex])
            )
            initializerInstructions.instructionLocations = Array(
                body.instructionLocations[initializerInstructionsStart..<body.endIndex]
            )
            body.removeSubrange(initializerInstructionsStart..<body.endIndex)

            let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
            let exceptionTypeSlot = arena.appendTemporary(type: sema.types.intType)
            let nullException = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            let unknownType = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            body.append(.constValue(result: nullException, value: .null))
            body.append(.constValue(result: unknownType, value: .intLiteral(0)))
            body.append(.copy(from: nullException, to: exceptionSlot))
            body.append(.copy(from: unknownType, to: exceptionTypeSlot))

            let initializerFailureLabel = ctx.makeLoopLabel()
            controlFlowLowerer.appendThrowAwareInstructions(
                initializerInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: initializerFailureLabel,
                sema: sema,
                interner: interner,
                arena: arena,
                emit: &body
            )
            body.append(.jump(doneLabel))
            body.append(.label(initializerFailureLabel))

            let errorFQName = [interner.intern("kotlin"), interner.intern("Error")]
            let rethrowErrorLabel = ctx.makeLoopLabel()
            if let errorSymbol = sema.symbols.lookup(fqName: errorFQName) {
                let errorType = sema.types.make(.classType(ClassType(
                    classSymbol: errorSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let errorTypeToken = arena.appendExpr(
                    .intLiteral(RuntimeTypeCheckToken.encode(type: errorType, sema: sema, interner: interner)),
                    type: sema.types.intType
                )
                let isError = arena.appendTemporary(type: sema.types.booleanType)
                let trueValue = arena.appendExpr(.boolLiteral(true), type: sema.types.booleanType)
                body.append(.constValue(result: errorTypeToken, value: .intLiteral(
                    RuntimeTypeCheckToken.encode(type: errorType, sema: sema, interner: interner)
                )))
                body.append(.constValue(result: trueValue, value: .boolLiteral(true)))
                body.append(.call(
                    callee: interner.intern("kk_op_is"),
                    arguments: [exceptionSlot, errorTypeToken],
                    result: isError,
                    canThrow: false
                ))
                body.append(.jumpIfEqual(lhs: isError, rhs: trueValue, target: rethrowErrorLabel))
            }

            let wrappedException = arena.appendTemporary(type: sema.types.anyType)
            body.append(.call(
                callee: interner.intern("__kk_exception_in_initializer_error_new_cause"),
                arguments: [exceptionSlot],
                result: wrappedException,
                canThrow: false
            ))
            body.append(.rethrow(value: wrappedException))
            if sema.symbols.lookup(fqName: errorFQName) != nil {
                body.append(.label(rethrowErrorLabel))
                body.append(.rethrow(value: exceptionSlot))
            }

            body.append(.label(doneLabel))
            body.append(.returnUnit)
            body.append(.endBlock)
            return body.instructions
        }
        let ensureInitGeneratedDecls = ctx.drainGeneratedCallableDecls()
        declIDs.append(arena.appendDecl(.function(KIRFunction(
            symbol: ensureInitSymbol,
            name: ensureInitName,
            params: [],
            returnType: sema.types.unitType,
            body: ensureInitBody,
            isSuspend: false,
            isInline: false,
            sourceRange: classDecl.range
        ))))
        declIDs.append(contentsOf: ensureInitGeneratedDecls)
        ctx.registerEnumLazyInit(for: ownerSymbol, symbol: ensureInitSymbol, name: ensureInitName)

        func emitEnsureInit(_ body: inout KIRLoweringEmitContext) {
            let result = arena.appendTemporary(type: sema.types.unitType)
            body.append(.call(symbol: ensureInitSymbol, callee: ensureInitName, arguments: [], result: result, canThrow: true))
        }

        let entryCount = classDecl.enumEntries.count
        for property in storedProperties {
            appendEnumGetterHelper(
                property: property,
                ownerInfo: ownerInfo,
                classDecl: classDecl,
                shared: shared,
                declIDs: &declIDs,
                emitPrologue: emitEnsureInit
            ) { ordinal, body in
                if let propertySymbol = entryBodyGetterSymbols[ordinal][property.name] {
                    let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
                    let getterName = sema.symbols.symbol(getterSymbol)?.name ?? interner.intern("get")
                    let enumType = sema.types.make(.classType(ClassType(
                        classSymbol: ownerSymbol, args: [], nullability: .nonNull
                    )))
                    let entryValue = arena.appendExpr(.symbolRef(entrySymbols[ordinal]), type: enumType)
                    body.append(.constValue(result: entryValue, value: .symbolRef(entrySymbols[ordinal])))
                    let result = arena.appendTemporary(type: property.type)
                    body.append(.call(symbol: getterSymbol, callee: getterName, arguments: [entryValue], result: result, canThrow: true))
                    return result
                }
                guard let slotSymbol = slot(for: property.name, ordinal: ordinal) else { return nil }
                let value = arena.appendExpr(.symbolRef(slotSymbol), type: property.type)
                body.append(.loadGlobal(result: value, symbol: slotSymbol))
                return value
            }

            guard property.isMutable || bodyStoredPropertySymbols[property.name] != nil else { continue }
            let setterName = interner.intern(EnumPropertyHelperNames.setterPrefix + interner.resolve(property.name))
            guard !helperFunctionExists(name: setterName, ownerInfo: ownerInfo, sema: sema) else { continue }
            let setterSymbol = defineEnumHelperSymbol(
                name: setterName, ownerInfo: ownerInfo, declSite: classDecl.range, sema: sema
            )
            let receiverParamSymbol = defineEnumHelperParameter(
                named: "$receiver", helperSymbol: setterSymbol, declSite: classDecl.range, sema: sema, interner: interner
            )
            let valueParamSymbol = defineEnumHelperParameter(
                named: "$value", helperSymbol: setterSymbol, declSite: classDecl.range, sema: sema, interner: interner
            )
            let anyType = sema.types.anyType
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [anyType, property.type],
                    returnType: sema.types.unitType,
                    isSuspend: false,
                    canThrow: false,
                    valueParameterSymbols: [receiverParamSymbol, valueParamSymbol],
                    valueParameterHasDefaultValues: [false, false],
                    valueParameterIsVararg: [false, false]
                ),
                for: setterSymbol
            )
            let setterBody = ctx.withNewScope { () -> [KIRInstruction] in
                ctx.setCurrentFunctionSymbol(setterSymbol)
                ctx.beginCallableLoweringScope()
                let receiverRef = arena.appendExpr(.symbolRef(receiverParamSymbol), type: anyType)
                let valueRef = arena.appendExpr(.symbolRef(valueParamSymbol), type: property.type)
                var body: KIRLoweringEmitContext = [.beginBlock]
                body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParamSymbol)))
                body.append(.constValue(result: valueRef, value: .symbolRef(valueParamSymbol)))
                emitEnsureInit(&body)
                emitEnumOrdinalSwitch(
                    receiver: receiverRef,
                    entryCount: entryCount,
                    sema: sema, arena: arena, interner: interner,
                    trapResultType: nil,
                    body: &body
                ) { ordinal, caseBody in
                    guard let slotSymbol = slot(for: property.name, ordinal: ordinal) else { return false }
                    let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: property.type)
                    caseBody.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
                    caseBody.append(.copy(from: valueRef, to: slotRef))
                    caseBody.append(.returnUnit)
                    return true
                }
                body.append(.endBlock)
                return body.instructions
            }
            let generatedDecls = ctx.drainGeneratedCallableDecls()
            declIDs.append(arena.appendDecl(.function(KIRFunction(
                symbol: setterSymbol,
                name: setterName,
                params: [
                    KIRParameter(symbol: receiverParamSymbol, type: anyType),
                    KIRParameter(symbol: valueParamSymbol, type: property.type),
                ],
                returnType: sema.types.unitType,
                body: setterBody,
                isSuspend: false,
                isInline: false,
                sourceRange: nil
            ))))
            declIDs.append(contentsOf: generatedDecls)
        }
        return declIDs
    }

    /// Inserts guarded enum and companion initialization calls before each
    /// enum entry reference, so entry side effects and companion `init` blocks
    /// run in source access order.
    private func emitEnumEntryConstructorInitialization(
        constructorSymbol: SymbolID,
        arguments: [CallArgument],
        providedArguments: [KIRExprID],
        binding: CallBinding,
        primaryConstructorSymbol: SymbolID?,
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        classSlots: [InternedString: SymbolID],
        storedProperties: [EnumStoredProperty],
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        guard let signature = sema.symbols.functionSignature(for: constructorSymbol) else { return }

        let isPrimary = constructorSymbol == primaryConstructorSymbol
        let constructorDeclSite = sema.symbols.symbol(constructorSymbol)?.declSite
        let secondaryConstructor = classDecl.secondaryConstructors.first {
            $0.range == constructorDeclSite
        }
        let parameters = isPrimary ? classDecl.primaryConstructorParams : secondaryConstructor?.valueParams ?? []
        let normalized = callSupportLowerer.normalizedCallArguments(
            providedArguments: providedArguments,
            callBinding: binding,
            chosenCallee: constructorSymbol,
            spreadFlags: arguments.map(\.isSpread),
            argumentLabels: arguments.map(\.label),
            sourceArgExprs: arguments.map(\.expr),
            ast: shared.ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &body.instructions
        )
        var argumentValues = normalized.arguments
        if argumentValues.count > signature.parameterTypes.count {
            argumentValues = Array(argumentValues.prefix(signature.parameterTypes.count))
        }
        while argumentValues.count < signature.parameterTypes.count {
            let index = argumentValues.count
            let type = constructorParameterStorageType(
                at: index, signature: signature, sema: sema, interner: interner
            )
            let value = delegationDefaultValue(for: type, sema: sema)
            let valueExpr = arena.appendExpr(value, type: type)
            body.append(.constValue(result: valueExpr, value: value))
            argumentValues.append(valueExpr)
        }

        let savedParameterValues = signature.valueParameterSymbols.map { ($0, ctx.localValue(for: $0)) }
        defer {
            for (symbol, value) in savedParameterValues {
                if let value {
                    ctx.setLocalValue(value, for: symbol)
                } else {
                    ctx.clearLocalValue(for: symbol)
                }
            }
        }

        // Enum defaults are evaluated here rather than through the ordinary
        // constructor's fixed-width ABI mask. This also keeps defaults beyond
        // bit 63 and defaults that read earlier parameters intact.
        let suppliedParameters = Set(binding.parameterMapping.values)
        let isVararg = OverloadResolver.normalizeFlags(
            signature.valueParameterIsVararg,
            count: signature.parameterTypes.count
        )
        let defaultedParameters = Set(signature.parameterTypes.indices.filter { index in
            !suppliedParameters.contains(index)
                && (!isVararg[index] || parameters.indices.contains(index) && parameters[index].defaultValue != nil)
        })
        for (index, value) in argumentValues.enumerated() where !defaultedParameters.contains(index) {
            guard signature.valueParameterSymbols.indices.contains(index) else { continue }
            ctx.setLocalValue(value, for: signature.valueParameterSymbols[index])
        }
        for index in defaultedParameters.sorted() where parameters.indices.contains(index) {
            let value: KIRExprID
            if let defaultExpr = parameters[index].defaultValue {
                value = lowerExpr(defaultExpr, shared: shared, emit: &body)
            } else {
                let type = constructorParameterStorageType(
                    at: index, signature: signature, sema: sema, interner: interner
                )
                let defaultValue = delegationDefaultValue(for: type, sema: sema)
                value = arena.appendExpr(defaultValue, type: type)
                body.append(.constValue(result: value, value: defaultValue))
            }
            argumentValues[index] = value
            if signature.valueParameterSymbols.indices.contains(index) {
                ctx.setLocalValue(value, for: signature.valueParameterSymbols[index])
            }
        }

        if isPrimary {
            for (index, parameter) in parameters.enumerated() where parameter.isProperty {
                guard argumentValues.indices.contains(index),
                      let slotSymbol = classSlots[parameter.name],
                      let property = storedProperties.first(where: { $0.name == parameter.name })
                else { continue }
                let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: property.type)
                body.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
                body.append(.copy(from: argumentValues[index], to: slotRef))
            }
            // Class-delegation handles are stored while the constructor
            // parameters are still bound (a delegate expression like `by c`
            // may name one of them), matching the ordinary class order:
            // constructor properties, then delegation, then body initializers.
            emitClassDelegationInitializers(
                ownerSymbol: ownerSymbol,
                receiverID: ctx.activeImplicitReceiverExprID()!,
                superTypeEntries: classDecl.superTypeEntries,
                shared: shared,
                body: &body
            )
            emitClassBodyInitializers(classDecl: classDecl, shared: shared, body: &body)
            return
        }

        guard let secondaryConstructor else {
            emitClassBodyInitializers(classDecl: classDecl, shared: shared, body: &body)
            return
        }

        if let delegation = secondaryConstructor.delegationCall,
           delegation.kind == .this,
           let delegatedConstructor = sema.bindings.constructorDelegationTarget(for: constructorSymbol)
        {
            let delegatedArguments = delegation.args.map {
                lowerExpr($0.expr, shared: shared, emit: &body)
            }
            let delegatedBinding = sema.bindings.constructorDelegationCallBinding(for: constructorSymbol)
                ?? CallBinding(
                    chosenCallee: delegatedConstructor,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                )
            emitEnumEntryConstructorInitialization(
                constructorSymbol: delegatedConstructor,
                arguments: delegation.args,
                providedArguments: delegatedArguments,
                binding: delegatedBinding,
                primaryConstructorSymbol: primaryConstructorSymbol,
                classDecl: classDecl,
                ownerSymbol: ownerSymbol,
                classSlots: classSlots,
                storedProperties: storedProperties,
                shared: shared,
                body: &body
            )
        } else {
            // Constructors without a `this(...)` call reach the superclass
            // directly, so the class property initializers and init blocks run
            // before their own body.
            emitClassDelegationInitializers(
                ownerSymbol: ownerSymbol,
                receiverID: ctx.activeImplicitReceiverExprID()!,
                superTypeEntries: classDecl.superTypeEntries,
                shared: shared,
                body: &body
            )
            emitClassBodyInitializers(classDecl: classDecl, shared: shared, body: &body)
        }

        switch secondaryConstructor.body {
        case let .block(exprIDs, _):
            for exprID in exprIDs {
                _ = lowerExpr(exprID, shared: shared, emit: &body)
            }
        case let .expr(exprID, _):
            _ = lowerExpr(exprID, shared: shared, emit: &body)
        case .unit:
            break
        }
    }

    func insertEnumLazyInitTriggers(arena: KIRArena, sema: SemaModule) {
        let lazyInits = ctx.enumLazyInitByOwner
        var companionLazyInits: [SymbolID: (symbol: SymbolID, name: InternedString)] = [:]
        var enumLazyInitByCompanionLazyInit: [SymbolID: (symbol: SymbolID, name: InternedString)] = [:]
        // A companion is initialized after its enclosing enum. Other nested
        // objects have independent initialization and must not trigger it.
        for enumSymbol in sema.symbols.allSymbols() where enumSymbol.kind == .enumClass {
            guard let companionSymbol = sema.symbols.companionObjectSymbolIfKnown(for: enumSymbol.id) else {
                continue
            }
            let companionLazyInit: (symbol: SymbolID, name: InternedString)?
            if let lazyInit = ctx.objectLazyInit(for: companionSymbol) {
                companionLazyInit = (lazyInit.ensureInitSymbol, lazyInit.ensureInitName)
            } else if let importedInit = sema.symbols.objectLazyInitializerSymbol(for: companionSymbol),
                      let importedSymbol = sema.symbols.symbol(importedInit)
            {
                companionLazyInit = (importedInit, importedSymbol.name)
            } else {
                companionLazyInit = nil
            }
            guard let companionLazyInit else { continue }
            companionLazyInits[enumSymbol.id] = companionLazyInit
            if let enumLazyInit = lazyInits[enumSymbol.id] {
                enumLazyInitByCompanionLazyInit[companionLazyInit.symbol] = enumLazyInit
            }
        }
        guard !lazyInits.isEmpty || !companionLazyInits.isEmpty else { return }
        let ensureInitSymbols = Set(lazyInits.values.map(\.symbol))
        var ownerByEntry: [SymbolID: SymbolID] = [:]
        func enumOwnerForEntry(_ symbol: SymbolID) -> SymbolID? {
            if let cached = ownerByEntry[symbol] { return cached == .invalid ? nil : cached }
            let owner = sema.symbols.symbol(symbol)
                .flatMap { sema.symbols.enumOwnerSymbol(for: $0) } ?? .invalid
            ownerByEntry[symbol] = owner
            guard owner != .invalid,
                  lazyInits[owner] != nil || companionLazyInits[owner] != nil
            else { return nil }
            return owner
        }
        let unitType = sema.types.unitType
        let intType = sema.types.intType
        arena.transformFunctions { function in
            guard !ensureInitSymbols.contains(function.symbol) else { return function }
            var needsRewrite = false
            for instruction in function.body {
                switch instruction {
                case let .constValue(_, .symbolRef(symbol)), let .loadGlobal(_, symbol):
                    if let owner = enumOwnerForEntry(symbol) {
                        let needsCompanionInit = companionLazyInits[owner].map {
                            $0.symbol != function.symbol
                        } ?? false
                        if lazyInits[owner] != nil || needsCompanionInit {
                            needsRewrite = true
                        }
                    }
                case let .call(symbol?, _, _, _, _, _, _, _):
                    if enumLazyInitByCompanionLazyInit[symbol] != nil {
                        needsRewrite = true
                    }
                default:
                    break
                }
                if needsRewrite { break }
            }
            guard needsRewrite else { return function }
            var newBody: [KIRInstruction] = []
            var newLocations: [SourceRange?] = []
            var guardStack: [FinallyGuardThrowContext?] = []
            newBody.reserveCapacity(function.body.count + 4)

            func appendInitializerCall(
                symbol: SymbolID,
                name: InternedString,
                result: KIRExprID,
                location: SourceRange?
            ) {
                func append(_ instruction: KIRInstruction) {
                    newBody.append(instruction)
                    newLocations.append(location)
                }

                guard let context = guardStack.last ?? nil else {
                    append(.call(
                        symbol: symbol,
                        callee: name,
                        arguments: [],
                        result: result,
                        canThrow: true
                    ))
                    return
                }

                append(.call(
                    symbol: symbol,
                    callee: name,
                    arguments: [],
                    result: result,
                    canThrow: true,
                    thrownResult: context.exceptionSlot
                ))
                let unknownType = arena.appendExpr(.intLiteral(0), type: intType)
                append(.constValue(result: unknownType, value: .intLiteral(0)))
                append(.copy(from: unknownType, to: context.exceptionTypeSlot))
                append(.jumpIfNotNull(value: context.exceptionSlot, target: context.thrownTarget))
            }

            for (index, instruction) in function.body.enumerated() {
                let location = index < function.instructionLocations.count ? function.instructionLocations[index] : nil
                switch instruction {
                case .beginFinallyGuard:
                    guardStack.append(resolveGuardRegionThrowContext(body: function.body, beginIndex: index))
                case .endFinallyGuard:
                    _ = guardStack.popLast()
                default:
                    break
                }
                let referenced: SymbolID? = switch instruction {
                case let .constValue(_, .symbolRef(symbol)), let .loadGlobal(_, symbol):
                    symbol
                default:
                    nil
                }
                if case let .call(symbol?, _, _, _, _, _, _, _) = instruction,
                   let enumLazyInit = enumLazyInitByCompanionLazyInit[symbol],
                   enumLazyInit.symbol != function.symbol
                {
                    appendInitializerCall(
                        symbol: enumLazyInit.symbol,
                        name: enumLazyInit.name,
                        result: arena.appendTemporary(type: unitType),
                        location: location
                    )
                }
                if let referenced, let owner = enumOwnerForEntry(referenced) {
                    if let lazyInit = lazyInits[owner] {
                        appendInitializerCall(
                            symbol: lazyInit.symbol,
                            name: lazyInit.name,
                            result: arena.appendTemporary(type: unitType),
                            location: location
                        )
                    }
                    if let companionInit = companionLazyInits[owner],
                       companionInit.symbol != function.symbol
                    {
                        appendInitializerCall(
                            symbol: companionInit.symbol,
                            name: companionInit.name,
                            result: arena.appendTemporary(type: unitType),
                            location: location
                        )
                    }
                }
                newBody.append(instruction)
                newLocations.append(location)
            }
            var updated = function
            updated.replaceBody(newBody, locations: newLocations)
            return updated
        }
    }
}
