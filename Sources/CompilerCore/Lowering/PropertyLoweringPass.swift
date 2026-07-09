
final class PropertyLoweringPass: LoweringPass {
    static let name = "PropertyLowering"

    /// Lazily built reverse map from backing field symbol to its owning property symbol.
    private var backingFieldToPropertyMap: [SymbolID: SymbolID]?

    func run(module: KIRModule, ctx: KIRContext) throws {
        let getterName = ctx.interner.intern("get")
        let setterName = ctx.interner.intern("set")
        let getValueName = ctx.interner.intern("getValue")
        let setValueName = ctx.interner.intern("setValue")
        let interner = ctx.interner
        let sema = ctx.sema

        // Collect all function symbols emitted into the KIR module so we can
        // verify that a getter accessor actually exists before rewriting.
        let emittedFunctionSymbols: Set<SymbolID> = {
            var result = Set<SymbolID>()
            for decl in module.arena.declarations {
                if case let .function(fn) = decl {
                    result.insert(fn.symbol)
                }
            }
            return result
        }()

        // Build a set of getter-only computed property symbols (property kind,
        // no backing field, AND a getter accessor function exists in the module)
        // so that constValue(.symbolRef(propSym)) can be rewritten to a getter
        // call in the main transform loop.
        let computedPropertySymbols: Set<SymbolID> = {
            guard let sema = ctx.sema else { return [] }
            var result = Set<SymbolID>()
            for sym in sema.symbols.allSymbols() {
                guard sym.kind == .property,
                      sema.symbols.backingFieldSymbol(for: sym.id) == nil
                else {
                    continue
                }
                // Only include if a getter accessor function was actually
                // emitted — this avoids over-matching regular stored properties
                // that have no custom getter.
                let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym.id)
                guard emittedFunctionSymbols.contains(getterSymbol) else {
                    continue
                }
                result.insert(sym.id)
            }
            return result
        }()

        let externalTopLevelCallee: (SymbolID) -> InternedString? = { symbol in
            guard let sema = ctx.sema else { return nil }
            guard sema.symbols.propertyType(for: symbol) != nil,
                  let linkName = sema.symbols.externalLinkName(for: symbol),
                  !linkName.isEmpty
            else {
                return nil
            }
            let parentKind = sema.symbols.parentSymbol(for: symbol).flatMap {
                sema.symbols.symbol($0)?.kind
            }
            guard parentKind == nil || parentKind == .package || parentKind == .object else {
                return nil
            }
            return interner.intern(linkName)
        }

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, _) = instruction else {
                    if case let .loadGlobal(lgResult, sym) = instruction,
                       let sema,
                       let constant = constValue(for: sym, sema: sema)
                    {
                        loweredBody.append(.constValue(result: lgResult, value: constant))
                        continue
                    }

                    // Rewrite loadGlobal for getter-only computed properties
                    // into a getter call.  ExprLowerer emits loadGlobal for
                    // top-level property references; without this rewrite the
                    // backend would look for a non-existent global slot.
                    if case let .loadGlobal(lgResult, sym) = instruction,
                       computedPropertySymbols.contains(sym)
                    {
                        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym)
                        if function.symbol != getterSymbol {
                            loweredBody.append(
                                .call(
                                    symbol: getterSymbol,
                                    callee: getterName,
                                    arguments: [],
                                    result: lgResult,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                    }

                    if case let .loadGlobal(lgResult, sym) = instruction,
                       let externalCallee = externalTopLevelCallee(sym)
                    {
                        loweredBody.append(
                            .call(
                                symbol: nil,
                                callee: externalCallee,
                                arguments: [],
                                result: lgResult,
                                canThrow: false,
                                thrownResult: nil
                            )
                        )
                        continue
                    }
                    // Rewrite constValue(.symbolRef(propSym)) for getter-only
                    // computed properties into a getter call so that each
                    // access invokes the getter body rather than loading a
                    // non-existent global.
                    if case let .constValue(cvResult, value) = instruction,
                       case let .symbolRef(sym) = value,
                       let sema,
                       let constant = constValue(for: sym, sema: sema)
                    {
                        loweredBody.append(.constValue(result: cvResult, value: constant))
                        continue
                    }

                    if case let .constValue(cvResult, value) = instruction,
                       case let .symbolRef(sym) = value,
                       computedPropertySymbols.contains(sym)
                    {
                        // Skip rewriting if we are inside the getter accessor
                        // for this property to avoid infinite recursion.
                        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym)
                        if function.symbol != getterSymbol {
                            loweredBody.append(
                                .call(
                                    symbol: getterSymbol,
                                    callee: getterName,
                                    arguments: [],
                                    result: cvResult,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                    }

                    if case let .constValue(cvResult, value) = instruction,
                       case let .symbolRef(sym) = value,
                       let externalCallee = externalTopLevelCallee(sym)
                    {
                        loweredBody.append(
                            .call(
                                symbol: nil,
                                callee: externalCallee,
                                arguments: [],
                                result: cvResult,
                                canThrow: false,
                                thrownResult: nil
                            )
                        )
                        continue
                    }
                    // Rewrite backing field copy instructions to direct
                    // setter accessor calls when the target is a backing
                    // field symbol.
                    if case let .copy(from, to) = instruction,
                       let sema = ctx.sema
                    {
                        let toExpr = module.arena.expr(to)
                        if case let .symbolRef(targetSym) = toExpr,
                           sema.symbols.symbol(targetSym)?.kind == .backingField
                        {
                            // Find the property symbol that owns this backing
                            // field and emit a direct setter accessor call.
                            let propSym = self.propertySymbolForBackingField(
                                targetSym, sema: sema
                            )
                            guard let baseSymbol = propSym else {
                                // Cannot find owning property — keep original copy.
                                loweredBody.append(instruction)
                                continue
                            }
                            let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: baseSymbol)
                            // If the current function IS one of this property's
                            // own accessors, keep the original copy: Kotlin's
                            // `field` keyword always writes directly to backing
                            // storage, bypassing the setter, even when the write
                            // occurs inside the getter (e.g. a lazy-caching
                            // getter that does `field = compute()`). Rewriting
                            // that into a setter call would both recurse
                            // (setter's own body) and, for the getter, silently
                            // run the setter's transformation logic a second
                            // time on every read.
                            let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: baseSymbol)
                            if function.symbol == setterSymbol || function.symbol == getterSymbol {
                                loweredBody.append(instruction)
                                continue
                            }
                            // No setter accessor function was actually emitted
                            // for this property — e.g. a `val` with an explicit
                            // backing field (Kotlin 2.0), or a `var` whose only
                            // customized accessor is the getter (no `set(value)
                            // { ... }` block, so PropertyDecl lowering never
                            // synthesizes a setter accessor; see
                            // KIRLoweringDriver+ModuleLowering+PropertyDecl.swift).
                            // There is no accessor to call, so keep the direct
                            // backing field copy. This check must not be gated
                            // on mutability: a mutable property can lack a
                            // setter accessor just as easily as an immutable one.
                            if !emittedFunctionSymbols.contains(setterSymbol) {
                                loweredBody.append(instruction)
                                continue
                            }
                            // Member property setter accessors are synthesized
                            // with signature (receiver, value) -> Unit (see
                            // lowerAccessorBody), so calling one from outside its
                            // own body — e.g. this rewrite of the constructor's
                            // field-initializer copy, or of a getter body that
                            // caches into `field` — must forward that enclosing
                            // function's own receiver parameter alongside the
                            // value. Top-level properties have no receiver.
                            let callArguments = self.setterCallArguments(
                                from: from, propertySymbol: baseSymbol, function: function,
                                sema: sema, arena: module.arena, loweredBody: &loweredBody
                            )
                            loweredBody.append(
                                .call(
                                    symbol: setterSymbol,
                                    callee: setterName,
                                    arguments: callArguments,
                                    result: nil,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                    }
                    loweredBody.append(instruction)
                    continue
                }

                // Lower delegated property getValue/setValue calls to
                // direct accessor calls with the delegate-aware signature.
                // Only rewrite calls whose symbol is a delegate storage field
                // (name starts with $delegate_) to avoid rewriting user-defined
                // getValue/setValue methods.
                if callee == getValueName || callee == setValueName,
                   let sema = ctx.sema,
                   let sym = symbol,
                   let symInfo = sema.symbols.symbol(sym),
                   symInfo.kind == .field,
                   interner.resolve(symInfo.name).hasPrefix("$delegate_")
                {
                    let isSetter = callee == setValueName
                    // Derive the property symbol from the delegate field name
                    // ($delegate_<propName> → <propName>). MemberLowerer creates
                    // accessor functions keyed off the property symbol, not the
                    // delegate storage field.
                    guard let propSymbol = self.propertySymbolForDelegateField(
                        sym, symInfo: symInfo, sema: sema, interner: interner
                    ) else {
                        // Cannot resolve property symbol — keep original call.
                        loweredBody.append(instruction)
                        continue
                    }
                    let accessorSymbol = isSetter
                        ? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propSymbol)
                        : SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propSymbol)
                    // If the current function IS the accessor being
                    // targeted, keep the original getValue/setValue call
                    // to avoid infinite recursion (accessor calling itself).
                    if function.symbol == accessorSymbol {
                        loweredBody.append(instruction)
                        continue
                    }
                    loweredBody.append(
                        .call(
                            symbol: accessorSymbol,
                            callee: isSetter ? setterName : getterName,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        )
                    )
                    continue
                }

                guard callee == getterName || callee == setterName else {
                    loweredBody.append(instruction)
                    continue
                }

                // Rewrite get/set calls to use the synthetic accessor
                // symbol for direct dispatch, eliminating the
                // kk_property_access indirection and accessor-kind
                // boolean argument.
                let isSetter = callee == setterName
                if let sym = symbol,
                   let sema,
                   let symInfo = sema.symbols.symbol(sym),
                   symInfo.kind == .property || symInfo.kind == .backingField
                {
                    let accessorSymbol = isSetter
                        ? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: sym)
                        : SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym)
                    loweredBody.append(
                        .call(
                            symbol: accessorSymbol,
                            callee: callee,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        )
                    )
                } else {
                    // No property symbol — keep original instruction.
                    loweredBody.append(instruction)
                }
            }

            updated.replaceBody(loweredBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func constValue(for symbol: SymbolID, sema: SemaModule) -> KIRExprKind? {
        if let symInfo = sema.symbols.symbol(symbol),
           symInfo.flags.contains(.constValue),
           let constant = sema.symbols.constValueExprKind(for: symbol)
        {
            return constant
        }
        guard let propertySymbol = propertySymbolForBackingField(symbol, sema: sema),
              let propertyInfo = sema.symbols.symbol(propertySymbol),
              propertyInfo.flags.contains(.constValue)
        else {
            return nil
        }
        return sema.symbols.constValueExprKind(for: propertySymbol)
    }

    /// Builds the argument list for a rewritten setter-accessor call.
    ///
    /// Member property setter accessors are synthesized with signature
    /// `(receiver, value) -> Unit` whenever the property has an owner symbol
    /// — see `lowerAccessorBody`'s `else if let ownerSymbol, let ownerSym =
    /// sema.symbols.symbol(ownerSymbol)` branch, which adds a receiver for
    /// *any* owner kind (class, interface, object, enum class, annotation
    /// class, ...) without filtering by kind. This check mirrors that exact
    /// condition rather than enumerating owner kinds, so it can't drift out
    /// of sync with it the way a hardcoded kind list did (a property owned
    /// by an enum class was previously — incorrectly — treated as receiver-less).
    /// Top-level properties have no owner symbol at all, so their setter
    /// accessors take only the value.
    private func setterCallArguments(
        from: KIRExprID,
        propertySymbol: SymbolID,
        function: KIRFunction,
        sema: SemaModule,
        arena: KIRArena,
        loweredBody: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              sema.symbols.symbol(ownerSymbol) != nil,
              let receiverParam = function.params.first
        else {
            return [from]
        }
        let receiverExpr = arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverParam.type)
        loweredBody.append(.constValue(result: receiverExpr, value: .symbolRef(receiverParam.symbol)))
        return [receiverExpr, from]
    }

    /// Given a backing field symbol, find the property symbol it belongs to.
    /// Uses a lazily built reverse map for O(1) lookups after the first call.
    private func propertySymbolForBackingField(
        _ backingFieldSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        if backingFieldToPropertyMap == nil {
            var map: [SymbolID: SymbolID] = [:]
            for sym in sema.symbols.allSymbols() {
                if let backing = sema.symbols.backingFieldSymbol(for: sym.id) {
                    map[backing] = sym.id
                }
            }
            backingFieldToPropertyMap = map
        }
        return backingFieldToPropertyMap?[backingFieldSymbol]
    }

    /// Given a delegate storage field symbol ($delegate_<name>), find the
    /// property symbol it belongs to by stripping the prefix and looking
    /// up a sibling symbol with the property name.
    private func propertySymbolForDelegateField(
        _: SymbolID,
        symInfo: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let delegateName = interner.resolve(symInfo.name)
        guard delegateName.hasPrefix("$delegate_") else { return nil }
        let propertyName = String(delegateName.dropFirst("$delegate_".count))
        let internedPropName = interner.intern(propertyName)
        // Look up a sibling with the matching property name in the
        // same parent scope (same fqName prefix).
        let parentFQ = symInfo.fqName.dropLast()
        let propFQ = Array(parentFQ) + [internedPropName]
        return sema.symbols.lookup(fqName: propFQ)
    }
}
