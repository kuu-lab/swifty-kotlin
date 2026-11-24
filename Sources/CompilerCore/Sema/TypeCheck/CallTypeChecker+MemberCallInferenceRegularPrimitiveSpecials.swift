// swiftlint:disable function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func primitiveCompareToCandidateMatches(
        _ candidate: SymbolID,
        calleeName: InternedString,
        receiverType: TypeID,
        argTypes: [TypeID],
        sema: SemaModule
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: driver.interner)
        let receiver = sema.types.makeNonNullable(receiverType)
        let isUnsignedReceiver = receiver == sema.types.uintType || receiver == sema.types.ulongType
        guard calleeName == knownNames.compareTo,
              receiver == sema.types.byteType || receiver == sema.types.shortType || isUnsignedReceiver,
              sema.symbols.parentSymbol(for: candidate) == sema.types.comparableInterfaceSymbol
        else {
            return true
        }
        guard argTypes.count == 1 else { return false }
        if isUnsignedReceiver {
            switch sema.types.kind(of: argTypes[0]) {
            case .primitive(.ubyte, .nonNull), .primitive(.ushort, .nonNull),
                 .primitive(.uint, .nonNull), .primitive(.ulong, .nonNull),
                 .nothing(.nonNull):
                return true
            default:
                return false
            }
        }
        switch sema.types.kind(of: argTypes[0]) {
        case .primitive(.byte, .nonNull), .primitive(.short, .nonNull),
             .primitive(.int, .nonNull), .primitive(.long, .nonNull),
             .primitive(.float, .nonNull), .primitive(.double, .nonNull),
             .nothing(.nonNull):
            return true
        default:
            return false
        }
    }

    func tryInferRegularMemberCallPrimitiveSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        argTypes: [TypeID],
        locals: inout LocalBindings,
        enforceInfixEligibility: Bool = true
    ) -> TypeID? {
        if enforceInfixEligibility, request.ctx.ast.arena.isInfixCall(request.id),
           !isInfixPrimitiveIntrinsic(request.calleeName, receiverType: lookupReceiverType, ctx: request.ctx)
        {
            return nil
        }
        if request.calleeName == request.knownNames.inv,
           request.args.isEmpty
        {
            let intType = request.sema.types.make(.primitive(.int, .nonNull))
            let longType = request.sema.types.make(.primitive(.long, .nonNull))
            let uintType = request.sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = request.sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = request.sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = request.sema.types.make(.primitive(.ushort, .nonNull))
            if lookupReceiverType == intType || lookupReceiverType == longType || lookupReceiverType == uintType || lookupReceiverType == ulongType || lookupReceiverType == ubyteType || lookupReceiverType == ushortType {
                let resultType = lookupReceiverType
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        if request.args.count == 1 {
            let intType = request.sema.types.make(.primitive(.int, .nonNull))
            let longType = request.sema.types.make(.primitive(.long, .nonNull))
            let uintType = request.sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = request.sema.types.make(.primitive(.ulong, .nonNull))
            let floatType = request.sema.types.make(.primitive(.float, .nonNull))
            let doubleType = request.sema.types.make(.primitive(.double, .nonNull))
            let ubyteType = request.sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = request.sema.types.make(.primitive(.ushort, .nonNull))
            let byteType = request.sema.types.byteType
            let shortType = request.sema.types.shortType
            let charType = request.sema.types.charType
            let receiverForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if request.calleeName == request.knownNames.compareTo,
               case .nothing(.nonNull) = request.sema.types.kind(of: argTypes[0]),
               receiverForCheck == byteType || receiverForCheck == shortType
                   || receiverForCheck == intType || receiverForCheck == longType
                   || receiverForCheck == floatType || receiverForCheck == doubleType
            {
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0003",
                    "Ambiguous overload resolution.",
                    range: request.range
                )
                request.sema.bindings.bindExprType(request.id, type: request.sema.types.errorType)
                return request.sema.types.errorType
            }
            let isRangeReceiver = ["plus", "minus"].contains(request.interner.resolve(request.calleeName))
                && (MemberRuntimeDispatch.rangeReceiverKind(
                    receiverExpr: request.receiverID,
                    receiverType: lookupReceiverType,
                    sema: request.sema,
                    interner: request.interner
                ) != nil
                    || ControlFlowTypeChecker.isRangeExpression(request.receiverID, ast: request.ctx.ast))
            let rawRhsType = argTypes[0]
            let isPrimitiveReceiver = !isRangeReceiver
                && (receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            let isShiftReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType
            let isBitwiseReceiver = isShiftReceiver || receiverForCheck == ubyteType || receiverForCheck == ushortType
            let isSmallUnsigned = { (t: TypeID) -> Bool in t == ubyteType || t == ushortType }
            let isUnsignedInteger = { (t: TypeID) -> Bool in
                t == uintType || t == ulongType || isSmallUnsigned(t)
            }
            let isSignedInteger = { (t: TypeID) -> Bool in
                t == intType || t == longType || t == byteType || t == shortType
            }
            let isFloating = { (t: TypeID) -> Bool in
                t == floatType || t == doubleType
            }
            let isNonNullNothingOperand = {
                if case .nothing(.nonNull) = request.sema.types.kind(of: rawRhsType) {
                    return true
                }
                return false
            }()
            if request.calleeName == request.knownNames.compareTo,
               isNonNullNothingOperand,
               receiverForCheck == byteType || receiverForCheck == shortType
                   || receiverForCheck == intType || receiverForCheck == longType
                   || receiverForCheck == floatType || receiverForCheck == doubleType
            {
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0003",
                    "Ambiguous overload resolution.",
                    range: request.range
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            // KUU-3954: Kotlin's primitive arithmetic members take only
            // non-null numeric operands — `x.plus(xn)` where xn: Int? is
            // rejected by kotlinc — but the fast path used to strip operand
            // nullability via makeNonNullable, and the Double/Float/Long/
            // unsigned receiver branches skipped operand checks entirely
            // (letting `d.plus("a")` reach codegen and die at link time).
            // An operand must be a non-null primitive numeric or an error
            // type; a non-null Nothing operand is additionally accepted for
            // unsigned receivers, matching kotlinc (`u.plus(TODO())`
            // resolves, while `x.plus(TODO())` is ambiguous there and still
            // rejected here). Anything else — including nullable operands —
            // falls through to normal resolution, which reports the
            // mismatch.
            let rejectsArithmeticOperand = { (operand: TypeID) -> Bool in
                if isSignedInteger(operand) || isFloating(operand) || isUnsignedInteger(operand) {
                    return false
                }
                switch request.sema.types.kind(of: operand) {
                case .error:
                    return false
                case .nothing(.nonNull):
                    return !isUnsignedInteger(receiverForCheck)
                default:
                    return true
                }
            }
            let unsignedOperandResultType = { (operand: TypeID) -> TypeID? in
                if isUnsignedInteger(operand) {
                    receiverForCheck == ulongType || operand == ulongType ? ulongType : uintType
                } else if case .nothing(.nonNull) = request.sema.types.kind(of: operand) {
                    receiverForCheck == ulongType ? ulongType : uintType
                } else {
                    nil
                }
            }
            let arithmeticOp: BinaryOp? = switch request.interner.resolve(request.calleeName) {
            case "plus": .add
            case "minus": .subtract
            case "times": .multiply
            case "div": .divide
            case "rem": .modulo
            default: nil
            }
            if let arithmeticOp,
               driver.exprChecker.hasInvalidBuiltinCharArithmetic(
                   op: arithmeticOp, lhs: receiverForCheck, rhs: rawRhsType, sema: request.sema
               )
            {
                return nil
            }
            let isNumericReceiver = isPrimitiveReceiver
                || receiverForCheck == floatType
                || receiverForCheck == doubleType
                || receiverForCheck == charType
            switch request.interner.resolve(request.calleeName) {
            case "plus":
                let resultType: TypeID? = if !isNumericReceiver {
                    nil
                } else if receiverForCheck == charType && rawRhsType == intType {
                    charType
                } else if receiverForCheck == charType && isNonNullNothingOperand {
                    charType
                } else if receiverForCheck == charType && request.sema.types.isString(rawRhsType) {
                    driver.exprChecker.collectScopedOperatorExtensionCandidates(
                        names: [request.calleeName], receiverType: receiverForCheck, argumentType: rawRhsType, ctx: request.ctx
                    ).isEmpty ? request.sema.types.stringType : nil
                } else if rejectsArithmeticOperand(rawRhsType) {
                    nil
                } else if isUnsignedInteger(receiverForCheck) {
                    unsignedOperandResultType(rawRhsType)
                } else if isUnsignedInteger(rawRhsType) {
                    nil
                } else if receiverForCheck == doubleType || rawRhsType == doubleType {
                    doubleType
                } else if receiverForCheck == floatType || rawRhsType == floatType {
                    floatType
                } else if receiverForCheck == longType || rawRhsType == longType {
                    longType
                } else if (receiverForCheck == intType || receiverForCheck == byteType || receiverForCheck == shortType)
                    && (rawRhsType == intType || rawRhsType == byteType || rawRhsType == shortType)
                {
                    intType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "minus":
                let resultType: TypeID? = if !isNumericReceiver {
                    nil
                } else if receiverForCheck == charType && rawRhsType == charType {
                    intType
                } else if receiverForCheck == charType && rawRhsType == intType {
                    charType
                } else if rejectsArithmeticOperand(rawRhsType) {
                    nil
                } else if isUnsignedInteger(receiverForCheck) {
                    unsignedOperandResultType(rawRhsType)
                } else if isUnsignedInteger(rawRhsType) {
                    nil
                } else if receiverForCheck == doubleType || rawRhsType == doubleType {
                    doubleType
                } else if receiverForCheck == floatType || rawRhsType == floatType {
                    floatType
                } else if receiverForCheck == longType || rawRhsType == longType {
                    longType
                } else if (receiverForCheck == intType || receiverForCheck == byteType || receiverForCheck == shortType)
                    && (rawRhsType == intType || rawRhsType == byteType || rawRhsType == shortType) {
                    intType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "times", "div", "rem":
                let resultType: TypeID? = if rejectsArithmeticOperand(rawRhsType) {
                    nil
                } else if isUnsignedInteger(receiverForCheck) {
                    unsignedOperandResultType(rawRhsType)
                } else if isUnsignedInteger(rawRhsType) {
                    nil
                } else if receiverForCheck == doubleType || rawRhsType == doubleType {
                    doubleType
                } else if receiverForCheck == floatType || rawRhsType == floatType {
                    floatType
                } else if receiverForCheck == longType || rawRhsType == longType {
                    longType
                } else if (receiverForCheck == intType || receiverForCheck == byteType || receiverForCheck == shortType),
                    rawRhsType == intType || rawRhsType == byteType || rawRhsType == shortType
                {
                    intType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "floorDiv":
                if hasUserFloorDivExtension(
                    request, lookupReceiverType: lookupReceiverType, argTypes: argTypes, locals: locals
                ) {
                    return tryBindShadowedExtensionCallFallback(
                        request,
                        receiverType: receiverType,
                        lookupReceiverType: lookupReceiverType,
                        memberLookupType: lookupReceiverType,
                        argTypes: argTypes,
                        isClassNameReceiver: false,
                        isSuperCall: false,
                        locals: &locals
                    )
                }
                let resultType: TypeID? = if isNonNullNothingOperand {
                    if isSignedInteger(receiverForCheck) {
                        receiverForCheck == longType ? longType : intType
                    } else if isUnsignedInteger(receiverForCheck) {
                        receiverForCheck == ulongType ? ulongType : uintType
                    } else {
                        nil
                    }
                } else if isSignedInteger(receiverForCheck), isSignedInteger(rawRhsType) {
                    receiverForCheck == longType || rawRhsType == longType ? longType : intType
                } else if isUnsignedInteger(receiverForCheck), isUnsignedInteger(rawRhsType) {
                    receiverForCheck == ulongType || rawRhsType == ulongType ? ulongType : uintType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "mod":
                let resultType: TypeID? = if isNonNullNothingOperand {
                    if isSignedInteger(receiverForCheck) {
                        intType
                    } else if isUnsignedInteger(receiverForCheck) {
                        uintType
                    } else if isFloating(receiverForCheck) {
                        doubleType
                    } else {
                        nil
                    }
                } else if isFloating(receiverForCheck), isFloating(rawRhsType) {
                    receiverForCheck == doubleType || rawRhsType == doubleType ? doubleType : floatType
                } else if isSignedInteger(receiverForCheck), isSignedInteger(rawRhsType) {
                    rawRhsType == longType ? longType : intType
                } else if isUnsignedInteger(receiverForCheck), isUnsignedInteger(rawRhsType) {
                    rawRhsType
                } else {
                    nil
                }
                if let resultType {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "and", "or", "xor":
                if isBitwiseReceiver,
                   rawRhsType == receiverForCheck || isNonNullNothingOperand
                {
                    let resultType = receiverForCheck
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "shl", "shr":
                if isShiftReceiver,
                   rawRhsType == intType || isNonNullNothingOperand
                {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "ushr":
                if (receiverForCheck == intType || receiverForCheck == longType),
                   rawRhsType == intType || isNonNullNothingOperand
                {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            default:
                break
            }
        }

        if request.calleeName == request.knownNames.toString,
           request.args.isEmpty
        {
            let intType = request.sema.types.make(.primitive(.int, .nonNull))
            let longType = request.sema.types.make(.primitive(.long, .nonNull))
            let byteType = request.sema.types.byteType
            let shortType = request.sema.types.shortType
            let stringType = request.sema.types.stringType
            let receiverForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == byteType || receiverForCheck == shortType {
                let finalType = request.safeCall ? request.sema.types.makeNullable(stringType) : stringType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        let anyFallbackReceiverType = request.safeCall
            ? request.sema.types.makeNonNullable(lookupReceiverType)
            : lookupReceiverType
        let allowsAnyFallback: Bool = switch request.sema.types.kind(of: anyFallbackReceiverType) {
        case .stringStruct:
            false
        case .primitive:
            true
        case .typeParam:
            true
        case .nothing(.nonNull):
            request.safeCall
        default:
            anyFallbackReceiverType == request.sema.types.anyType || anyFallbackReceiverType == request.sema.types.nullableAnyType
        }

        if request.calleeName == request.knownNames.hashCode, request.args.isEmpty, allowsAnyFallback {
            let finalType = request.safeCall ? request.sema.types.makeNullable(request.sema.types.intType) : request.sema.types.intType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }

        if request.calleeName == request.knownNames.toString, request.args.isEmpty, allowsAnyFallback {
            let stringType = request.sema.types.stringType
            let finalType = request.safeCall ? request.sema.types.makeNullable(stringType) : stringType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }

        if request.calleeName == request.knownNames.equals, request.args.count == 1, allowsAnyFallback {
            if !request.safeCall, request.sema.types.nullability(of: lookupReceiverType) == .nullable {
                request.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0026",
                    "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                    range: request.range
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            let finalType = request.safeCall ? request.sema.types.makeNullable(request.sema.types.booleanType) : request.sema.types.booleanType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }

        if request.args.isEmpty {
            let intType = request.sema.types.make(.primitive(.int, .nonNull))
            let longType = request.sema.types.make(.primitive(.long, .nonNull))
            let uintType = request.sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = request.sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = request.sema.types.ubyteType
            let ushortType = request.sema.types.ushortType
            let byteType = request.sema.types.byteType
            let shortType = request.sema.types.shortType
            let floatType = request.sema.types.make(.primitive(.float, .nonNull))
            let doubleType = request.sema.types.make(.primitive(.double, .nonNull))
            let receiverForCheck = request.safeCall
                ? request.sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = request.interner.resolve(request.calleeName)
            let (targetType, matches): (TypeID, Bool) = switch calleeStr {
            case "toInt": (intType, receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toUInt": (uintType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toLong": (longType, receiverForCheck == intType || receiverForCheck == uintType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == longType || receiverForCheck == ulongType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toULong": (ulongType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toFloat": (floatType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == doubleType || receiverForCheck == floatType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toDouble": (doubleType, receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toByte": (byteType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toShort": (shortType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toUByte": (request.sema.types.ubyteType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toUShort": (request.sema.types.ushortType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == byteType || receiverForCheck == shortType)
            case "toChar": (request.sema.types.charType, receiverForCheck == byteType || receiverForCheck == shortType)
            default: (request.sema.types.errorType, false)
            }
            if matches {
                let finalType = request.safeCall ? request.sema.types.makeNullable(targetType) : targetType
                let deprecatedCallee = driver.helpers.checkBuiltinDeprecation(
                    calleeName: request.calleeName,
                    receiverType: receiverForCheck,
                    sema: request.sema,
                    interner: request.interner,
                    range: request.range,
                    diagnostics: request.ctx.sema.diagnostics
                )
                // KUU-3763: Byte/Short.toChar() has no entry in the KIR
                // conversion tables, so an unbound call fell back to a
                // same-named inline candidate and died in the inliner
                // (KSWIFTK-INL-0001). Binding the bundled deprecated decl
                // emits a real call, which a @Suppress('DEPRECATION_ERROR')
                // site can still execute.
                if let deprecatedCallee {
                    request.sema.bindings.bindCall(request.id, binding: CallBinding(
                        chosenCallee: deprecatedCallee,
                        substitutedTypeArguments: [],
                        parameterMapping: [:]
                    ))
                }
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }
        return nil
    }
}
