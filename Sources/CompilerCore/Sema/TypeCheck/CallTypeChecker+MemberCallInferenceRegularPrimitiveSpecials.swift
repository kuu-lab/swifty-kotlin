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
            // kotlinc exposes six compareTo overloads on each signed primitive
            // receiver, so `i.compareTo(TODO())` is ambiguous there. KSwiftK
            // binds the single Comparable<T> member instead and must report the
            // ambiguity itself (KUU-4351). Unsigned primitives keep their
            // unique resolution, matching kotlinc.
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
            // Range expressions use their scalar element type as the lowering
            // type. Keep them out of the numeric fast path so range extensions
            // such as Iterable.plus/minus can be resolved from the source-level
            // range receiver instead.
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
            // In Kotlin stdlib, small unsigned types promote to UInt for most
            // arithmetic (plus/minus/times/div/rem). `mod` returns the RHS type.
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
            // KUU-4015: a non-null `Nothing` operand is a subtype of every
            // parameter type, so kotlinc applies its overload most-specific
            // rules (integer/float widening priority) and accepts calls whose
            // winner is unique — `x.mod(TODO())`, `u.floorDiv(TODO())`,
            // `c.plus(TODO())`, `x.and(TODO())`. Ambiguous winners such as
            // `x.plus(TODO())` or `c.minus(TODO())` still fall through to
            // normal resolution and are rejected there, matching kotlinc.
            let isNonNullNothingOperand = {
                if case .nothing(.nonNull) = request.sema.types.kind(of: rawRhsType) {
                    return true
                }
                return false
            }()
            // KUU-4351: operator `compareTo` calls take the member-call path
            // too, but a non-null `Nothing` argument makes every primitive
            // overload applicable and kotlinc reports the signed and
            // floating-point sets as ambiguous. Char and the unsigned types
            // keep a unique winner and fall through to normal resolution.
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
            // Kotlin's unsigned arithmetic members (plus/minus/times/div/rem)
            // only take unsigned operands — e.g. UInt.plus(UByte/UShort/UInt/
            // ULong). Signed, floating-point, or nullable operands have no
            // overload, so such calls must fall through to normal resolution
            // instead of being bound here (KUU-3936). A non-null Nothing
            // argument (`u.plus(TODO())`) still typechecks, matching kotlinc.
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
                // Collection plus(element) must reach overload resolution instead of
                // being mistaken for primitive arithmetic based only on the RHS type.
                let resultType: TypeID? = if !isNumericReceiver {
                    nil
                } else if receiverForCheck == charType && rawRhsType == intType {
                    charType
                } else if receiverForCheck == charType && isNonNullNothingOperand {
                    // Char.plus(Int) is the only member overload and beats the
                    // Char.plus(String) extension, so a Nothing operand resolves.
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
                    // Signed/floating receivers have no unsigned-operand
                    // overload either (`x.plus(1u)` fails in kotlinc).
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
                // Collection minus(element) must reach overload resolution just like plus(element).
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
                // times/div/rem: small unsigned types promote to UInt (Kotlin stdlib)
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
                    // KUU-4015: same most-specific winner as mod — the
                    // Int/UInt-parameter overload — except Long/ULong
                    // receivers keep their wider floorDiv result type.
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
                // mod overloads return the divisor type for integer overloads and
                // use normal Float/Double widening for floating operands.
                let resultType: TypeID? = if isNonNullNothingOperand {
                    // KUU-4015: every mod overload is applicable; the
                    // most-specific winner is the Int-parameter overload for
                    // signed receivers (Int result), the UInt-parameter
                    // overload for unsigned receivers (UInt result), and the
                    // Double-parameter overload for floating receivers.
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
                // KUU-4015: each bitwise op has a single receiver-typed
                // overload, so a Nothing operand resolves to the receiver type.
                if isBitwiseReceiver,
                   rawRhsType == receiverForCheck || isNonNullNothingOperand
                {
                    let resultType = receiverForCheck
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "shl", "shr":
                // KUU-4015: shifts take a single Int bitCount parameter, so a
                // Nothing operand resolves to the receiver type.
                if isShiftReceiver,
                   rawRhsType == intType || isNonNullNothingOperand
                {
                    let finalType = request.safeCall ? request.sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
            case "ushr":
                // Unsigned integers only expose shl/shr; ushr is signed-only.
                // KUU-4015: the single Int bitCount parameter also accepts a
                // Nothing operand.
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

        // STDLIB-NUM-130 / KSP-638 / KSP-647: floating-point precision and bit helpers
        // (isNaN / isInfinite / isFinite / toBits / toRawBits) are declared by bundled
        // Kotlin source. Their internal __kk_* bridges are ordinary source declarations,
        // so they must flow through normal extension resolution instead of a primitive
        // name-based fast path. ulp / nextUp / nextDown remain runtime-backed synthetic
        // functions until their respective migrations.

        // Unsigned coercion (UByte/UShort/UInt/ULong) is handled by bundled Kotlin source
        // (RangeCoercion.kt); no primitive fast-path is needed.

        // KSP-642: Int/Long rotateLeft / rotateRight resolve through the bundled Kotlin
        // declarations in `Stdlib/kotlin/Numbers.kt`, so no special inference is needed.

        // Primitive member function: Int/Long/Byte/Short.toString() → String
        // (STDLIB-306). Int/Long.toString(radix: Int) is bundled Kotlin source
        // (Stdlib/kotlin/text/StringNumberConversions.kt, KSP-717) and resolves
        // through normal extension-function overload resolution below instead.
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
            // All type parameters have an implicit upper bound of Any? in Kotlin,
            // so Any methods (toString, hashCode, equals) are always available on
            // type parameter receivers (STDLIB-GEN-055).
            true
        case .nothing(.nonNull):
            // `Nothing` is a subtype of every Kotlin type including `Any`, so its
            // member scope is `Any`'s and `toString`/`hashCode`/`equals` are the
            // single valid candidates. A safe call unwraps a `Nothing?` receiver
            // to non-null `Nothing`; resolving to `Any`'s member here (instead of
            // collecting unrelated `toString` extensions that the bottom type is
            // nominally a subtype of) matches kotlinc for `null?.toString()`
            // (KUU-3146). Non-safe `Nothing` receivers keep ordinary resolution.
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
