/// Member-call fallback resolution for `Array<T>` and primitive-array
/// receivers (STDLIB-087/088/089).
///
/// Split out from `CallTypeChecker+MemberCallFallbacks.swift`.
extension CallTypeChecker {
    func tryArrayMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard !isClassNameReceiver,
              isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        guard isSupportedArrayMember(memberName),
              isValidArrayMemberArity(memberName, argCount: args.count)
        else {
            return nil
        }

        // Extract the actual element type from the Array<T> receiver (TYPE-103).
        let receiverElementType = arrayFallbackElementType(receiverID: receiverID, sema: sema, interner: interner)
        if memberName == "copyOf", args.indices.contains(0) {
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.intType
            )
        }
        if (memberName == "fold" || memberName == "foldIndexed"), args.indices.contains(0) {
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.anyType
            )
        }
        if let expectation = arrayMemberLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
            receiverElementType: receiverElementType,
            sema: sema
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }

        // Mark result as collection if it returns a List
        if isArrayMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }

        let resultType = arrayMemberResultType(
            memberName: memberName,
            receiverID: receiverID,
            elementType: receiverElementType,
            sema: sema,
            interner: interner
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func isSupportedArrayMember(_ memberName: String) -> Bool {
        let arrayMembers: Set = [
            "toList", "toMutableList",
            "map", "filter", "forEach", "any", "all", "none",
            "find", "findLast",
            "fold", "foldIndexed",
            "reduce", "reduceOrNull",
            "count",
            "copyOf", "copyOfRange", "fill",
            "size", "get", "contains", "isEmpty",
            "concatToString",
        ]
        return arrayMembers.contains(memberName)
    }

    private func isValidArrayMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "toList", "toMutableList", "size", "isEmpty", "concatToString":
            argCount == 0
        case "copyOf":
            (0...2).contains(argCount)
        case "map", "filter", "forEach", "any", "all", "none", "fill", "get", "contains",
             "find", "findLast", "reduce", "reduceOrNull":
            argCount == 1
        case "fold", "foldIndexed":
            argCount == 2
        case "count":
            (0...1).contains(argCount)
        case "copyOfRange":
            argCount == 2
        default:
            true
        }
    }

    private func isArrayMemberReturningCollection(_ memberName: String) -> Bool {
        ["toList", "toMutableList", "map", "filter", "copyOf", "copyOfRange"].contains(memberName)
    }

    private func arrayMemberResultType(
        memberName: String,
        receiverID: ExprID,
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        switch memberName {
        case "size":
            return sema.types.intType
        case "isEmpty", "contains", "any", "all", "none":
            return sema.types.booleanType
        case "forEach", "fill":
            return sema.types.unitType
        case "count":
            return sema.types.intType
        case "find", "findLast":
            return sema.types.makeNullable(elementType)
        case "reduce":
            return elementType
        case "reduceOrNull":
            return sema.types.makeNullable(elementType)
        case "fold", "foldIndexed":
            return sema.types.anyType
        case "concatToString":
            return sema.types.stringType
        case "get":
            return elementType
        case "copyOf", "copyOfRange":
            let receiverType = sema.bindings.exprTypes[receiverID]
                ?? sema.bindings.identifierSymbol(for: receiverID).flatMap { sema.symbols.propertyType(for: $0) }
                ?? sema.types.anyType
            return sema.types.makeNonNullable(receiverType)
        case "toList":
            if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        case "toMutableList":
            if let mutableListSymbol = sema.symbols.lookupByShortName(interner.intern("MutableList")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: mutableListSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        default:
            return sema.types.anyType
        }
    }

    private func arrayMemberLambdaExpectation(
        memberName: String,
        argCount: Int,
        receiverElementType: TypeID,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let boolPredicateMembers: Set = ["filter", "any", "all", "none", "find", "findLast", "count"]
        let oneParamMembers: Set = ["map", "filter", "forEach", "any", "all", "none", "find", "findLast", "count"]
        if memberName == "copyOf", argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }
        if (memberName == "reduce" || memberName == "reduceOrNull"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType, receiverElementType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }
        if memberName == "fold", argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, receiverElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }
        if memberName == "foldIndexed", argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, receiverElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }
        guard oneParamMembers.contains(memberName), argCount == 1 else {
            return nil
        }
        let lambdaReturnType = boolPredicateMembers.contains(memberName)
            ? sema.types.booleanType
            : memberName == "forEach" ? sema.types.unitType : sema.types.anyType
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: [receiverElementType],
            returnType: lambdaReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: 0, expectedType: expectedType)
    }

    /// Extract the element type from an `Array<T>` receiver.
    /// For generic `Array<T>`, returns `T`; for primitive arrays (IntArray, etc.)
    /// returns the corresponding primitive type.  Falls back to `Any` when the
    /// element type cannot be determined.
    private func arrayFallbackElementType(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let receiverType = sema.bindings.exprTypes[receiverID]
            ?? sema.bindings.identifierSymbol(for: receiverID).flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard let (classType, symbol) = resolveClassTypeSymbol(nonNull, sema: sema) else {
            return sema.types.anyType
        }

        let knownNames = KnownCompilerNames(interner: interner)

        // Generic Array<T>: extract type argument.
        if symbol.name == knownNames.array, let firstArg = classType.args.first {
            return switch firstArg {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
        }

        // Primitive arrays have a fixed element type.
        // Note: Byte/Short map to intType (same as builtinType resolution).
        let primitiveMapping: [(InternedString, TypeID)] = [
            (knownNames.intArray, sema.types.intType),
            (knownNames.longArray, sema.types.longType),
            (knownNames.shortArray, sema.types.intType),
            (knownNames.byteArray, sema.types.intType),
            (knownNames.ubyteArray, sema.types.ubyteType),
            (knownNames.ushortArray, sema.types.ushortType),
            (knownNames.uintArray, sema.types.uintType),
            (knownNames.ulongArray, sema.types.ulongType),
            (knownNames.doubleArray, sema.types.doubleType),
            (knownNames.floatArray, sema.types.floatType),
            (knownNames.booleanArray, sema.types.booleanType),
            (knownNames.charArray, sema.types.charType),
        ]
        for (name, elementType) in primitiveMapping {
            // swiftlint:disable:next for_where
            if symbol.name == name {
                return elementType
            }
        }

        return sema.types.anyType
    }

    // MARK: - KFunction member call fallback (STDLIB-REFLECT-063)

    /// Checks whether the receiver type is `kotlin.reflect.KFunction<*>`.
    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard let classType = resolveClassType(receiverType, sema: sema),
              let kFuncSym = sema.types.kFunctionInterfaceSymbol,
              classType.classSymbol == kFuncSym
        else {
            return false
        }
        return true
    }

    /// Returns the return-type argument of a `KFunction<R>` type, or `anyType` when not available.
    private func kFunctionReturnType(
        _ receiverType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard let classType = resolveClassType(receiverType, sema: sema),
              classType.args.count == 1
        else {
            return sema.types.anyType
        }
        switch classType.args[0] {
        case let .out(t), let .invariant(t): return t
        default: return sema.types.anyType
        }
    }

    /// Handles member calls on `KFunction<R>` receivers:
    /// - `call(vararg args)` → returns R (the KFunction type argument)
    func tryKFunctionMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema) else { return nil }
        let memberName = interner.resolve(calleeName)

        switch memberName {
        case "call":
            // Infer argument types (accept any).
            for arg in args {
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: nil)
            }
            let returnType = kFunctionReturnType(receiverType, sema: sema)
            let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "name":
            let resultType = sema.types.stringType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "isSuspend":
            let resultType = sema.types.booleanType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "parameters":
            // parameters returns List<Any?>, but at this stage use anyType as a safe fallback.
            let resultType = sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        default:
            return nil
        }
    }
}
