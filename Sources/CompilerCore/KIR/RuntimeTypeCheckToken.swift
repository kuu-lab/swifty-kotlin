
enum RuntimeTypeCategory {
    case unknown
    case any
    case string
    case int
    case boolean
    case null
    case nominal(SymbolID)
    case uint
    case ulong
    case ubyte
    case ushort
    case byte
    case short
    case long
    case double
    case float
    case char
    case unit
    case function(arity: Int, isSuspend: Bool)

    var base: Int64 {
        switch self {
        case .unknown:  RuntimeTypeCheckToken.unknownBase
        case .any:      RuntimeTypeCheckToken.anyBase
        case .string:   RuntimeTypeCheckToken.stringBase
        case .int:      RuntimeTypeCheckToken.intBase
        case .boolean:  RuntimeTypeCheckToken.booleanBase
        case .null:     RuntimeTypeCheckToken.nullBase
        case .nominal:  RuntimeTypeCheckToken.nominalBase
        case .uint:     RuntimeTypeCheckToken.uintBase
        case .ulong:    RuntimeTypeCheckToken.ulongBase
        case .ubyte:    RuntimeTypeCheckToken.ubyteBase
        case .ushort:   RuntimeTypeCheckToken.ushortBase
        case .byte:     RuntimeTypeCheckToken.byteBase
        case .short:    RuntimeTypeCheckToken.shortBase
        case .long:     RuntimeTypeCheckToken.longBase
        case .double:   RuntimeTypeCheckToken.doubleBase
        case .float:    RuntimeTypeCheckToken.floatBase
        case .char:     RuntimeTypeCheckToken.charBase
        case .unit:     RuntimeTypeCheckToken.unitBase
        case .function: RuntimeTypeCheckToken.functionBase
        }
    }

    /// The Kotlin simple name for this category, or `nil` for unknown/nominal
    /// (nominal names require symbol resolution).
    var simpleName: String? {
        switch self {
        case .any:      "Any"
        case .null:     "Nothing"
        case .string:   "String"
        case .int:      PrimitiveType.int.kotlinName
        case .boolean:  PrimitiveType.boolean.kotlinName
        case .uint:     PrimitiveType.uint.kotlinName
        case .ulong:    PrimitiveType.ulong.kotlinName
        case .ubyte:    PrimitiveType.ubyte.kotlinName
        case .ushort:   PrimitiveType.ushort.kotlinName
        case .byte:     PrimitiveType.byte.kotlinName
        case .short:    PrimitiveType.short.kotlinName
        case .long:     PrimitiveType.long.kotlinName
        case .double:   PrimitiveType.double.kotlinName
        case .float:    PrimitiveType.float.kotlinName
        case .char:     PrimitiveType.char.kotlinName
        case .unit:     "Unit"
        // Function names come from the token payload at runtime, so the
        // compiler never has to supply a name hint for them.
        case .unknown, .nominal, .function:  nil
        }
    }
}

struct RuntimeTypeDescriptor {
    let category: RuntimeTypeCategory
    let nullable: Bool
}

/// Keep these values in sync with Runtime's `kk_op_is` implementation.
enum RuntimeTypeCheckToken {
    static let unknownBase: Int64 = 0
    static let anyBase: Int64 = 1
    static let stringBase: Int64 = 2
    static let intBase: Int64 = 3
    static let booleanBase: Int64 = 4
    static let nullBase: Int64 = 5
    static let nominalBase: Int64 = 6
    static let uintBase: Int64 = 7
    static let ulongBase: Int64 = 8
    static let ubyteBase: Int64 = 9
    static let ushortBase: Int64 = 10
    static let byteBase: Int64 = 16
    static let shortBase: Int64 = 17
    static let longBase: Int64 = 11
    static let doubleBase: Int64 = 12
    static let floatBase: Int64 = 13
    static let charBase: Int64 = 14
    static let unitBase: Int64 = 15
    // Function-type token base. Payload packs the FunctionN arity in
    // bits 0-7 and the suspend flag in bit 8.
    static let functionBase: Int64 = 18

    static let baseMask: Int64 = 0xFF
    static let nullableFlag: Int64 = 1 << 8
    static let payloadShift: Int64 = 9
    static let payloadMask: Int64 = (1 << 55) - 1

    static func encode(base: Int64, nullable: Bool, payload: Int64 = 0) -> Int64 {
        var token = base & baseMask
        if nullable {
            token |= nullableFlag
        }
        let normalizedPayload = payload & payloadMask
        token |= (normalizedPayload << payloadShift)
        return token
    }

    static func emitNullableToken(
        _ token: KIRExprID,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Tokens can contain a nominal ID in their upper bits. Use a Long
        // result so IntegerNarrowingPass does not truncate the bitwise OR.
        let tokenStorageType = sema.types.longType
        let flag = arena.appendExpr(.intLiteral(nullableFlag), type: tokenStorageType)
        instructions.append(.constValue(result: flag, value: .intLiteral(nullableFlag)))
        let result = arena.appendTemporary(type: tokenStorageType)
        instructions.append(.call(
            callee: interner.intern("kk_bitwise_or"), arguments: [token, flag],
            result: result, canThrow: false
        ))
        return result
    }

    static func classify(type: TypeID, sema: SemaModule) -> RuntimeTypeDescriptor {
        let nullable = sema.types.nullability(of: type) == .nullable
        let category: RuntimeTypeCategory
        switch sema.types.kind(of: type) {
        case .any:                      category = .any
        case .stringStruct:             category = .string
        case .primitive(.int, _):       category = .int
        case .primitive(.uint, _):      category = .uint
        case .primitive(.ulong, _):     category = .ulong
        case .primitive(.ubyte, _):     category = .ubyte
        case .primitive(.ushort, _):    category = .ushort
        case .primitive(.byte, _):      category = .byte
        case .primitive(.short, _):      category = .short
        case .primitive(.boolean, _):   category = .boolean
        // REFL-002: Classify additional primitive types so ::class tokens
        // carry distinct base values instead of falling through to .unknown.
        case .primitive(.long, _):      category = .long
        case .primitive(.double, _):    category = .double
        case .primitive(.float, _):     category = .float
        case .primitive(.char, _):      category = .char
        case .unit, .nullableUnit, .platformUnit:      category = .unit
        case .nothing:                  category = nullable ? .null : .unknown
        case let .functionType(functionType):
            // KUU-1084: `() -> Unit`, `Int.(String) -> Long`, suspend and
            // context-receiver variants all normalize to `kotlin.FunctionN`
            // (or SuspendFunctionN) classifiers, where N counts every
            // context receiver, extension receiver and value parameter.
            let receiverCount = functionType.receiver == nil ? 0 : 1
            category = .function(
                arity: functionType.contextReceivers.count
                    + receiverCount
                    + functionType.params.count,
                isSuspend: functionType.isSuspend
            )
        case let .classType(classType):
            // Value classes (boxed or not) are checked by nominal identity,
            // not by their underlying representation: kk_tag_value_class_box
            // (see emitBoxCallWithValueClassTag) tags a value class's boxed
            // primitive with its own stable nominal type ID at every
            // reference-type boundary, so `is`/`as`/`KClass.isInstance`
            // against the value class name can match that tag directly —
            // the same way a plain nominal class/interface check does.
            if let shape = sema.types.nominalFunctionInterfaceShape(of: classType.classSymbol) {
                category = .function(arity: shape.arity, isSuspend: shape.isSuspend)
            } else {
                category = .nominal(classType.classSymbol)
            }
        case .kClassType:
            // Concrete KClass<T> and nominal KClass<*> targets share the
            // erased reflection interface identity, not T's type token.
            if let symbol = sema.types.kClassInterfaceSymbol {
                category = .nominal(symbol)
            } else {
                category = .unknown
            }
        default:                        category = .unknown
        }
        return RuntimeTypeDescriptor(category: category, nullable: nullable)
    }

    static func encodeBuiltinTypeName(
        _ name: InternedString,
        nullable: Bool,
        builtinNames: BuiltinTypeNames
    ) -> Int64? {
        switch name {
        case builtinNames.any:
            encode(base: anyBase, nullable: nullable)
        case builtinNames.string:
            encode(base: stringBase, nullable: nullable)
        case builtinNames.int:
            encode(base: intBase, nullable: nullable)
        case builtinNames.uint:
            encode(base: uintBase, nullable: nullable)
        case builtinNames.ulong:
            encode(base: ulongBase, nullable: nullable)
        case builtinNames.ubyte:
            encode(base: ubyteBase, nullable: nullable)
        case builtinNames.ushort:
            encode(base: ushortBase, nullable: nullable)
        case builtinNames.byte:
            encode(base: byteBase, nullable: nullable)
        case builtinNames.short:
            encode(base: shortBase, nullable: nullable)
        case builtinNames.boolean:
            encode(base: booleanBase, nullable: nullable)
        case builtinNames.long:
            encode(base: longBase, nullable: nullable)
        case builtinNames.double:
            encode(base: doubleBase, nullable: nullable)
        case builtinNames.float:
            encode(base: floatBase, nullable: nullable)
        case builtinNames.char:
            encode(base: charBase, nullable: nullable)
        case builtinNames.unit:
            encode(base: unitBase, nullable: nullable)
        case builtinNames.nothing:
            nullable ? nullBase : unknownBase
        default:
            nil
        }
    }

    static func encode(type: TypeID, sema: SemaModule, interner: StringInterner) -> Int64 {
        let descriptor = classify(type: type, sema: sema)
        switch descriptor.category {
        case let .nominal(symbolID):
            if let builtinToken = encodeBuiltinDisguisedNominal(
                symbolID, nullable: descriptor.nullable, sema: sema, interner: interner
            ) {
                return builtinToken
            }
            let nominalTypeID = stableNominalTypeID(symbol: symbolID, sema: sema, interner: interner)
            return encode(base: descriptor.category.base, nullable: descriptor.nullable, payload: nominalTypeID)
        case let .function(arity, isSuspend):
            let payload = Int64(arity) | (isSuspend ? 0x100 : 0)
            return encode(base: functionBase, nullable: descriptor.nullable, payload: payload)
        case .null:
            return nullBase
        default:
            return encode(base: descriptor.category.base, nullable: descriptor.nullable)
        }
    }

    /// Some builtin types (`String`, `Char`, `Any`, …) additionally have a
    /// synthetic `.class`-kind symbol registered under `kotlin.<Name>` purely
    /// to host member declarations (see `HeaderHelpers.ensureClassSymbol`,
    /// e.g. String's `CharSequence` conformance or Char's companion helpers).
    /// `T::class` for these names resolves `classRefTargetType` to that
    /// class-symbol-wrapped `.classType` representation — `inferClassRefExpr`
    /// finds the synthetic class symbol via scope lookup before it ever
    /// reaches the builtin-name fallback — and `javaClassTypeArgument` relies
    /// on exactly this shape to recover the builtin for `.java`/`.js`/
    /// `.javaClass`. `classify(type:sema:)` reports it as an ordinary
    /// `.nominal` type indistinguishable from a user-defined class, though,
    /// so left unhandled here, the encoded token would use `nominalBase` with
    /// a class-hash payload instead of the dedicated primitive base — causing
    /// `String::class.isInstance(...)` / `.cast(...)` to diverge from the
    /// `stringBase` token that an ordinary `is String` check produces for the
    /// same conceptual type. Detect the disguise and encode via the
    /// canonical builtin base instead.
    private static func encodeBuiltinDisguisedNominal(
        _ symbolID: SymbolID,
        nullable: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int64? {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.fqName.count == 2,
              symbol.fqName.first == interner.intern("kotlin")
        else {
            return nil
        }
        let builtinNames = BuiltinTypeNames(interner: interner)
        return encodeBuiltinTypeName(symbol.name, nullable: nullable, builtinNames: builtinNames)
    }

    static func simpleName(of type: TypeID, sema: SemaModule, interner: StringInterner) -> String? {
        let descriptor = classify(type: type, sema: sema)
        if let name = descriptor.category.simpleName {
            return name
        }
        switch sema.types.kind(of: type) {
        case .nothing:
            return "Void"
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol) else {
                return nil
            }
            if symbol.fqName == [interner.intern("kotlin"), interner.intern("Nothing")] {
                return "Void"
            }
            return interner.resolve(symbol.name)
        default:
            return nil
        }
    }

    static func qualifiedName(of type: TypeID, sema: SemaModule, interner: StringInterner) -> String? {
        let descriptor = classify(type: type, sema: sema)
        if let name = descriptor.category.simpleName {
            return "kotlin." + name
        }
        switch descriptor.category {
        case let .nominal(symbolID):
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            if fqName == "kotlin.Nothing" {
                return "java.lang.Void"
            }
            return fqName.isEmpty ? nil : fqName
        case .unknown:
            if case .nothing = sema.types.kind(of: type) {
                return "java.lang.Void"
            }
            return nil
        // Function types render their FunctionN classifier from the token
        // payload at runtime; no source-level hint is needed.
        default:
            return nil
        }
    }

    static func stableNominalTypeID(symbol: SymbolID, sema: SemaModule, interner: StringInterner) -> Int64 {
        stableNominalTypeID(symbol: symbol, symbols: sema.symbols, interner: interner)
    }

    /// Same computation as the `sema:`-based overload, for lowering passes
    /// (e.g. ABILoweringPass) that only have a `SymbolTable` in scope. Keep
    /// the hash formula identical to Runtime's `runtimeStableNominalTypeID`
    /// so a value class's box-time tag (kk_tag_value_class_box) always
    /// matches its check-time payload (kk_op_is).
    static func stableNominalTypeID(symbol: SymbolID, symbols: SymbolTable, interner: StringInterner) -> Int64 {
        guard let semanticSymbol = symbols.symbol(symbol) else {
            return 0
        }
        let fqName = semanticSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        guard !fqName.isEmpty else {
            return 0
        }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in fqName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        let payload = Int64(bitPattern: hash) & payloadMask
        return payload == 0 ? 1 : payload
    }
}

/// The runtime erasure an unchecked/erased boundary can verify against:
/// a type parameter's first upper bound, resolved transitively when bounds
/// reference other type parameters, or the type itself when it already
/// carries a runtime classifier. Kotlin/JVM checkcasts `as T` against
/// exactly this erasure — `R : C, I1, I2` checks `C` and leaves the rest
/// unchecked. Returns nil when there is no bound or the bound encodes no
/// runtime classifier (`.any`/`.unknown`), where only the null contract
/// is observable.
func kirCheckableCastErasure(of type: TypeID, sema: SemaModule) -> TypeID? {
    var visited: Set<SymbolID> = []
    var current = type
    while case let .typeParam(parameter) = sema.types.kind(of: current) {
        guard visited.insert(parameter.symbol).inserted,
              let bound = sema.symbols.typeParameterUpperBounds(for: parameter.symbol).first
        else {
            return nil
        }
        // A nullable type parameter remains nullable when erased to its bound.
        current = parameter.nullability == .nullable ? sema.types.makeNullable(bound) : bound
    }
    switch RuntimeTypeCheckToken.classify(type: current, sema: sema).category {
    case .unknown, .any:
        return nil
    default:
        return current
    }
}

/// The type parameter inside a definitely-non-null `T & Any` intersection,
/// or nil for every other shape.
func kirDefinitelyNotNullTypeParameter(of type: TypeID, sema: SemaModule) -> TypeID? {
    guard case let .intersection(parts) = sema.types.kind(of: type),
          parts.count == 2,
          parts.contains(where: { sema.types.kind(of: $0) == .any(.nonNull) }),
          let typeParameter = parts.first(where: {
              if case .typeParam = sema.types.kind(of: $0) { return true }
              return false
          })
    else {
        return nil
    }
    return typeParameter
}

/// Whether a declared member type still travels through the erased ABI: a
/// non-reified type parameter, or its definitely-non-null `T & Any` shape.
/// Reified parameters and concrete classifiers keep their real
/// representation and never need an erased-boundary checkcast.
func kirIsNonReifiedErasedABIType(_ type: TypeID, sema: SemaModule) -> Bool {
    if let typeParameterType = kirDefinitelyNotNullTypeParameter(of: type, sema: sema) {
        return kirIsNonReifiedErasedABIType(typeParameterType, sema: sema)
    }
    guard case let .typeParam(parameter) = sema.types.kind(of: type),
          let symbol = sema.symbols.symbol(parameter.symbol)
    else {
        return false
    }
    return !symbol.flags.contains(.reifiedTypeParameter)
}

/// Whether `kk_op_cast` can verify a value arriving through an erased ABI
/// boundary against this classifier. Enum classifiers are excluded: enum
/// values cross erased slots as raw ordinals (or ordinal IntBoxes), neither
/// of which carries the nominal tag the nominal check requires, so the cast
/// would falsely throw. `Nothing` (`.null`) accepts only the null value the
/// erased boundary still needs to let through.
func kirErasedBoundaryCheckable(_ type: TypeID, sema: SemaModule) -> Bool {
    switch RuntimeTypeCheckToken.classify(type: type, sema: sema).category {
    case .unknown, .any, .null:
        return false
    case let .nominal(symbol):
        return sema.symbols.symbol(symbol)?.kind != .enumClass
    default:
        return true
    }
}

/// Whether a declared function result crosses the ABI as an erased generic
/// value. A definitely-non-null `T & Any` return still erases to T.
func kirIsNonReifiedErasedReturnType(_ type: TypeID, sema: SemaModule) -> Bool {
    let typeParameter: TypeID = if case let .intersection(parts) = sema.types.kind(of: type),
                                   parts.count == 2,
                                   parts.contains(where: { sema.types.kind(of: $0) == .any(.nonNull) }),
                                   let parameter = parts.first(where: {
                                       if case .typeParam = sema.types.kind(of: $0) { return true }
                                       return false
                                   })
    {
        parameter
    } else {
        type
    }
    guard case let .typeParam(parameter) = sema.types.kind(of: typeParameter) else {
        return false
    }
    // Synthetic type-parameter symbols (precompiled/imported declarations
    // and fallback stubs like List<E>.get) carry negative IDs and never
    // appear in the local symbol table. Only a materialized symbol can
    // hold `reifiedTypeParameter`, so an unresolved parameter is always
    // an erased return — without this, every stdlib generic member
    // (`List.get`, `MutableMap.get`, ...) silently skipped its JVM
    // boundary checkcast and let a heap-polluted element through
    // (KUU-3668).
    guard let symbol = sema.symbols.symbol(parameter.symbol) else {
        return true
    }
    return !symbol.flags.contains(.reifiedTypeParameter)
}

/// The resolved `(bound, checkType)` pair for a generic call or property
/// getter's substituted result crossing the erased ABI boundary — nil when
/// no boundary checkcast is required. For a property read the claim type is
/// the member's own static type (`d.x : String?`), which Kotlin checkcasts
/// regardless of what the surrounding expression expects — e.g.
/// `println(d.x)` still checkcasts on JVM — so it takes precedence over the
/// context-expected type; call results keep the context-expected type.
func kirErasedGenericCallClaimCheck(
    exprID: ExprID,
    boundType: TypeID?,
    sema: SemaModule
) -> (bound: TypeID, checkType: TypeID?)? {
    let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee
    let propertySymbol: SymbolID? = if let chosenCallee {
        sema.symbols.accessorOwnerProperty(for: chosenCallee)
            ?? sema.symbols.propertySymbol(forAccessor: chosenCallee)
            ?? (sema.symbols.symbol(chosenCallee)?.kind == .property ? chosenCallee : nil)
            ?? sema.symbols.parentSymbol(for: chosenCallee).flatMap { parent in
                sema.symbols.symbol(parent)?.kind == .property ? parent : nil
            }
    } else {
        sema.bindings.identifierSymbol(for: exprID).flatMap { symbol in
            sema.symbols.symbol(symbol)?.kind == .property ? symbol : nil
        }
    }
    let declaredReturnType: TypeID? = if let propertySymbol {
        sema.symbols.propertyType(for: propertySymbol)
            ?? chosenCallee.flatMap { sema.symbols.functionSignature(for: $0)?.returnType }
    } else if let chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosenCallee)
    {
        signature.returnType
    } else if let callableBinding = sema.bindings.callableValueCalls[exprID],
              case let .functionType(functionType) = sema.types.kind(of: callableBinding.functionType)
    {
        functionType.returnType
    } else {
        nil
    }
    let expressionBound = propertySymbol != nil
        ? sema.bindings.exprType(for: exprID) ?? boundType
        : boundType ?? sema.bindings.exprType(for: exprID)
    let consumer = propertySymbol == nil ? sema.bindings.genericCallConsumerTypes[exprID] : nil
    guard let declaredReturnType,
          kirIsNonReifiedErasedReturnType(declaredReturnType, sema: sema),
          let target = consumer ?? expressionBound
    else {
        return nil
    }
    // A platform value must retain its flexible representation until the
    // later null assertion, even when the destination is a non-null primitive.
    let isPlatformResult = expressionBound.map { sema.types.nullability(of: $0) == .platformType } ?? false
    let bound = isPlatformResult ? (expressionBound ?? target) : target
    // Calls coerced to Unit evaluate for side effects and discard their
    // erased result, so no cast of that result is observable in Kotlin.
    // Property reads retain their own platform-Unit behavior.
    if propertySymbol == nil,
       (bound == sema.types.unitType || sema.bindings.unitReturnCoercionExprs.contains(exprID)) {
        return nil
    }
    guard let checkType = kirCheckableCastErasure(of: target, sema: sema),
          kirErasedBoundaryCheckable(checkType, sema: sema)
    else {
        // An erased consumer (such as Any?) needs the raw object, without a
        // cast to the narrower source-level type argument. Preserve that ABI
        // representation even though no checkcast is emitted.
        return consumer == nil ? nil : (bound, nil)
    }
    // A platform result can still contain null. Check its erased classifier
    // without rejecting null; a non-null use inserts its own assertion later.
    let nullableCheckType = isPlatformResult
        ? sema.types.makeNullable(checkType)
        : checkType
    return (bound, nullableCheckType)
}

/// True when a generic call or property getter's substituted result can be
/// checked before the erased ABI result is converted to its native representation.
func kirShouldCheckErasedGenericCallResult(
    exprID: ExprID,
    boundType: TypeID?,
    sema: SemaModule
) -> Bool {
    kirErasedGenericCallClaimCheck(exprID: exprID, boundType: boundType, sema: sema) != nil
}
