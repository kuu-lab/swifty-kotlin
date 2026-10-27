
final class ABILoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "ABILowering"
    static let requiredStage: KIRStage = .integerNarrowed
    static let producedStage: KIRStage = .abiLowered

    static func primitiveBoxingCallee(for primitive: PrimitiveType, interner: StringInterner) -> InternedString {
        guard let callee = BoxingCalleeTable(interner: interner).boxCallee(for: primitive) else {
            preconditionFailure("No boxing callee registered for \(primitive)")
        }
        return callee
    }

    static func primitiveUnboxingCallee(for primitive: PrimitiveType, interner: StringInterner) -> InternedString {
        guard let callee = BoxingCalleeTable(interner: interner).unboxCallee(for: primitive) else {
            preconditionFailure("No unboxing callee registered for \(primitive)")
        }
        return callee
    }

    static func primitiveUnboxingCallee(for kind: TypeKind, interner: StringInterner) -> InternedString? {
        BoxingCalleeTable(interner: interner).unboxCallee(for: kind, requireNonNull: false)
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCalleeSet = nonThrowingCallees(interner: ctx.interner)
        let boxingCalleeTable = BoxingCalleeTable(interner: ctx.interner)
        let intNarrowingCallee = ctx.interner.intern("kk_int_narrow")
        let listViewChecks = listViewCheckedArguments(interner: ctx.interner)
        let listViewCheckCallee = ctx.interner.intern("__kk_list_check_modification")

        let types = ctx.sema?.types
        let symbols = ctx.sema?.symbols
        let listViewMembers = listViewMemberMatcher(symbols: symbols, interner: ctx.interner)

        let inlineArithmeticCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_add"),
            ctx.interner.intern("kk_op_sub"),
            ctx.interner.intern("kk_op_mul"),
            ctx.interner.intern("kk_op_div"),
            ctx.interner.intern("kk_op_floor_div"),
            ctx.interner.intern("kk_op_lfloor_div"),
            ctx.interner.intern("kk_op_mod"),
            ctx.interner.intern("kk_op_floor_mod"),
            ctx.interner.intern("kk_op_lfloor_mod"),
            ctx.interner.intern("kk_op_ffloor_mod"),
            ctx.interner.intern("kk_op_dfloor_mod"),
            ctx.interner.intern("kk_op_fadd"),
            ctx.interner.intern("kk_op_fsub"),
            ctx.interner.intern("kk_op_fmul"),
            ctx.interner.intern("kk_op_fdiv"),
            ctx.interner.intern("kk_op_fmod"),
            ctx.interner.intern("kk_op_dadd"),
            ctx.interner.intern("kk_op_dsub"),
            ctx.interner.intern("kk_op_dmul"),
            ctx.interner.intern("kk_op_ddiv"),
            ctx.interner.intern("kk_op_dmod"),
            ctx.interner.intern("kk_op_udiv"),
            ctx.interner.intern("kk_op_urem"),
            ctx.interner.intern("kk_op_uadd"),
            ctx.interner.intern("kk_op_usub"),
            ctx.interner.intern("kk_op_umul"),
        ]
        // Comparison operators: result type is Boolean so we cannot use the
        // result to drive unboxing.  Idempotent for already-unboxed values
        // (kk_unbox_* passes raw primitives through unchanged).
        let inlineComparisonCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_eq"),
            ctx.interner.intern("kk_op_ne"),
            ctx.interner.intern("kk_op_lt"),
            ctx.interner.intern("kk_op_le"),
            ctx.interner.intern("kk_op_gt"),
            ctx.interner.intern("kk_op_ge"),
            ctx.interner.intern("kk_op_ult"),
            ctx.interner.intern("kk_op_ule"),
            ctx.interner.intern("kk_op_ugt"),
            ctx.interner.intern("kk_op_uge"),
            ctx.interner.intern("kk_op_deq"),
            ctx.interner.intern("kk_op_dne"),
            ctx.interner.intern("kk_op_dlt"),
            ctx.interner.intern("kk_op_dle"),
            ctx.interner.intern("kk_op_dgt"),
            ctx.interner.intern("kk_op_dge"),
            ctx.interner.intern("kk_op_feq"),
            ctx.interner.intern("kk_op_fne"),
            ctx.interner.intern("kk_op_flt"),
            ctx.interner.intern("kk_op_fle"),
            ctx.interner.intern("kk_op_fgt"),
            ctx.interner.intern("kk_op_fge"),
            ctx.interner.intern("kk_double_equals"),
            ctx.interner.intern("kk_float_equals"),
        ]
        let unitEqualityCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_eq"),
            ctx.interner.intern("kk_op_ne"),
            ctx.interner.intern("kk_structural_eq"),
            ctx.interner.intern("kk_structural_ne"),
            // The sentinel-safe nullable comparison likewise receives its
            // operands raw: a value-class peer (e.g. `v2 == v1` where `v2`
            // is `V?` for a Double-backed `V`) must arrive tagged so the
            // runtime's nominal check can match it against the box the `V?`
            // slot carries (KUU-3616). The trailing flag literal is a plain
            // Int and passes through untouched.
            ctx.interner.intern("kk_nullable_primitive_eq"),
            ctx.interner.intern("kk_nullable_primitive_ne"),
            // The signature-less Any-equals fallback takes
            // (receiver, receiverTag, arg, argTag): the value slots can
            // carry a raw value-class payload the bridge would otherwise
            // compare as the bare underlying primitive (KUU-3616). The tag
            // slots are Int literals and pass through untouched.
            ctx.interner.intern("kk_any_equals"),
        ]
        // Membership intrinsics (`x in c` / `contains`) receive their element
        // argument raw: enum-typed parameters carry ordinals, while stored
        // elements are boxed. Enum operands meet the stored elements as the
        // canonical entry box — the same normalization `==`/`!=` receive — so
        // `E.A in listOf(E.A)` compares nominal identity, not ordinal payload
        // (KUU-2957). Integral scalars box for the same reason: a bare `0`
        // probe would alias a stored enum box by ordinal, while the JVM keeps
        // `0 in listOf(E.A as Any)` false (KUU-3027). The runtime probes stay
        // correct for raw ordinals too, but boxing removes the ambiguity.
        let membershipElementCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_contains"),
            ctx.interner.intern("kk_sequence_contains"),
            ctx.interner.intern("kk_sequence_indexOf"),
            ctx.interner.intern("kk_sequence_lastIndexOf"),
            ctx.interner.intern("kk_sequence_minus"),
        ]

        // Type-check intrinsics: `value` is a bare Int that the runtime can only
        // tell apart as Int/UInt/ULong/Long/Double/Float/Char by inspecting a
        // boxed pointer's Swift type — unlike Boolean/Unit, none of these share a
        // sound unboxed-value heuristic (they all reinterpret the same 64-bit
        // word). Box `value` whenever its intrinsic type is a concrete primitive,
        // even if the checked expression's own declared type is already a
        // concrete primitive (e.g. `x is Long` where `x: Int`): KIR local
        // declarations alias a variable directly to its initializer expression
        // (see ExprLowerer+ControlFlowAndBlocks.localDecl), so an unboxed literal
        // or primitive-typed value can flow into a type check unmodified.
        // These callees have no FunctionSignature, so the normal argument-boxing
        // path above leaves them untouched.
        let typeCheckValueCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_is"),
            ctx.interner.intern("kk_op_cast"),
            ctx.interner.intern("kk_op_safe_cast"),
        ]

        // Callees that retrieve an erased value from a collection, object field,
        // or closure environment. These slots may contain a boxed pointer even
        // when the KIR result type is a non-null primitive. Normalize at the
        // retrieval site so downstream arithmetic, comparisons, and calls see
        // the plain primitive value.
        let erasedValueAccessorCallees: Set<InternedString> = [
            ctx.interner.intern("__kk_list_get"),
            ctx.interner.intern("__kk_map_get"),
            ctx.interner.intern("kk_list_iterator_next"),
            ctx.interner.intern("kk_list_iterator_previous"),
            ctx.interner.intern("kk_array_get_inbounds"),
        ]

        // `kk_array_get` reads an element out of both generic `Array<T>` (boxed
        // elements) and the primitive arrays (raw elements), so it needs the
        // same unboxing as the accessors above only for the generic receiver;
        // unboxing a raw `DoubleArray` element would corrupt values such as -0.0.
        let genericArrayGetCallee = ctx.interner.intern("kk_array_get")
        let arrayClassName = ctx.interner.intern("Array")

        // `kk_array_is_empty` returns a boxed Boolean but is emitted for both
        // generic and primitive arrays without a Sema function signature. Keep
        // its result on the same ABI normalization path as other erased
        // collection results so conditions compare the unboxed Boolean.
        let boxedBooleanReturnCallees: Set<InternedString> = [
            ctx.interner.intern("kk_array_is_empty"),
        ]

        // The typed rangeUntil bridges back the `until` infix function (registered in
        // bundled Kotlin source with a scalar Int/Long return type, matching
        // the isRangeExpr duck-typing convention used for range operators,
        // but always return boxed RuntimeRangeBox
        // references at runtime (see the typed rangeUntil bridges in Runtime).
        // Unlike `..`/`downTo`/`step`, calls to the named `until` function carry a
        // resolved Sema symbol, so resolveUnboxForCall would otherwise see a
        // Long/Int-typed return and insert an erroneous kk_unbox_long/kk_unbox_int
        // on the range object itself.
        let boxedReturnRangeCallees: Set<InternedString> = [
            ctx.interner.intern("__kk_op_rangeUntil"),
            ctx.interner.intern("__kk_long_rangeUntil"),
            ctx.interner.intern("__kk_char_rangeUntil"),
            ctx.interner.intern("__kk_uint_rangeUntil"),
        ]

        let unboxSkipCallees = boxedReturnRangeCallees.union(
            rawBooleanReturnCallees(interner: ctx.interner)
        )

        var signatureByName: [InternedString: FunctionSignature] = [:]
        // `$default` stubs have no Sema signature. Recover their actual ABI
        // from the KIR declaration, preferring the synthetic symbol and using
        // the name for symbol-less calls (KUU-3224).
        var stubSignatureByName: [InternedString: FunctionSignature] = [:]
        var stubSignatureBySymbol: [SymbolID: FunctionSignature] = [:]
        if let symbols {
            for decl in module.arena.declarations {
                guard case let .function(fn) = decl else { continue }
                if let sig = symbols.functionSignature(for: fn.symbol) {
                    signatureByName[fn.name] = sig
                }
                if SyntheticSymbolScheme.isSyntheticCallTarget(fn.symbol),
                   !SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(fn.symbol)
                {
                    let stubSignature = FunctionSignature(
                        parameterTypes: fn.params.map(\.type),
                        returnType: fn.returnType,
                        isSuspend: fn.isSuspend
                    )
                    stubSignatureByName[fn.name] = stubSignature
                    stubSignatureBySymbol[fn.symbol] = stubSignature
                }
            }
        }
        // A nullable-underlying value class needs a heap box while its
        // constructor body writes the underlying field. Preserve that boxed
        // receiver both on direct constructor calls and across the generated
        // constructor `$default` stub; ordinary value-class arguments still
        // follow the payload ABI.
        var nullableUnderlyingValueClassConstructors: Set<SymbolID> = []
        var nullableUnderlyingValueClassDefaultStubReceiverIndices: [SymbolID: Int] = [:]
        if let symbols, let types {
            for constructor in symbols.symbols(ofKind: .constructor) {
                guard let owner = symbols.parentSymbol(for: constructor),
                      nullableUnderlyingValueClassSymbol(
                          of: .classType(ClassType(classSymbol: owner)),
                          types: types,
                          symbols: symbols
                      ) != nil
                else {
                    continue
                }
                nullableUnderlyingValueClassConstructors.insert(constructor)
                let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: constructor)
                let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: constructor)
                if let stub = module.arena.function(for: stubSymbol),
                   let receiverIndex = stub.params.firstIndex(where: { $0.symbol == receiverSymbol })
                {
                    nullableUnderlyingValueClassDefaultStubReceiverIndices[stubSymbol] = receiverIndex
                }
            }
        }

        // ABI-002: An inline body imported from a library artifact records only
        // the link name for a callee whose declaration is synthetic in this
        // compilation, so the call arrives with no symbol and no KIR
        // declaration to recover a signature from (LibraryInlineImport resolves
        // `linkB64` against imported bindings only). Without the declared
        // parameter types the boxing rules below cannot see the erased
        // type-parameter slots of the boundary bridges, and `map[k] = v` — the
        // bundled inline `kotlin.collections.set` forwarding to `put` — stores a
        // raw Double/Float/Char/Boolean word that later renders as its bit
        // pattern. Only the documented boundary bridges are recovered here, and
        // boxing still follows their declared parameter types, so a bridge's raw
        // Int parameter (e.g. the index of `__kk_mutable_list_add_at`) stays raw.
        var boundaryBridgeSignatureByLinkName: [InternedString: FunctionSignature] = [:]
        if let symbols {
            var ambiguousBoundaryBridges: Set<InternedString> = []
            for symbol in symbols.allSymbols() where symbol.kind == .function {
                guard let linkName = symbols.externalLinkNameIfKnown(for: symbol.id),
                      Self.typeParamBoxingBoundaryCallees.contains(linkName),
                      let signature = symbols.functionSignature(for: symbol.id)
                else {
                    continue
                }
                let key = ctx.interner.intern(linkName)
                guard !ambiguousBoundaryBridges.contains(key) else { continue }
                if let existing = boundaryBridgeSignatureByLinkName[key] {
                    // Two declarations claiming one bridge name give no basis to
                    // pick a parameter list; leave the call unboxed rather than
                    // guessing. The comparison is on raw TypeIDs, so distinct
                    // type parameters (`MutableMap.V` vs a future overrider's
                    // own `V`) count as a conflict and disable recovery for that
                    // bridge — the conservative direction, but it means boxing
                    // can stop for a bridge that gains a second declaration.
                    if existing.parameterTypes != signature.parameterTypes
                        || existing.receiverType != signature.receiverType
                    {
                        boundaryBridgeSignatureByLinkName.removeValue(forKey: key)
                        ambiguousBoundaryBridges.insert(key)
                    }
                    continue
                }
                boundaryBridgeSignatureByLinkName[key] = signature
            }
        }

        // Inline expansion can substitute a raw concrete enum ordinal into
        // the compiler-owned abstract Enum.name bridge. Restore its erased
        // receiver contract so normal enum boxing runs at this boundary.
        if let types {
            boundaryBridgeSignatureByLinkName[ctx.interner.intern("__kk_enum_name")] = FunctionSignature(
                parameterTypes: [types.anyType], returnType: types.stringType
            )
        }

        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated: KIRFunction = function
            var newBody = KIRLoweringEmitContext()
            newBody.instructions.reserveCapacity(function.body.count)
            var nullableGenericResults: Set<KIRExprID> = []

            let functionReturnKind: TypeKind? = types.map { $0.kind(of: function.returnType) }

            var idx = 0
            while idx < function.body.count {
                newBody.currentSourceRange = idx < function.instructionLocations.count
                    ? function.instructionLocations[idx]
                    : nil
                let instruction = function.body[idx]
                if case let .virtualCall(vcSymbol, vcCallee, vcReceiver, vcArguments, vcResult, _, vcThrownResult, vcDispatch) = instruction {
                    if let vcSymbol, listViewMembers.contains(vcSymbol) {
                        appendListViewChecks(
                            arguments: [vcReceiver], checkedIndices: [0], thrownResult: vcThrownResult,
                            followingInstructions: function.body[(idx + 1)...],
                            checkCallee: listViewCheckCallee, newBody: &newBody
                        )
                    }
                    let vcIsClosureRelated = module.nonThrowingClosureCallees.contains(vcCallee)
                    let vcCanThrow = !vcIsClosureRelated
                        && !nonThrowingCalleeSet.contains(vcCallee)
                    var vcSignature: FunctionSignature?
                    if let symbols, let vcSymbol {
                        vcSignature = symbols.functionSignature(for: vcSymbol)
                    }
                    if vcSignature == nil {
                        vcSignature = signatureByName[vcCallee]
                    }
                    let vcBoxedArguments: [KIRExprID] = if let vcSignature, let types {
                        applyArgumentBoxing(
                            arguments: vcArguments,
                            signature: vcSignature,
                            receiverOffset: vcSymbol.flatMap {
                                symbols?.memberExtensionOwnerSymbol(for: $0)
                            } != nil ? 1 : 0,
                            module: module,
                            types: types,
                            symbols: symbols,
                            boxingCalleeTable: boxingCalleeTable,
                            callee: vcCallee,
                            interner: ctx.interner,
                            boxTypeParamArguments: isKotlinSourceCallee(vcSymbol, symbols: symbols),
                            sema: ctx.sema,
                            cache: ctx.nominalDispatchCache,
                            newBody: &newBody
                        )
                    } else {
                        vcArguments
                    }
                    let vcUnbox = resolveUnboxForCall(
                        callSymbol: vcSymbol,
                        callee: vcCallee,
                        arguments: vcArguments,
                        receiver: vcReceiver,
                        result: vcResult,
                        signatureByName: signatureByName,
                        module: module,
                        types: types,
                        symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable,
                        nullableGenericResults: &nullableGenericResults,
                        boxedReturnCallees: unboxSkipCallees
                    )
                    let vcResultConversion = resolveValueClassResultConversion(
                        callSymbol: vcSymbol,
                        callee: vcCallee,
                        result: vcResult,
                        signatureByName: signatureByName,
                        module: module,
                        types: types,
                        symbols: symbols,
                        rawValueReturningCallees: typeCheckValueCallees,
                        boxedReturnCallees: unboxSkipCallees
                    )
                    if let vcResultConversion, let vcResult, let types, let symbols {
                        let tempResult = module.arena.appendTemporary(
                            type: vcResultConversion.returnType
                        )
                        newBody.append(.virtualCall(
                            symbol: vcSymbol,
                            callee: vcCallee,
                            receiver: vcReceiver,
                            arguments: vcBoxedArguments,
                            result: tempResult,
                            canThrow: vcCanThrow,
                            thrownResult: vcThrownResult,
                            dispatch: vcDispatch
                        ))
                        if vcThrownResult != nil {
                            let nextIdx = idx + 1
                            if nextIdx < function.body.count,
                               case .jumpIfNotNull = function.body[nextIdx]
                            {
                                newBody.append(function.body[nextIdx])
                                idx += 1
                            }
                        }
                        appendValueClassResultConversion(
                            conversion: vcResultConversion,
                            from: tempResult,
                            to: vcResult,
                            module: module,
                            types: types,
                            symbols: symbols,
                            interner: ctx.interner,
                            into: &newBody
                        )
                    } else if let (vcUnboxCallee, vcReturnType) = vcUnbox, let vcResult {
                        let tempResult = module.arena.appendTemporary(type: vcReturnType
                        )
                        newBody.append(.virtualCall(
                            symbol: vcSymbol,
                            callee: vcCallee,
                            receiver: vcReceiver,
                            arguments: vcBoxedArguments,
                            result: tempResult,
                            canThrow: vcCanThrow,
                            thrownResult: vcThrownResult,
                            dispatch: vcDispatch
                        ))
                        if vcThrownResult != nil {
                            let nextIdx = idx + 1
                            if nextIdx < function.body.count,
                               case .jumpIfNotNull = function.body[nextIdx]
                            {
                                newBody.append(function.body[nextIdx])
                                idx += 1
                            }
                        }
                        emitNonThrowingCall(
                            callee: vcUnboxCallee,
                            arg: tempResult,
                            result: vcResult,
                            into: &newBody
                        )
                    } else {
                        newBody.append(.virtualCall(
                            symbol: vcSymbol,
                            callee: vcCallee,
                            receiver: vcReceiver,
                            arguments: vcBoxedArguments,
                            result: vcResult,
                            canThrow: vcCanThrow,
                            thrownResult: vcThrownResult,
                            dispatch: vcDispatch
                        ))
                    }
                    idx += 1
                    continue
                }

                if case let .returnValue(value) = instruction, let types,
                   let rewritten = rewriteReturnValueBoxingOrUnboxing(
                       value: value,
                       functionReturnKind: functionReturnKind,
                       returnType: function.returnType,
                       module: module, types: types, symbols: symbols,
                       interner: ctx.interner,
                       boxingCalleeTable: boxingCalleeTable,
                       sema: ctx.sema,
                       cache: ctx.nominalDispatchCache
                   )
                {
                    newBody.append(contentsOf: rewritten)
                    idx += 1
                    continue
                }
                if case .returnValue = instruction {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Narrowing produces a raw Int. Unboxing it again can mistake a
                // positive arithmetic result for a live box address on non-PIE Linux.
                // Require the adjacent producer and non-null Int types on both sides;
                // copies into nullable or erased slots still need the normal boxing.
                if case let .copy(from, to) = instruction, idx > 0,
                   case let .call(_, callee, _, result, _, _, _, _) = function.body[idx - 1],
                   callee == intNarrowingCallee, result == from,
                   let types,
                   module.arena.exprType(from) == types.intType,
                   module.arena.exprType(to) == types.intType
                {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                if case let .copy(_, to) = instruction,
                   module.isRawValueClassPayload(to)
                {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                if case let .copy(from, to) = instruction, let types,
                   let rewritten = rewriteCopyBoxingOrUnboxing(
                       from: from, to: to,
                       module: module, types: types, symbols: symbols,
                       interner: ctx.interner,
                       boxingCalleeTable: boxingCalleeTable,
                       sema: ctx.sema,
                       cache: ctx.nominalDispatchCache
                   )
                {
                    newBody.append(contentsOf: rewritten)
                    idx += 1
                    continue
                }
                if case .copy = instruction {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                if case let .binary(op, lhs, rhs, result) = instruction, let types {
                    let newLhs = unboxBinaryOperandIfNeeded(
                        operand: lhs, resultExpr: result,
                        module: module, types: types, symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                    )
                    let newRhs = unboxBinaryOperandIfNeeded(
                        operand: rhs, resultExpr: result,
                        module: module, types: types, symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                    )
                    newBody.append(.binary(op: op, lhs: newLhs, rhs: newRhs, result: result))
                    idx += 1
                    continue
                }

                // `var x: V? = V(...)` stores into a backing field/global slot
                // bypass `.copy`, so the `V` -> `V?` boundary is normalized
                // here for nullable-underlying value classes (KUU-3115).
                if case let .storeGlobal(value, symbol) = instruction,
                   let types, let symbols,
                   let slotType = symbols.propertyType(for: symbol),
                   let valueType = intrinsicArgType(value, arena: module.arena, types: types),
                   let vcSymbol = nullableUnderlyingValueClassSymbol(
                       of: types.kind(of: valueType), types: types, symbols: symbols
                   ),
                   valueClassBoxTargetIsBoxed(types.kind(of: slotType), symbols: symbols)
                {
                    let boxed = module.arena.appendTemporary(type: slotType)
                    emitValueClassBoxCall(
                        value: value, classSymbol: vcSymbol, result: boxed,
                        resultType: slotType, types: types, symbols: symbols,
                        interner: ctx.interner, arena: module.arena, into: &newBody
                    )
                    newBody.append(.storeGlobal(value: boxed, symbol: symbol))
                    idx += 1
                    continue
                }

                guard case let .call(callSymbol, callee, arguments, result, _, thrownResult, isSuperCall, qualifiedSuperType) = instruction else {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Most synthetic property accessors are field/property plumbing
                // and historically have no throwing ABI. Delegated properties
                // are different: their accessor invokes delegate getValue or
                // setValue, which can throw (e.g. Delegates.notNull()).
                let isSyntheticAccessor: Bool = {
                    guard let s = callSymbol else { return false }
                    return SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(s)
                }()
                let isDelegatedAccessor: Bool = {
                    guard isSyntheticAccessor,
                          let s = callSymbol,
                          let syms = symbols
                    else { return false }
                    let propertySymbol = SyntheticSymbolScheme.originalPropertySymbolFromAccessor(s)
                    return syms.delegateStorageSymbol(for: propertySymbol) != nil
                }()
                let rewrittenCallee: InternedString? = {
                    guard isSyntheticAccessor,
                          let s = callSymbol,
                          SyntheticSymbolScheme.isLikelySyntheticSetterAccessor(s),
                          callee == ctx.interner.intern("set"),
                          let syms = symbols
                    else { return nil }
                    let propSym = SyntheticSymbolScheme.originalPropertySymbolFromSetterAccessor(s)
                    guard let getterLink = syms.externalLinkNameIfKnown(for: propSym),
                          getterLink.hasSuffix("_load")
                    else { return nil }
                    let storeLinkName = String(getterLink.dropLast("_load".count)) + "_store"
                    return ctx.interner.intern(storeLinkName)
                }()
                var effectiveCallee = rewrittenCallee ?? callee
                if let firstArgument = arguments.first,
                   nullableGenericResults.contains(firstArgument)
                {
                    switch ctx.interner.resolve(effectiveCallee) {
                    case "kk_box_double_nonnull":
                        effectiveCallee = ctx.interner.intern("kk_box_double")
                    case "kk_box_double_nonnull_static":
                        effectiveCallee = ctx.interner.intern("kk_box_double_static")
                    case "kk_box_long_nonnull":
                        effectiveCallee = ctx.interner.intern("kk_box_long")
                    case "kk_box_long_nonnull_static":
                        effectiveCallee = ctx.interner.intern("kk_box_long_static")
                    default:
                        break
                    }
                }
                let effectiveCallSymbol: SymbolID? = rewrittenCallee != nil ? nil : callSymbol
                let runtimeLink = effectiveCallSymbol.flatMap { symbols?.externalLinkNameIfKnown(for: $0) }
                    .map { ctx.interner.intern($0) } ?? effectiveCallee
                let checkedIndices = listViewChecks[runtimeLink]
                    ?? (effectiveCallSymbol.map { listViewMembers.contains($0) } == true ? [0] : nil)
                if let checkedIndices {
                    appendListViewChecks(
                        arguments: arguments,
                        checkedIndices: checkedIndices,
                        thrownResult: thrownResult,
                        followingInstructions: function.body[(idx + 1)...],
                        checkCallee: listViewCheckCallee,
                        newBody: &newBody
                    )
                }
                // Stubs explicitly marked .throwingFunction must always emit the
                // outThrown channel regardless of whether their callee name appears
                // in nonThrowingCallees.
                let isExplicitlyThrowing: Bool = {
                    if isSyntheticAccessor, let s = callSymbol,
                       symbols?.functionSignature(for: s)?.canThrow == true {
                        return true
                    }
                    guard let s = callSymbol, let sym = symbols?.symbol(s) else { return false }
                    return sym.flags.contains(.throwingFunction)
                }()
                // Source-backed bridge calls keep the Kotlin declaration name in
                // KIR (for example, `__kk_duration_parseOrNull`) while the ABI
                // throwing contract is keyed by the external runtime link name
                // (`kk_duration_parseOrNull`). Consult both names so a
                // non-throwing bridge does not acquire an outThrown parameter
                // merely because its source name is absent from the runtime set.
                let isNonThrowingExternalLink: Bool = {
                    guard let s = effectiveCallSymbol,
                          let linkName = symbols?.externalLinkNameIfKnown(for: s)
                    else {
                        return false
                    }
                    return nonThrowingCalleeSet.contains(ctx.interner.intern(linkName))
                }()
                // Only explicitly proven non-throwing callees may bypass the
                // channel. Closure conversion does not prove source lambda bodies
                // non-throwing before their calls have undergone ABI lowering.
                let isClosureRelatedCallee = module.nonThrowingClosureCallees.contains(effectiveCallee)
                let effectiveCalleeName = ctx.interner.resolve(effectiveCallee)
                let isFunctionValueInvoke = effectiveCalleeName == "kk_function_invoke"
                    || effectiveCalleeName.hasPrefix("kk_function_invoke_")
                    || effectiveCalleeName == "kk_suspend_function_invoke"
                    || effectiveCalleeName.hasPrefix("kk_suspend_function_invoke_")
                let canThrow = isExplicitlyThrowing
                    || isDelegatedAccessor
                    // FunctionN.invoke forwards exceptions from an arbitrary
                    // callback, even though its own Kotlin declaration has no
                    // throws annotation and closure analysis may mark it pure.
                    || isFunctionValueInvoke
                    || (!isSyntheticAccessor
                        && !isClosureRelatedCallee
                        && !nonThrowingCalleeSet.contains(effectiveCallee)
                        && !isNonThrowingExternalLink)

                var signature: FunctionSignature?
                var recoveredStubSignature = false
                if let symbols, let effectiveCallSymbol {
                    signature = symbols.functionSignature(for: effectiveCallSymbol)
                }
                // A default stub's symbol identifies its owner even when other
                // declarations have the same `$default` display name.
                if signature == nil, let effectiveCallSymbol,
                   let stubSignature = stubSignatureBySymbol[effectiveCallSymbol]
                {
                    signature = stubSignature
                    recoveredStubSignature = true
                }
                if signature == nil {
                    signature = signatureByName[effectiveCallee]
                }
                if signature == nil {
                    signature = stubSignatureByName[effectiveCallee]
                    recoveredStubSignature = signature != nil
                }
                // Default stubs do not have Sema signatures. Their KIR params
                // include the receiver as an ordinary argument, so recover the
                // concrete signature when an enum slot needs ABI adaptation.
                if signature == nil,
                   let stubSymbol = effectiveCallSymbol,
                   SyntheticSymbolScheme.isSyntheticCallTarget(stubSymbol),
                   !SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(stubSymbol),
                   let stub = module.arena.function(for: stubSymbol),
                   let types,
                   stub.params.contains(where: { parameter in
                       guard case let .classType(classType) = types.kind(of: parameter.type) else { return false }
                       return classType.nullability == .nonNull
                           && symbols?.symbol(classType.classSymbol)?.kind == .enumClass
                   })
                {
                    signature = FunctionSignature(
                        parameterTypes: stub.params.map(\.type),
                        returnType: stub.returnType,
                        isSuspend: stub.isSuspend
                    )
                }
                // ABI-002: see boundaryBridgeSignatureByLinkName above.
                if signature == nil, effectiveCallSymbol == nil {
                    signature = boundaryBridgeSignatureByLinkName[effectiveCallee]
                }
                var boxedArguments: [KIRExprID]
                var callCaptureOffset = 0
                if let signature, let types {
                    // A constructor bridged to an allocating runtime entry
                    // (`Pair`'s `__kk_pair_new`) is called without the allocated-object
                    // argument that an ordinary `<init>` receives, so its value
                    // arguments start at index 0. Using the signature's receiver
                    // unconditionally would shift every parameter by one and box each
                    // argument against its neighbour's declared type.
                    let receiverOffset: Int = {
                        guard signature.receiverType != nil else { return 0 }
                        if let symbol = effectiveCallSymbol, let symbols,
                           symbols.memberExtensionOwnerSymbol(for: symbol) != nil
                        {
                            return 2
                        }
                        if symbols?.symbol(effectiveCallSymbol ?? .invalid)?.kind == .constructor,
                           arguments.count == signature.parameterTypes.count
                        {
                            return 0
                        }
                        return 1
                    }()
                    callCaptureOffset = localFunctionCaptureOffset(
                        callSymbol: effectiveCallSymbol,
                        signature: signature,
                        receiverOffset: receiverOffset,
                        argumentCount: arguments.count,
                        module: module,
                        symbols: symbols
                    )
                    var preservedBoxedArgumentIndices: Set<Int> = []
                    if let callSymbol = effectiveCallSymbol,
                       let receiverIndex = nullableUnderlyingValueClassDefaultStubReceiverIndices[callSymbol],
                       arguments.indices.contains(receiverIndex)
                    {
                        preservedBoxedArgumentIndices.insert(receiverIndex)
                    } else if let callSymbol = effectiveCallSymbol,
                              nullableUnderlyingValueClassConstructors.contains(callSymbol),
                              receiverOffset > 0
                    {
                        let receiverIndex = callCaptureOffset + receiverOffset - 1
                        if arguments.indices.contains(receiverIndex) {
                            preservedBoxedArgumentIndices.insert(receiverIndex)
                        }
                    }
                    boxedArguments = applyArgumentBoxing(
                        arguments: arguments,
                        signature: signature,
                        receiverOffset: receiverOffset,
                        captureOffset: callCaptureOffset,
                        module: module,
                        types: types,
                        symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable,
                        callee: effectiveCallee,
                        interner: ctx.interner,
                        // A recovered `$default` stub is a source-generated
                        // Kotlin function, so its type-parameter slots carry
                        // the same boxed values as any Kotlin-source callee.
                        boxTypeParamArguments: isKotlinSourceCallee(effectiveCallSymbol, symbols: symbols)
                            || recoveredStubSignature,
                        preservedBoxedArgumentIndices: preservedBoxedArgumentIndices,
                        sema: ctx.sema,
                        cache: ctx.nominalDispatchCache,
                        newBody: &newBody,
                        isConstructorCall: symbols?.symbol(effectiveCallSymbol ?? .invalid)?.kind == .constructor
                    )
                } else {
                    boxedArguments = arguments
                }

                // Synthesized delegation and imported bodies can reach this
                // bridge with a Kotlin function value instead of the C callback
                // pair produced by direct member-call lowering. Normalize only
                // the unexpanded shape; already-expanded calls stay intact.
                if runtimeLink == ctx.interner.intern("kk_context_fold"),
                   boxedArguments.count == 3
                {
                    let operation = boxedArguments[2]
                    let fnPtr = emitNonThrowingCall(
                        callee: ctx.interner.intern("kk_function_value_fn_ptr"),
                        arg: operation,
                        resultType: types?.intType,
                        arena: module.arena,
                        into: &newBody
                    )
                    let closureRaw = emitNonThrowingCall(
                        callee: ctx.interner.intern("kk_function_value_closure_raw"),
                        arg: operation,
                        resultType: types?.intType,
                        arena: module.arena,
                        into: &newBody
                    )
                    boxedArguments = [boxedArguments[0], boxedArguments[1], fnPtr, closureRaw]
                }

                // `generateSequence` reaches this private runtime bridge after
                // its generic source wrapper is expanded. The bridge stores the
                // seed in an erased sequence element slot, so a raw primitive or
                // enum ordinal must be boxed here; otherwise enum ordinal zero
                // loses its entry name and prints as `0`.
                let generateSequenceBridgeLink = effectiveCallSymbol.flatMap { symbol in
                    symbols?.externalLinkNameIfKnown(for: symbol)
                }
                if (effectiveCallee == ctx.interner.intern("__kk_sequence_generate")
                    || generateSequenceBridgeLink == "__kk_sequence_generate"),
                   let types,
                   let seed = boxedArguments.first,
                   let seedType = intrinsicArgType(seed, arena: module.arena, types: types)
                {
                    boxedArguments[0] = boxValueForAnySlot(
                        seed,
                        sourceType: seedType,
                        types: types,
                        symbols: symbols,
                        interner: ctx.interner,
                        arena: module.arena,
                        sema: ctx.sema,
                        cache: ctx.nominalDispatchCache,
                        into: &newBody
                    )
                }

                // Inline arithmetic calls (kk_op_add, etc.) have no
                // FunctionSignature so the normal argument-boxing path above
                // leaves them untouched.
                if signature == nil, let types, let result,
                   inlineArithmeticCallees.contains(effectiveCallee)
                {
                    for i in boxedArguments.indices {
                        boxedArguments[i] = unboxBinaryOperandIfNeeded(
                            operand: boxedArguments[i], resultExpr: result,
                            module: module, types: types, symbols: symbols,
                            boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                        )
                    }
                }
                // Unit and enum values may arrive as raw builtins or as erased
                // singleton handles. Compare canonical singleton handles for
                // both representations, including when-branch equality emitted
                // by OperatorLowering. Nullable/platform Unit slots carry the
                // same raw-zero representation (or the null sentinel, which
                // `kk_box_unit` passes through), so they normalize through the
                // same callee (KUU-2957).
                if signature == nil, let types,
                   unitEqualityCallees.contains(effectiveCallee)
                {
                    let argEnumClasses: [SymbolID?] = boxedArguments.map { arg in
                        guard let argType = intrinsicArgType(arg, arena: module.arena, types: types),
                              case let .classType(classType) = types.kind(of: argType),
                              symbols?.symbol(classType.classSymbol)?.kind == .enumClass
                        else {
                            return nil
                        }
                        return classType.classSymbol
                    }
                    for i in boxedArguments.indices {
                        guard let argType = intrinsicArgType(boxedArguments[i], arena: module.arena, types: types)
                        else { continue }
                        switch types.kind(of: argType) {
                        case .unit, .nullableUnit, .platformUnit:
                            guard let boxCallee = boxingCalleeTable.boxCallee(
                                for: types.kind(of: argType), requireNonNull: false
                            )
                            else { continue }
                            boxedArguments[i] = emitNonThrowingCall(
                                callee: boxCallee, arg: boxedArguments[i], resultType: types.anyType,
                                arena: module.arena, into: &newBody
                            )
                        case .classType:
                            // Same-class non-null enum pairs were already
                            // unboxed to raw ordinals upstream, so an
                            // enum-typed operand here faces a nullable,
                            // cross-class, or Any-erased peer and must meet it
                            // as the canonical singleton box: raw ordinals
                            // would alias other enum classes' entries and
                            // could never match an erased handle.
                            // `kk_enum_box_ordinal` normalizes boxed and raw
                            // inputs to the cached entry box and keeps the
                            // null sentinel null (KUU-2957).
                            if let enumClass = argEnumClasses[i],
                               let symbols,
                               let enumSymbol = symbols.symbol(enumClass),
                               enumBoxingHasOrdinalNameHelper(enumSymbol, symbols: symbols, interner: ctx.interner)
                            {
                                let boxedTemp = module.arena.appendTemporary(type: types.anyType)
                                emitEnumOrdinalBoxCall(
                                    ordinal: boxedArguments[i],
                                    classSymbol: enumClass,
                                    result: boxedTemp,
                                    resultType: types.anyType,
                                    types: types,
                                    symbols: symbols,
                                    interner: ctx.interner,
                                    arena: module.arena,
                                    sema: ctx.sema,
                                    cache: ctx.nominalDispatchCache,
                                    into: &newBody
                                )
                                boxedArguments[i] = boxedTemp
                                continue
                            }
                            // A value class is its raw underlying payload
                            // while statically value-class-typed, so an
                            // unboxed operand would reach the equality bridge
                            // indistinguishable from a raw Int/String and
                            // `A("x") == "x"` would compare payloads. Boxed
                            // equality is nominal on the JVM, so box the
                            // operand through the ordinary Any-boundary path
                            // first — the runtime then sees the class's type
                            // tag before any payload unwrapping (KUU-3616).
                            guard let symbols,
                                  case let .classType(classType) = types.kind(of: argType),
                                  classType.nullability == .nonNull,
                                  symbols.symbol(classType.classSymbol)?.flags.contains(.valueType) == true,
                                  let boxCallee = boxingCallee(
                                      argType: argType,
                                      paramType: types.anyType,
                                      callee: effectiveCallee,
                                      types: types,
                                      interner: ctx.interner,
                                      boxingCalleeTable: boxingCalleeTable,
                                      symbols: symbols,
                                      preferStaticPrimitive: true
                                  )
                            else { continue }
                            let boxedValueClass = module.arena.appendTemporary(type: types.anyType)
                            emitBoxCallWithValueClassTag(
                                boxCallee: boxCallee,
                                value: boxedArguments[i],
                                rawSourceKind: types.kind(of: argType),
                                result: boxedValueClass,
                                resultType: types.anyType,
                                types: types,
                                symbols: symbols,
                                interner: ctx.interner,
                                arena: module.arena,
                                sema: ctx.sema,
                                cache: ctx.nominalDispatchCache,
                                into: &newBody
                            )
                            boxedArguments[i] = boxedValueClass
                        default:
                            continue
                        }
                    }
                }
                // Element arguments to membership intrinsics arrive raw even
                // when a signature exists (enum-typed parameters carry
                // ordinals), so this is not gated on `signature == nil`.
                if let types,
                   membershipElementCallees.contains(effectiveCallee)
                {
                    // `x in range` dispatches to `runtimeRangeContains`, which
                    // compares the bare word against first/last — the element
                    // must stay raw there (KUU-3027's scalar boxing would wrap
                    // it into a pointer). `ClosedRange`-typed receivers are the
                    // only ones that take this path.
                    let containerIsRange: Bool = boxedArguments.first.flatMap {
                        intrinsicArgType($0, arena: module.arena, types: types)
                    }.flatMap { containerType -> SymbolID? in
                        guard case let .classType(classType) = types.kind(of: containerType)
                        else { return nil }
                        return classType.classSymbol
                    }.flatMap { symbols?.symbol($0)?.fqName }.map { fqName in
                        fqName.count >= 2
                            && fqName[0] == ctx.interner.intern("kotlin")
                            && fqName[1] == ctx.interner.intern("ranges")
                    } ?? false
                    for i in boxedArguments.indices {
                        guard let argType = intrinsicArgType(
                            boxedArguments[i], arena: module.arena, types: types
                        ) else { continue }
                        switch types.kind(of: argType) {
                        case let .classType(classType):
                            if let symbols,
                               let enumSymbol = symbols.symbol(classType.classSymbol),
                               enumSymbol.kind == .enumClass,
                               enumBoxingHasOrdinalNameHelper(
                                   enumSymbol, symbols: symbols, interner: ctx.interner
                               )
                            {
                                let boxedTemp = module.arena.appendTemporary(type: types.anyType)
                                emitEnumOrdinalBoxCall(
                                    ordinal: boxedArguments[i],
                                    classSymbol: classType.classSymbol,
                                    result: boxedTemp,
                                    resultType: types.anyType,
                                    types: types,
                                    symbols: symbols,
                                    interner: ctx.interner,
                                    arena: module.arena,
                                    sema: ctx.sema,
                                    cache: ctx.nominalDispatchCache,
                                    into: &newBody
                                )
                                boxedArguments[i] = boxedTemp
                                continue
                            }
                            // A value-class probe must carry the same tagged
                            // box the elements were stored as, or
                            // `A(1) in listOf(A(1))` misses on the nominal
                            // tag check (KUU-3616).
                            guard let symbols,
                                  classType.nullability == .nonNull,
                                  symbols.symbol(classType.classSymbol)?.flags.contains(.valueType) == true,
                                  let boxCallee = boxingCallee(
                                      argType: argType,
                                      paramType: types.anyType,
                                      callee: effectiveCallee,
                                      types: types,
                                      interner: ctx.interner,
                                      boxingCalleeTable: boxingCalleeTable,
                                      symbols: symbols,
                                      preferStaticPrimitive: true
                                  )
                            else { continue }
                            let boxedValueClass = module.arena.appendTemporary(type: types.anyType)
                            emitBoxCallWithValueClassTag(
                                boxCallee: boxCallee,
                                value: boxedArguments[i],
                                rawSourceKind: types.kind(of: argType),
                                result: boxedValueClass,
                                resultType: types.anyType,
                                types: types,
                                symbols: symbols,
                                interner: ctx.interner,
                                arena: module.arena,
                                sema: ctx.sema,
                                cache: ctx.nominalDispatchCache,
                                into: &newBody
                            )
                            boxedArguments[i] = boxedValueClass
                        case .primitive(let primitive, .nonNull)
                            where primitive != .double && primitive != .float && !containerIsRange:
                            // A bare integral scalar would alias a stored enum
                            // box by ordinal (KUU-3027). Floating-point words
                            // stay raw — the strict equality path compares
                            // boxed `Double`/`Float` against raw bit patterns,
                            // which boxing here would defeat.
                            guard i > 0,
                                  let boxCallee = boxCalleeForPrimitive(
                                      types.kind(of: argType),
                                      boxingCalleeTable: boxingCalleeTable,
                                      preferStaticPrimitive: true
                                  )
                            else { continue }
                            let boxedTemp = module.arena.appendTemporary(type: types.anyType)
                            emitBoxCallWithValueClassTag(
                                boxCallee: boxCallee,
                                value: boxedArguments[i],
                                rawSourceKind: types.kind(of: argType),
                                result: boxedTemp,
                                resultType: types.anyType,
                                types: types,
                                symbols: symbols,
                                interner: ctx.interner,
                                arena: module.arena,
                                sema: ctx.sema,
                                cache: ctx.nominalDispatchCache,
                                into: &newBody
                            )
                            boxedArguments[i] = boxedTemp
                        default:
                            continue
                        }
                    }
                }
                // The result is Boolean so the arithmetic path above cannot
                // determine the operand's primitive type from the result; use
                // each operand's own declared type instead.
                // When one operand has no type info (e.g. the result of x+0 whose
                // Sema type was not recorded), collect a hint from a sibling operand
                // that does have type info and forward it so the unboxing can still
                // emit the correct kk_unbox_* call.
                if signature == nil, let types,
                   inlineComparisonCallees.contains(effectiveCallee)
                {
                    var primitiveHint: TypeKind?
                    for operand in boxedArguments {
                        if let opType = intrinsicArgType(operand, arena: module.arena, types: types) {
                            let primitiveType = symbols.flatMap {
                                resolvePrimitiveArithmeticUpperBound(
                                    of: opType, types: types, symbols: $0
                                )
                            } ?? opType
                            let opKind = resolveValueClassKind(
                                types.kind(of: primitiveType), types: types, symbols: symbols
                            )
                            if case .primitive(_, .nonNull) = opKind {
                                primitiveHint = opKind
                                break
                            }
                        }
                    }
                    for i in boxedArguments.indices {
                        boxedArguments[i] = unboxOperandToOwnType(
                            boxedArguments[i],
                            hint: primitiveHint,
                            module: module, types: types, symbols: symbols,
                            boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                        )
                    }
                }
                // See typeCheckValueCallees above. Enum values resolve to Int for
                // their unboxed representation, but must retain their nominal
                // class ID when boxed so nominal and interface checks can
                // recognize them.
                if signature == nil, let types,
                   typeCheckValueCallees.contains(effectiveCallee),
                   let firstArg = boxedArguments.first
                {
                    let argType = intrinsicArgType(firstArg, arena: module.arena, types: types)
                    let rawArgKind = argType.map { types.kind(of: $0) }
                    let argKind = rawArgKind.map {
                        resolveValueClassKind($0, types: types, symbols: symbols)
                    }
                    if let argKind,
                       let boxCallee = boxCalleeForPrimitive(
                           argKind,
                           boxingCalleeTable: boxingCalleeTable,
                           preferStaticPrimitive: true
                       )
                    {
                        let boxedResult = module.arena.appendTemporary(type: types.anyType)
                        emitBoxCallWithValueClassTag(
                            boxCallee: boxCallee,
                            value: firstArg,
                            rawSourceKind: rawArgKind ?? argKind,
                            result: boxedResult,
                            resultType: types.anyType,
                            types: types,
                            symbols: symbols,
                            interner: ctx.interner,
                            arena: module.arena,
                            sema: ctx.sema,
                            cache: ctx.nominalDispatchCache,
                            into: &newBody
                        )
                        boxedArguments[0] = boxedResult
                    } else if let rawArgKind,
                       case let .classType(argClass) = rawArgKind,
                       argClass.nullability == .nonNull,
                       symbols?.symbol(argClass.classSymbol)?.flags.contains(.valueType) == true
                    {
                        // No primitive box exists for a value class whose
                        // underlying type is itself an object — a nullable or
                        // reference payload (KUU-3115, KUU-3616). `kk_op_cast`
                        // returns its operand as the cast result, so the
                        // `.any`-typed result must carry the nominal
                        // `kk_value_class_box` wrapper: otherwise `r as Any`
                        // is the bare payload handle and compares equal to it.
                        boxedArguments[0] = boxValueForAnySlot(
                            firstArg,
                            sourceType: argType ?? types.anyType,
                            types: types,
                            symbols: symbols,
                            interner: ctx.interner,
                            arena: module.arena,
                            resultType: types.anyType,
                            requireNonNull: true,
                            boxingCalleeTable: boxingCalleeTable,
                            sema: ctx.sema,
                            cache: ctx.nominalDispatchCache,
                            into: &newBody
                        )
                    }
                }

                let resolvedUnbox = resolveUnboxForCall(
                    callSymbol: effectiveCallSymbol,
                    callee: effectiveCallee,
                    arguments: arguments,
                    captureOffset: callCaptureOffset,
                    result: result,
                    signatureByName: signatureByName,
                    module: module,
                    types: types,
                    symbols: symbols,
                    boxingCalleeTable: boxingCalleeTable,
                    nullableGenericResults: &nullableGenericResults,
                    boxedReturnCallees: unboxSkipCallees
                )

                // Fallback: collection element accessors may return a boxed primitive.
                // resolveUnboxForCall cannot handle these because they have no
                // FunctionSignature entry. Unbox using the KIR result type as the target.
                var effectiveUnbox: (InternedString, TypeID)? = resolvedUnbox
                let needsErasedResultUnbox =
                    erasedValueAccessorCallees.contains(effectiveCallee)
                    || (effectiveCallee == genericArrayGetCallee
                        && isGenericArrayReceiver(
                            boxedArguments.first,
                            module: module,
                            types: types,
                            symbols: symbols,
                            arrayName: arrayClassName
                        ))
                    || boxedBooleanReturnCallees.contains(effectiveCallee)
                if effectiveUnbox == nil,
                   needsErasedResultUnbox,
                   let result, let types,
                   let resultType = module.arena.exprType(result)
                {
                    let resultKind = resolveValueClassKind(
                        types.kind(of: resultType), types: types, symbols: symbols
                    )
                    // Strings stored in generic arrays/collections are represented as
                    // raw object handles at runtime; the backend already bridges that
                    // raw handle to a flat string aggregate when the result type is
                    // String. Inserting an explicit kk_string_to_flat here would
                    // unbox a flat aggregate as if it were a raw handle, causing a
                    // double conversion crash.
                    if case .stringStruct = resultKind {
                        // Leave string unboxing to the backend bridge.
                    } else if let unboxCallee = unboxingCallee(
                        sourceKind: TypeKind.any(.nullable), targetKind: resultKind,
                        boxingCalleeTable: boxingCalleeTable, types: types, symbols: symbols,
                        preferStaticPrimitive: true
                    ) {
                        effectiveUnbox = (unboxCallee, resultType)
                    }
                }

                let valueClassResultConversion = resolveValueClassResultConversion(
                    callSymbol: effectiveCallSymbol,
                    callee: effectiveCallee,
                    result: result,
                    signatureByName: signatureByName,
                    module: module,
                    types: types,
                    symbols: symbols,
                    rawValueReturningCallees: typeCheckValueCallees,
                    boxedReturnCallees: unboxSkipCallees
                )

                if let valueClassResultConversion, let result, let types, let symbols {
                    let tempResult = module.arena.appendTemporary(
                        type: valueClassResultConversion.returnType
                    )
                    newBody.append(.call(
                        symbol: effectiveCallSymbol,
                        callee: effectiveCallee,
                        arguments: boxedArguments,
                        result: tempResult,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall,
                        qualifiedSuperType: qualifiedSuperType
                    ))
                    if thrownResult != nil {
                        let nextIdx = idx + 1
                        if nextIdx < function.body.count,
                           case .jumpIfNotNull = function.body[nextIdx]
                        {
                            newBody.append(function.body[nextIdx])
                            idx += 1
                        }
                    }
                    appendValueClassResultConversion(
                        conversion: valueClassResultConversion,
                        from: tempResult,
                        to: result,
                        module: module,
                        types: types,
                        symbols: symbols,
                        interner: ctx.interner,
                        into: &newBody
                    )
                } else if let (resolvedUnboxCallee, resolvedReturnType) = effectiveUnbox, let result {
                    let tempResult = module.arena.appendTemporary(type: resolvedReturnType
                    )
                    newBody.append(.call(
                        symbol: effectiveCallSymbol,
                        callee: effectiveCallee,
                        arguments: boxedArguments,
                        result: tempResult,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall,
                        qualifiedSuperType: qualifiedSuperType
                    ))
                    if thrownResult != nil {
                        let nextIdx = idx + 1
                        if nextIdx < function.body.count,
                           case .jumpIfNotNull = function.body[nextIdx]
                        {
                            newBody.append(function.body[nextIdx])
                            idx += 1
                        }
                    }
                    emitNonThrowingCall(
                        callee: resolvedUnboxCallee,
                        arg: tempResult,
                        result: result,
                        into: &newBody
                    )
                } else {
                    newBody.append(.call(
                        symbol: effectiveCallSymbol,
                        callee: effectiveCallee,
                        arguments: boxedArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall,
                        qualifiedSuperType: qualifiedSuperType
                    ))
                }
                idx += 1
            }

            updated.replaceBody(newBody)
            return updated
        }
        module.arena.transformFunctions(transformFunction)
        module.recordLowering(Self.name)
    }

    private func rewriteReturnValueBoxingOrUnboxing(
        value: KIRExprID,
        functionReturnKind: TypeKind?,
        returnType: TypeID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        interner: StringInterner,
        boxingCalleeTable: BoxingCalleeTable,
        sema: SemaModule?,
        cache: KIRNominalDispatchCache?
    ) -> [KIRInstruction]? {
        guard let functionReturnKind,
              let valueType = intrinsicArgType(value, arena: module.arena, types: types)
        else {
            return nil
        }
        let rawValueKind = types.kind(of: valueType)
        let resolvedValueKind = resolveValueClassKind(rawValueKind, types: types, symbols: symbols)
        // A nullable-underlying value class crossing the `V`/`V?`/reference
        // boundary in either direction uses the nominal box helpers rather
        // than a `kk_box_*`/`kk_unbox_*` callee (KUU-3115).
        if valueType != returnType, let symbols {
            let rawReturnKind = types.kind(of: returnType)
            if let vcSymbol = nullableUnderlyingValueClassSymbol(
                of: rawValueKind, types: types, symbols: symbols
            ), valueClassBoxTargetIsBoxed(rawReturnKind, symbols: symbols) {
                var instructions: [KIRInstruction] = []
                let boxedResult = module.arena.appendTemporary(type: returnType)
                emitValueClassBoxCall(
                    value: value, classSymbol: vcSymbol, result: boxedResult,
                    resultType: returnType, types: types, symbols: symbols,
                    interner: interner, arena: module.arena, into: &instructions
                )
                instructions.append(.returnValue(boxedResult))
                return instructions
            }
            // Reference-backed value classes take the same wrapper when the
            // declared return slot is a boxed target — `fun f(): Any = r`
            // must not leak the payload handle as the Any value (KUU-3616).
            if let vcSymbol = referenceBackedValueClassSymbol(
                of: rawValueKind, types: types, symbols: symbols
            ), valueClassBoxTargetIsBoxed(rawReturnKind, symbols: symbols) {
                var instructions: [KIRInstruction] = []
                let boxedResult = module.arena.appendTemporary(type: returnType)
                emitValueClassBoxCall(
                    value: value, classSymbol: vcSymbol, result: boxedResult,
                    resultType: returnType, types: types, symbols: symbols,
                    interner: interner, arena: module.arena, into: &instructions
                )
                instructions.append(.returnValue(boxedResult))
                return instructions
            }
            if let vcSymbol = nullableUnderlyingValueClassSymbol(
                of: rawReturnKind, types: types, symbols: symbols
            ), valueClassUnboxSourceIsBoxed(rawValueKind, symbols: symbols) {
                var instructions: [KIRInstruction] = []
                let unboxed = module.arena.appendTemporary(type: returnType)
                emitValueClassUnboxCall(
                    value: value, classSymbol: vcSymbol, result: unboxed,
                    resultType: returnType, types: types, symbols: symbols,
                    interner: interner, arena: module.arena, into: &instructions
                )
                instructions.append(.returnValue(unboxed))
                return instructions
            }
            // `Any`/type-parameter/`V?` slots may hold a reference-backed
            // value-class box; an `R` return slot expects the payload, so
            // unwrap the nominal box the same way copies do — the helper
            // passes non-matching values through unchanged (KUU-3616).
            if let vcSymbol = referenceBackedValueClassSymbol(
                of: rawReturnKind, types: types, symbols: symbols
            ), valueClassUnboxSourceIsBoxed(rawValueKind, symbols: symbols) {
                var instructions: [KIRInstruction] = []
                let unboxed = module.arena.appendTemporary(type: returnType)
                emitValueClassUnboxCall(
                    value: value, classSymbol: vcSymbol, result: unboxed,
                    resultType: returnType, types: types, symbols: symbols,
                    interner: interner, arena: module.arena, into: &instructions
                )
                instructions.append(.returnValue(unboxed))
                return instructions
            }
        }
        // A smart-cast name can still refer to its erased/nullable storage.
        // Explicit returns have no copy instruction to normalize that boundary.
        if valueType != returnType,
           case .primitive(_, .nonNull) = functionReturnKind,
           let unboxCallee = unboxingCallee(
               sourceKind: rawValueKind, targetKind: functionReturnKind,
               boxingCalleeTable: boxingCalleeTable, types: types, symbols: symbols,
               preferStaticPrimitive: true
           )
        {
            var instructions: [KIRInstruction] = []
            let unboxed = emitNonThrowingCall(
                callee: unboxCallee, arg: value, resultType: returnType,
                arena: module.arena, into: &instructions
            )
            instructions.append(.returnValue(unboxed))
            return instructions
        }
        // A non-null primitive returned from a `P?`-typed function must be
        // boxed — not passed through verbatim — because a `P?` slot holds
        // box-or-sentinel and a raw sentinel-equal scalar (Long.MIN_VALUE,
        // ULong 2^63, -0.0) would read as `null` at every call site (KUU-854).
        guard isAnyOrNullableAny(functionReturnKind)
            || isNonValueClassReference(functionReturnKind, symbols: symbols)
            || needsBoxingForCopy(sourceKind: resolvedValueKind, targetKind: functionReturnKind),
              let boxCallee = boxCalleeForPrimitive(
                  resolvedValueKind,
                  boxingCalleeTable: boxingCalleeTable,
                  preferStaticPrimitive: true
              )
        else {
            return nil
        }
        var instructions: [KIRInstruction] = []
        let boxedResult = module.arena.appendTemporary(type: returnType)
        emitBoxCallWithValueClassTag(
            boxCallee: boxCallee,
            value: value,
            rawSourceKind: rawValueKind,
            result: boxedResult,
            resultType: returnType,
            types: types,
            symbols: symbols,
            interner: interner,
            arena: module.arena,
            sema: sema,
            cache: cache,
            into: &instructions
        )
        instructions.append(.returnValue(boxedResult))
        return instructions
    }

    private func rewriteCopyBoxingOrUnboxing(
        from: KIRExprID, to: KIRExprID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        interner: StringInterner,
        boxingCalleeTable: BoxingCalleeTable,
        sema: SemaModule?,
        cache: KIRNominalDispatchCache?
    ) -> [KIRInstruction]? {
        guard let fromType = intrinsicArgType(from, arena: module.arena, types: types),
              let toType = module.arena.exprType(to)
        else {
            return nil
        }
        let rawFromKind = types.kind(of: fromType)
        let fromKind = resolveValueClassKind(rawFromKind, types: types, symbols: symbols)
        let rawToKind = types.kind(of: toType)
        let toKind = resolveValueClassKind(rawToKind, types: types, symbols: symbols)
        // A non-null enum local is stored as its raw ordinal. Keep copies between
        // values of the same enum class verbatim; otherwise resolving both sides
        // to Int below would add an unnecessary kk_unbox_int and corrupt the
        // ordinal before a later .name/.ordinal read.
        let isDirectNonNullEnumCopy: Bool = {
            guard case let .classType(sourceClass) = rawFromKind,
                  case let .classType(targetClass) = rawToKind,
                  sourceClass.nullability == .nonNull,
                  targetClass.nullability == .nonNull,
                  sourceClass.classSymbol == targetClass.classSymbol,
                  let symbols,
                  let sym = symbols.symbol(targetClass.classSymbol)
            else {
                return false
            }
            return sym.kind == .enumClass
        }()
        // A nullable-underlying value class keeps payload-or-box
        // representations on opposite sides of the `V`/`V?` boundary —
        // `V` -> `V?`/`Any`/other reference slots box through
        // `kk_value_class_box`, while `V?`/reference -> `V` unwraps through
        // `kk_value_class_unbox` (KUU-3115).
        if let symbols,
           let vcSymbol = nullableUnderlyingValueClassSymbol(
               of: rawFromKind, types: types, symbols: symbols
           ),
           valueClassBoxTargetIsBoxed(rawToKind, symbols: symbols)
        {
            var instructions: [KIRInstruction] = []
            emitValueClassBoxCall(
                value: from, classSymbol: vcSymbol, result: to,
                resultType: toType, types: types, symbols: symbols,
                interner: interner, arena: module.arena, into: &instructions
            )
            return instructions
        }
        // A reference-backed value class needs the same nominal wrapper at a
        // copy boundary: `V` is the bare payload object, so `r as Any` would
        // otherwise stash the shared `c` handle into the Any slot and compare
        // equal to it — boxed equality is nominal on the JVM (KUU-3616).
        if let symbols,
           let vcSymbol = referenceBackedValueClassSymbol(
               of: rawFromKind, types: types, symbols: symbols
           ),
           valueClassBoxTargetIsBoxed(rawToKind, symbols: symbols)
        {
            var instructions: [KIRInstruction] = []
            emitValueClassBoxCall(
                value: from, classSymbol: vcSymbol, result: to,
                resultType: toType, types: types, symbols: symbols,
                interner: interner, arena: module.arena, into: &instructions
            )
            return instructions
        }
        // Reference-backed boxes unwrap the same way: an `Any`/`T` slot or a
        // `V?` slot can carry the wrapper, and `kk_value_class_unbox` passes
        // payloads and foreign boxes through unchanged (KUU-3616).
        if let symbols,
           let vcSymbol = referenceBackedValueClassSymbol(of: rawToKind, types: types, symbols: symbols),
           valueClassUnboxSourceIsBoxed(rawFromKind, symbols: symbols)
        {
            var instructions: [KIRInstruction] = []
            emitValueClassUnboxCall(
                value: from, classSymbol: vcSymbol, result: to,
                resultType: toType, types: types, symbols: symbols,
                interner: interner, arena: module.arena, into: &instructions
            )
            return instructions
        }
        if let symbols,
           let vcSymbol = nullableUnderlyingValueClassSymbol(
               of: rawToKind, types: types, symbols: symbols
           ),
           valueClassUnboxSourceIsBoxed(rawFromKind, symbols: symbols)
        {
            var instructions: [KIRInstruction] = []
            emitValueClassUnboxCall(
                value: from, classSymbol: vcSymbol, result: to,
                resultType: toType, types: types, symbols: symbols,
                interner: interner, arena: module.arena, into: &instructions
            )
            return instructions
        }
        if !isDirectNonNullEnumCopy,
           isAnyOrNullableAny(toKind) || needsBoxingForCopy(sourceKind: fromKind, targetKind: toKind)
            || isNonValueClassReference(rawToKind, symbols: symbols),
            let boxCallee = boxCalleeForPrimitive(
                fromKind,
                boxingCalleeTable: boxingCalleeTable,
                preferStaticPrimitive: true
            )
        {
            var instructions: [KIRInstruction] = []
            emitBoxCallWithValueClassTag(
                boxCallee: boxCallee,
                value: from,
                rawSourceKind: rawFromKind,
                result: to,
                resultType: toType,
                types: types,
                symbols: symbols,
                interner: interner,
                arena: module.arena,
                sema: sema,
                cache: cache,
                into: &instructions
            )
            return instructions
        }
        if !isDirectNonNullEnumCopy,
           needsUnboxing(sourceKind: fromKind, targetKind: toKind, symbols: symbols),
           let unboxCallee = unboxingCallee(
               sourceKind: fromKind, targetKind: toKind,
               boxingCalleeTable: boxingCalleeTable,
               types: types, symbols: symbols,
               preferStaticPrimitive: true
           )
        {
            return [.call(callee: unboxCallee, arguments: [from],
                         result: to, canThrow: false)]
        }
        return nil
    }

    func localFunctionCaptureOffset(
        callSymbol: SymbolID?,
        signature: FunctionSignature,
        receiverOffset: Int,
        argumentCount: Int,
        module: KIRModule,
        symbols: SymbolTable?
    ) -> Int {
        guard let callSymbol,
              let sym = symbols?.symbol(callSymbol),
              sym.flags.contains(.localFunction)
        else {
            return 0
        }
        let expectedCount = receiverOffset + signature.contextParameterTypes.count + signature.parameterTypes.count
        if let function = module.arena.function(for: callSymbol) {
            return max(0, function.params.count - expectedCount)
        }
        return max(0, argumentCount - expectedCount)
    }
}
