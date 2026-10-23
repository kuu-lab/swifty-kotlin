/// This pass must run **before** PropertyLoweringPass and ABILoweringPass.
final class ValueClassUnboxingPass: LoweringPass, ParallelLoweringPass {
    static let name = "ValueClassUnboxing"
    static let requiredStage: KIRStage = .desugared
    static let producedStage: KIRStage = .valueClassUnboxed

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else { return false }
        let symbols = sema.symbols
        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else { continue }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  symbols.effectiveValueClassUnderlyingType(for: nominal.symbol) != nil
            else { continue }
            return true
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols
        let types = sema.types

        var valueClassCtors: Set<SymbolID> = []
        var valueClassSymbols: Set<SymbolID> = []

        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else { continue }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  symbols.effectiveValueClassUnderlyingType(for: nominal.symbol) != nil
            else { continue }

            valueClassSymbols.insert(nominal.symbol)

            let children = symbols.children(ofFQName: sym.fqName)
            for childID in children {
                guard let child = symbols.symbol(childID) else { continue }
                if child.kind == .constructor {
                    valueClassCtors.insert(childID)
                }
            }
        }

        guard !valueClassSymbols.isEmpty else {
            module.recordLowering(Self.name)
            return
        }

        let kk_object_new = ctx.interner.intern("kk_object_new")
        let kk_array_get_inbounds = ctx.interner.intern("kk_array_get_inbounds")

        let interner = ctx.interner

        module.arena.transformFunctions { function in
            var updated = function
            let newBody = self.rewriteBody(
                function.body,
                arena: module.arena,
                interner: interner,
                types: types,
                symbols: symbols,
                valueClassCtors: valueClassCtors,
                valueClassSymbols: valueClassSymbols,
                kk_object_new: kk_object_new,
                kk_array_get_inbounds: kk_array_get_inbounds
            )
            updated.replaceBody(newBody, locations: function.instructionLocations)
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// Nullable value-class-typed expressions are included: a
    /// `kk_array_get_inbounds` property read only ever appears on a receiver
    /// Kotlin's type checker has already proven non-null at that point (e.g.
    /// the non-null branch of a safe call, or the result of `maxByOrNull`
    /// right after its `jumpIfNotNull` guard) — the KIR type itself just
    /// hasn't been narrowed. Requiring `.nonNull` here made those reads fall
    /// through to the generic call fallback and crash on the unboxed raw
    /// value instead of being rewritten to a plain copy.
    private func isValueClassExpr(
        _ expr: KIRExprID,
        arena: KIRArena,
        types: TypeSystem,
        symbols: SymbolTable,
        valueClassSymbols: Set<SymbolID>,
        allowTypeParameterUpperBound: Bool = false
    ) -> Bool {
        guard let type = arena.exprType(expr) else { return false }
        let classSymbol: SymbolID?
        switch types.kind(of: type) {
        case let .classType(classType):
            classSymbol = classType.classSymbol
        case let .typeParam(typeParameter) where allowTypeParameterUpperBound:
            // A type parameter bounded by a value class still uses that
            // value class's unboxed representation for direct property reads.
            classSymbol = symbols.typeParameterUpperBounds(for: typeParameter.symbol).compactMap { bound in
                guard case let .classType(classType) = types.kind(of: bound),
                      valueClassSymbols.contains(classType.classSymbol)
                else { return nil }
                return classType.classSymbol
            }.first
        default:
            classSymbol = nil
        }
        if let classSymbol, valueClassSymbols.contains(classSymbol) {
            return true
        }
        return false
    }

    private func rewriteBody(
        _ body: [KIRInstruction],
        arena: KIRArena,
        interner: StringInterner,
        types: TypeSystem,
        symbols: SymbolTable,
        valueClassCtors: Set<SymbolID>,
        valueClassSymbols: Set<SymbolID>,
        kk_object_new: InternedString,
        kk_array_get_inbounds: InternedString
    ) -> [KIRInstruction] {
        // The KIR pattern for `val m = Meter(42)` is:
        //   constValue slotCount = 1
        //   constValue classID = ...
        //   call kk_object_new(slotCount, classID) -> allocObj     [symbol: nil]
        //   ... (possibly kk_type_register_super/iface calls) ...
        //   call <init>(allocObj, 42) -> result                     [symbol: ctor]

        var allocExprs: Set<KIRExprID> = []
        var allocConstExprs: Set<KIRExprID> = []
        var classIDExprs: Set<KIRExprID> = []

        for instruction in body {
            if case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
               callee == kk_object_new,
               let result,
               isValueClassExpr(
                   result, arena: arena, types: types, symbols: symbols,
                   valueClassSymbols: valueClassSymbols
               )
            {
                allocExprs.insert(result)
                // arguments[0] = slotCount, arguments[1] = classID
                if arguments.count >= 1 {
                    allocConstExprs.insert(arguments[0])
                }
                if arguments.count >= 2 {
                    allocConstExprs.insert(arguments[1])
                    classIDExprs.insert(arguments[1])
                }
            }
        }

        var typeRegisterConstExprs: Set<KIRExprID> = []
        for instruction in body {
            if case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
               let result
            {
                let calleeName = interner.resolve(callee)
                if calleeName.hasPrefix("kk_type_register_") {
                    // arguments[0] = childExpr (classID), arguments[1] = parentExpr
                    if arguments.count >= 1 {
                        for classIDExpr in classIDExprs {
                            if let classIDKind = arena.expr(classIDExpr),
                               let childKind = arena.expr(arguments[0]),
                               classIDKind == childKind
                            {
                                typeRegisterConstExprs.insert(result)
                                if arguments.count >= 2 {
                                    typeRegisterConstExprs.insert(arguments[1])
                                }
                                typeRegisterConstExprs.insert(arguments[0])
                            }
                        }
                    }
                }
            }
        }

        var result: [KIRInstruction] = []
        result.reserveCapacity(body.count)

        for instruction in body {
            switch instruction {
            case let .call(_, callee, _, callResult, _, _, _, _)
                where callee == kk_object_new
                    && callResult != nil
                    && allocExprs.contains(callResult!):
                result.append(.nop)
                continue

            case let .constValue(constResult, _)
                where allocConstExprs.contains(constResult):
                result.append(.nop)
                continue

            case let .call(_, callee, arguments, _, _, _, _, _)
                where {
                    let name = interner.resolve(callee)
                    guard name.hasPrefix("kk_type_register_") else { return false }
                    guard arguments.count >= 1 else { return false }
                    for classIDExpr in classIDExprs {
                        if let classIDKind = arena.expr(classIDExpr),
                           let childKind = arena.expr(arguments[0]),
                           classIDKind == childKind
                        {
                            return true
                        }
                    }
                    return false
                }():
                result.append(.nop)
                continue

            case let .constValue(constResult, _)
                where typeRegisterConstExprs.contains(constResult):
                result.append(.nop)
                continue

            case let .call(symbol, callee, arguments, callResult, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
                if let symbol, valueClassCtors.contains(symbol),
                   let callResult
                {
                    if arguments.count == 2, allocExprs.contains(arguments[0]) {
                        // arguments[0] is the allocated receiver, arguments[1] is the value
                        result.append(.copy(from: arguments[1], to: callResult))
                        continue
                    } else if arguments.count == 1 {
                        // No explicit receiver
                        result.append(.copy(from: arguments[0], to: callResult))
                        continue
                    }
                }
                // call kk_array_get_inbounds(receiver, offset) -> result
                if callee == kk_array_get_inbounds,
                   let callResult,
                   arguments.count == 2,
                   isValueClassExpr(
                       arguments[0], arena: arena, types: types, symbols: symbols,
                       valueClassSymbols: valueClassSymbols,
                       allowTypeParameterUpperBound: true
                   )
                {
                    result.append(.copy(from: arguments[0], to: callResult))
                    continue
                }
                // Remove auxiliary calls that consume the removed value-class
                // allocation (e.g. kk_object_register_any_to_string): the
                // unboxed value has no heap object to register.
                if let objectArg = arguments.first, allocExprs.contains(objectArg) {
                    result.append(.nop)
                    continue
                }
                result.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: callResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))

            default:
                result.append(instruction)
            }
        }

        return result
    }
}
