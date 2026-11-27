
extension ExprLowerer {
    func runtimeIsCheckTargetType(
        subjectType: TypeID?,
        targetType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard let subjectType else {
            return targetType
        }
        let subjectNonNull = sema.types.makeNonNullable(subjectType)
        let targetNonNull = sema.types.makeNonNullable(targetType)
        let isCompatibleFunctionValue: Bool = {
            guard case .functionType = sema.types.kind(of: targetType) else { return false }
            return sema.types.isSubtype(subjectNonNull, targetNonNull)
        }()
        // JVM `x is T` folds to a null check when the subject's erased
        // classifier already is the target's — `x: T?` `is T` emits `x !=
        // null`, tolerating unchecked-cast heap pollution exactly the way the
        // claim boundary does (KUU-3893). A nullable target keeps the real
        // check: `x is T?` is `x == null || x instanceof T`, not a null check.
        let foldsToNullCheck = isCompatibleFunctionValue
            || (isSameErasedClassifier(subject: subjectNonNull, target: targetNonNull, sema: sema)
                && sema.types.nullability(of: targetType) != .nullable)
        guard foldsToNullCheck else {
            return targetType
        }
        return sema.types.nullability(of: targetType) == .nullable
            ? sema.types.nullableAnyType : sema.types.anyType
    }

    private func isSameErasedClassifier(subject: TypeID, target: TypeID, sema: SemaModule) -> Bool {
        switch (RuntimeTypeCheckToken.classify(type: subject, sema: sema).category,
                RuntimeTypeCheckToken.classify(type: target, sema: sema).category) {
        case let (.nominal(lhs), .nominal(rhs)):
            return lhs == rhs
        case let (.function(arityLHS, suspendLHS), .function(arityRHS, suspendRHS)):
            return arityLHS == arityRHS && suspendLHS == suspendRHS
        case (.any, .any), (.string, .string), (.boolean, .boolean),
             (.int, .int), (.uint, .uint), (.ulong, .ulong), (.ubyte, .ubyte),
             (.ushort, .ushort), (.byte, .byte), (.short, .short), (.long, .long),
             (.double, .double), (.float, .float), (.char, .char), (.unit, .unit):
            return true
        default:
            return false
        }
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
        case .named, .qualifiedNamed:
            guard let namedType = typeRef.namedType else {
                return emitLiteral(RuntimeTypeCheckToken.unknownBase)
            }
            let path = namedType.path
            let nullable = namedType.nullable
            guard let last = path.last else {
                return emitLiteral(RuntimeTypeCheckToken.unknownBase)
            }
            if path.count == 1,
               let tokenSymbol = reifiedTypeTokenSymbol(for: last, sema: sema)
            {
                return lowerReifiedTypeCheckTokenExpr(
                    tokenSymbol: tokenSymbol, nullable: nullable, sema: sema,
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
        if case let .typeParam(typeParam) = sema.types.kind(of: targetType),
           let symbolInfo = sema.symbols.symbol(typeParam.symbol),
           symbolInfo.flags.contains(.reifiedTypeParameter),
           let tokenSymbol = reifiedTypeTokenSymbol(for: symbolInfo.name, sema: sema)
        {
            return lowerReifiedTypeCheckTokenExpr(
                tokenSymbol: tokenSymbol, nullable: typeParam.nullability == .nullable, sema: sema,
                interner: interner, arena: arena, instructions: &instructions
            )
        }
        let encoded = RuntimeTypeCheckToken.encode(type: targetType, sema: sema, interner: interner)
        let tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        return tokenExpr
    }

    private func lowerReifiedTypeCheckTokenExpr(
        tokenSymbol: SymbolID,
        nullable: Bool,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let token: KIRExprID
        if let local = driver.ctx.localValue(for: tokenSymbol) {
            token = local
        } else {
            token = arena.appendExpr(.symbolRef(tokenSymbol), type: sema.types.intType)
            instructions.append(.constValue(result: token, value: .symbolRef(tokenSymbol)))
        }
        guard nullable else { return token }
        return RuntimeTypeCheckToken.emitNullableToken(
            token, sema: sema, interner: interner, arena: arena, instructions: &instructions
        )
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
