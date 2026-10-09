/// Enum entry construction and property storage.
///
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
/// blocks or body/entry stored properties keep the storage-free fast path:
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
        let name: InternedString
        let symbol: SymbolID
        let initializer: ExprID
        let type: TypeID
    }

    /// BUG-205: synthesizes the per-enum-class property helpers (and, when
    /// needed, the entry storage and lazy initializer described above).
    ///
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
                    && sema.symbols.parentSymbol(for: candidate) == ownerSymbol
            }) ?? .invalid
        }
        guard !entrySymbols.contains(.invalid) else { return [] }

        let params = classDecl.primaryConstructorParams
        let parameterNames = params.map(\.name)
        let argumentMappings = classDecl.enumEntries.map {
            $0.constructorArgumentMapping(parameterNames: parameterNames).argumentIndexByParameter
        }

        // Stored properties, keyed by name in declaration order.
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
        let entryBodyProperties: [[EnumEntryBodyProperty]] = classDecl.enumEntries.map { entry in
            entry.memberProperties.compactMap { declID in
                guard let decl = ast.arena.decl(declID),
                      case let .propertyDecl(property) = decl,
                      isPlainStoredEnumProperty(property),
                      let initializer = property.initializer,
                      let propertySymbol = sema.bindings.declSymbols[declID]
                else {
                    return nil
                }
                let type = classPropertySymbol(named: property.name).flatMap { sema.symbols.propertyType(for: $0) }
                    ?? sema.symbols.propertyType(for: propertySymbol)
                    ?? sema.types.anyType
                return EnumEntryBodyProperty(
                    name: property.name, symbol: propertySymbol, initializer: initializer, type: type
                )
            }
        }
        for entryProperties in entryBodyProperties {
            for property in entryProperties {
                let isMutable = classPropertySymbol(named: property.name)
                    .flatMap { sema.symbols.symbol($0)?.flags.contains(.mutable) } ?? false
                addStoredProperty(EnumStoredProperty(name: property.name, type: property.type, isMutable: isMutable))
            }
        }

        let needsStorage = !classDecl.initBlocks.isEmpty
            || !bodyStoredPropertySymbols.isEmpty
            || entryBodyProperties.contains(where: { !$0.isEmpty })
            || zip(classDecl.enumEntries, argumentMappings).contains { entry, mapping in
                params.indices.contains { paramIndex in
                    if let argIndex = mapping[paramIndex] {
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
            argumentMappings: argumentMappings,
            storedProperties: storedProperties,
            bodyStoredPropertySymbols: bodyStoredPropertySymbols,
            entryBodyProperties: entryBodyProperties,
            shared: shared
        )
    }

    /// A property whose value is plain backing storage: no delegate, no
    /// custom accessor body and no explicit backing field.
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

    // MARK: - Helper function shells

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

    /// Emits `switch (unbox(receiver)) { ordinal -> emitCase(ordinal) }`
    /// followed by an unreachable trap; `emitCase` must end its block with a
    /// return or return `false` to fall through to the next ordinal.
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
            symbol: nil,
            callee: interner.intern("kk_abort_unreachable"),
            arguments: [],
            result: fallbackResult,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        ))
        if trapResultType != nil {
            body.append(.returnValue(fallbackResult))
        } else {
            body.append(.returnUnit)
        }
    }

    /// Builds one getter helper `(receiver: Any) -> T` and appends it.
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
        let anyType = sema.types.anyType
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
                parameterTypes: [anyType],
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
            let receiverRef = arena.appendExpr(.symbolRef(receiverParamSymbol), type: anyType)
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
            params: [KIRParameter(symbol: receiverParamSymbol, type: anyType)],
            returnType: property.type,
            body: helperBody,
            isSuspend: false,
            isInline: false,
            sourceRange: nil
        ))))
        declIDs.append(contentsOf: generatedDecls)
    }

    // MARK: - Literal fast path

    private func synthesizeLiteralEnumPropertyGetters(
        classDecl: ClassDecl,
        ownerInfo: SemanticSymbol,
        argumentMappings: [[Int?]],
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
                if let argIndex = argumentMappings[ordinal][paramIndex] {
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

    // MARK: - Entry storage + lazy initializer

    private func synthesizeEnumEntryStorage(
        classDecl: ClassDecl,
        ownerInfo: SemanticSymbol,
        entrySymbols: [SymbolID],
        argumentMappings: [[Int?]],
        storedProperties: [EnumStoredProperty],
        bodyStoredPropertySymbols: [InternedString: SymbolID],
        entryBodyProperties: [[EnumEntryBodyProperty]],
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

            let ctorSignature = primaryConstructorSignature(classDecl: classDecl, sema: sema)
            let enumType = sema.types.make(.classType(ClassType(
                classSymbol: ownerSymbol, args: [], nullability: .nonNull
            )))
            for (ordinal, entry) in classDecl.enumEntries.enumerated() {
                let entrySymbol = entrySymbols[ordinal]
                let thisExpr = arena.appendExpr(.symbolRef(entrySymbol), type: enumType)
                body.append(.constValue(result: thisExpr, value: .symbolRef(entrySymbol)))
                ctx.setImplicitReceiver(symbol: entrySymbol, exprID: thisExpr)

                // Constructor arguments: explicit ones in source order, then
                // defaults in parameter order with earlier parameters bound.
                let params = classDecl.primaryConstructorParams
                var argumentValues = [KIRExprID?](repeating: nil, count: params.count)
                let paramIndexByArg = Dictionary(
                    argumentMappings[ordinal].enumerated().compactMap { paramIndex, argIndex in
                        argIndex.map { ($0, paramIndex) }
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                for (argIndex, arg) in entry.constructorArgs.enumerated() {
                    let value = lowerExpr(arg.expr, shared: shared, emit: &body)
                    if let paramIndex = paramIndexByArg[argIndex] {
                        argumentValues[paramIndex] = value
                    }
                }
                var boundParameterSymbols: [SymbolID] = []
                func bind(_ paramIndex: Int, _ value: KIRExprID) {
                    guard let signature = ctorSignature,
                          paramIndex < signature.valueParameterSymbols.count
                    else { return }
                    let parameterSymbol = signature.valueParameterSymbols[paramIndex]
                    ctx.setLocalValue(value, for: parameterSymbol)
                    boundParameterSymbols.append(parameterSymbol)
                }
                for (paramIndex, value) in argumentValues.enumerated() {
                    if let value { bind(paramIndex, value) }
                }
                for (paramIndex, param) in params.enumerated() where argumentValues[paramIndex] == nil {
                    let value: KIRExprID
                    if let defaultExpr = param.defaultValue {
                        value = lowerExpr(defaultExpr, shared: shared, emit: &body)
                    } else {
                        let paramType = ctorSignature.flatMap { signature in
                            paramIndex < signature.parameterTypes.count ? signature.parameterTypes[paramIndex] : nil
                        } ?? sema.types.anyType
                        let defaultValue = delegationDefaultValue(for: paramType, sema: sema)
                        value = arena.appendExpr(defaultValue, type: paramType)
                        body.append(.constValue(result: value, value: defaultValue))
                    }
                    argumentValues[paramIndex] = value
                    bind(paramIndex, value)
                }

                for (paramIndex, param) in params.enumerated() where param.isProperty {
                    guard let value = argumentValues[paramIndex],
                          let slotSymbol = classSlots[ordinal][param.name],
                          let property = storedProperties.first(where: { $0.name == param.name })
                    else { continue }
                    let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: property.type)
                    body.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
                    body.append(.copy(from: value, to: slotRef))
                }

                // Class body: property initializers and `init` blocks in
                // source order, writing into this entry's slots.
                ctx.enumEntryStorageSlots = Dictionary(
                    uniqueKeysWithValues: bodyStoredPropertySymbols.compactMap { name, propertySymbol in
                        classSlots[ordinal][name].map { (propertySymbol, $0) }
                    }
                )
                emitClassBodyInitializers(classDecl: classDecl, shared: shared, body: &body)
                ctx.enumEntryStorageSlots = [:]

                // Entry body (`A { override val x = ... }`) runs after the
                // enum class constructor, like a subclass initializer.
                for property in entryBodyProperties[ordinal] {
                    guard let slotSymbol = entrySlots[ordinal][property.name] else { continue }
                    let value = lowerExpr(property.initializer, shared: shared, emit: &body)
                    let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: property.type)
                    body.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
                    body.append(.copy(from: value, to: slotRef))
                }

                for parameterSymbol in boundParameterSymbols {
                    ctx.clearLocalValue(for: parameterSymbol)
                }
                ctx.clearImplicitReceiver()
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
            body.append(.call(
                symbol: ensureInitSymbol,
                callee: ensureInitName,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
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
                guard let slotSymbol = slot(for: property.name, ordinal: ordinal) else { return nil }
                let value = arena.appendExpr(.symbolRef(slotSymbol), type: property.type)
                body.append(.loadGlobal(result: value, symbol: slotSymbol))
                return value
            }

            guard property.isMutable else { continue }
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

    private func primaryConstructorSignature(classDecl: ClassDecl, sema: SemaModule) -> FunctionSignature? {
        sema.symbols.symbols(atDeclSite: classDecl.range)
            .first(where: { sema.symbols.symbol($0)?.kind == .constructor })
            .flatMap { sema.symbols.functionSignature(for: $0) }
    }

    // MARK: - Lazy-init trigger

    /// Inserts a call to the owning enum's lazy initializer in front of
    /// every entry reference lowered in this compilation, so `init` blocks
    /// and argument side effects run on first access to the enum, as on the
    /// JVM, rather than eagerly or never.
    func insertEnumLazyInitTriggers(arena: KIRArena, sema: SemaModule) {
        let lazyInits = ctx.enumLazyInitByOwner
        guard !lazyInits.isEmpty else { return }
        let ensureInitSymbols = Set(lazyInits.values.map(\.symbol))
        var ownerByEntry: [SymbolID: SymbolID] = [:]
        func lazyInitOwner(of symbol: SymbolID) -> SymbolID? {
            if let cached = ownerByEntry[symbol] { return cached == .invalid ? nil : cached }
            var owner = SymbolID.invalid
            if sema.symbols.symbol(symbol)?.kind == .field,
               let parent = sema.symbols.parentSymbol(for: symbol),
               lazyInits[parent] != nil
            {
                owner = parent
            }
            ownerByEntry[symbol] = owner
            return owner == .invalid ? nil : owner
        }
        let unitType = sema.types.unitType
        arena.transformFunctions { function in
            guard !ensureInitSymbols.contains(function.symbol) else { return function }
            var needsRewrite = false
            for instruction in function.body {
                switch instruction {
                case let .constValue(_, .symbolRef(symbol)), let .loadGlobal(_, symbol):
                    if lazyInitOwner(of: symbol) != nil { needsRewrite = true }
                default:
                    break
                }
                if needsRewrite { break }
            }
            guard needsRewrite else { return function }
            var newBody: [KIRInstruction] = []
            var newLocations: [SourceRange?] = []
            newBody.reserveCapacity(function.body.count + 4)
            for (index, instruction) in function.body.enumerated() {
                let location = index < function.instructionLocations.count ? function.instructionLocations[index] : nil
                let referenced: SymbolID? = switch instruction {
                case let .constValue(_, .symbolRef(symbol)), let .loadGlobal(_, symbol):
                    symbol
                default:
                    nil
                }
                if let referenced, let owner = lazyInitOwner(of: referenced), let lazyInit = lazyInits[owner] {
                    newBody.append(.call(
                        symbol: lazyInit.symbol,
                        callee: lazyInit.name,
                        arguments: [],
                        result: arena.appendTemporary(type: unitType),
                        canThrow: false,
                        thrownResult: nil
                    ))
                    newLocations.append(location)
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
