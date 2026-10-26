
extension ExprLowerer {
    func runtimeIsCheckTargetType(
        subjectType: TypeID?,
        targetType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard let subjectType,
              case .functionType = sema.types.kind(of: targetType),
              sema.types.isSubtype(
                  sema.types.makeNonNullable(subjectType),
                  sema.types.makeNonNullable(targetType)
              )
        else {
            return targetType
        }
        // Compatible function values may be raw pointers or boxed closures;
        // their signature is known statically, so only nullability remains.
        return sema.types.nullability(of: targetType) == .nullable
            ? sema.types.nullableAnyType : sema.types.anyType
    }

    /// A generic comparison helper uses an erased Comparable cast to reach the
    /// source-backed member. The runtime representation does not attach
    /// interface metadata to primitive values, so checking this cast would
    /// reject valid calls before the bridge can compare them.
    func isRedundantComparableCast(
        from sourceType: TypeID?,
        to targetType: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard let sourceType,
              case let .typeParam(sourceParam) = sema.types.kind(of: sourceType),
              case let .classType(targetClass) = sema.types.kind(of: sema.types.makeNonNullable(targetType)),
              targetClass.classSymbol == sema.types.comparableInterfaceSymbol
        else {
            return false
        }
        let upperBounds = sema.symbols.typeParameterUpperBounds(for: sourceParam.symbol)
        if upperBounds.isEmpty {
            // An unconstrained T is the intentional erasure boundary used by
            // compareValuesUnchecked and Array/List binary search.
            return true
        }
        return upperBounds.contains { bound in
            guard case let .classType(boundClass) = sema.types.kind(of: sema.types.makeNonNullable(bound)) else {
                return false
            }
            return boundClass.classSymbol == targetClass.classSymbol
        }
    }

    func lowerIsCheckTypeTokenExpr(
        typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        func emitLiteral(_ literal: Int64) -> KIRExprID {
            let tokenExpr = arena.appendExpr(.intLiteral(literal), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(literal)))
            return tokenExpr
        }

        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return emitLiteral(RuntimeTypeCheckToken.unknownBase)
        }

        switch typeRef {
        case let .named(path, _, nullable):
            guard let last = path.last else {
                return emitLiteral(RuntimeTypeCheckToken.unknownBase)
            }
            if path.count == 1,
               let tokenSymbol = reifiedTypeTokenSymbol(for: last, sema: sema)
            {
                return lowerReifiedTypeCheckTokenExpr(
                    tokenSymbol: tokenSymbol, nullable: nullable, intType: intType,
                    interner: interner, arena: arena, instructions: &instructions
                )
            }
            if let symbol = sema.symbols.lookup(fqName: path),
               let nominal = sema.symbols.symbol(symbol),
               nominal.kind == .class || nominal.kind == .interface || nominal.kind == .object || nominal.kind == .enumClass
            {
                if let shape = sema.types.nominalFunctionInterfaceShape(of: symbol) {
                    let payload = Int64(shape.arity) | (shape.isSuspend ? 0x100 : 0)
                    return emitLiteral(
                        RuntimeTypeCheckToken.encode(
                            base: RuntimeTypeCheckToken.functionBase,
                            nullable: nullable,
                            payload: payload
                        )
                    )
                }
                let nominalTypeID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: symbol, sema: sema, interner: interner)
                return emitLiteral(
                    RuntimeTypeCheckToken.encode(
                        base: RuntimeTypeCheckToken.nominalBase,
                        nullable: nullable,
                        payload: nominalTypeID
                    )
                )
            }
            let literal = RuntimeTypeCheckToken.encodeBuiltinTypeName(
                last,
                nullable: nullable,
                builtinNames: BuiltinTypeNames(interner: interner)
            )
                ?? RuntimeTypeCheckToken.encode(base: RuntimeTypeCheckToken.unknownBase, nullable: nullable)
            return emitLiteral(literal)

        case let .functionType(_, _, _, _, _, nullable):
            return emitLiteral(
                RuntimeTypeCheckToken.encode(
                    base: RuntimeTypeCheckToken.unknownBase,
                    nullable: nullable
                )
            )

        case .intersection:
            return emitLiteral(RuntimeTypeCheckToken.unknownBase)
        case let .annotated(base, _):
            return lowerIsCheckTypeTokenExpr(
                typeRefID: base,
                ast: ast,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
        }
    }

    func lowerTypeCheckTokenExpr(
        targetType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        // When the target type is a reified type parameter, emit a symbolRef
        // to the synthetic token parameter so that inline expansion can
        // substitute the concrete type token at the call site.
        if case let .typeParam(typeParam) = sema.types.kind(of: targetType),
           let symbolInfo = sema.symbols.symbol(typeParam.symbol),
           symbolInfo.flags.contains(.reifiedTypeParameter),
           let tokenSymbol = reifiedTypeTokenSymbol(for: symbolInfo.name, sema: sema)
        {
            return lowerReifiedTypeCheckTokenExpr(
                tokenSymbol: tokenSymbol, nullable: typeParam.nullability == .nullable, intType: intType,
                interner: interner, arena: arena, instructions: &instructions
            )
        }
        let encoded = RuntimeTypeCheckToken.encode(type: targetType, sema: sema, interner: interner)
        let tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        return tokenExpr
    }

    /// The hidden token carries the call-site T, while an explicit T? adds
    /// nullability at the use site even when that call-site type is non-null.
    private func lowerReifiedTypeCheckTokenExpr(
        tokenSymbol: SymbolID,
        nullable: Bool,
        intType: TypeID,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let token: KIRExprID
        if let local = driver.ctx.localValue(for: tokenSymbol) {
            token = local
        } else {
            token = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            instructions.append(.constValue(result: token, value: .symbolRef(tokenSymbol)))
        }
        guard nullable else { return token }
        let flag = arena.appendExpr(.intLiteral(RuntimeTypeCheckToken.nullableFlag), type: intType)
        instructions.append(.constValue(result: flag, value: .intLiteral(RuntimeTypeCheckToken.nullableFlag)))
        let result = arena.appendTemporary(type: intType)
        instructions.append(.call(callee: interner.intern("kk_bitwise_or"), arguments: [token, flag], result: result, canThrow: false))
        return result
    }

    func reifiedTypeTokenSymbol(
        for typeName: InternedString,
        sema: SemaModule
    ) -> SymbolID? {
        if let currentFunctionSymbol = driver.ctx.activeFunctionSymbol(),
           let signature = sema.symbols.functionSignature(for: currentFunctionSymbol)
        {
            for typeParameterSymbol in signature.typeParameterSymbols {
                guard let symbol = sema.symbols.symbol(typeParameterSymbol),
                      symbol.kind == .typeParameter,
                      symbol.name == typeName,
                      symbol.flags.contains(.reifiedTypeParameter)
                else {
                    continue
                }
                return SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameterSymbol)
            }
        }
        // A lambda body can refer to a reified type parameter captured from an
        // enclosing inline function. The lambda has no function signature for
        // that outer parameter, so recover the token from its capture context.
        return sema.symbols.allSymbols()
            .filter { symbol in
                symbol.kind == .typeParameter
                    && symbol.name == typeName
                    && symbol.flags.contains(.reifiedTypeParameter)
            }
            .compactMap { symbol -> SymbolID? in
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: symbol.id)
                return driver.ctx.localValue(for: tokenSymbol) != nil ? tokenSymbol : nil
            }
            .first
    }
}
