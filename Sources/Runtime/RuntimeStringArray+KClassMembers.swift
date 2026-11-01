import Foundation

// String is a runtime primitive rather than a lowered class declaration, so
// its JVM-compatible zero-argument constructor is registered on demand.
private let builtinStringConstructorLock = NSLock()
private let builtinStringMemberLock = NSLock()
private let builtinStringLengthGet: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, receiver, thrown in
    thrown?.pointee = 0
    guard kk_op_is(receiver, Int(RuntimeTypeTokenEncoding.stringBase)) != 0 else {
        thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Expected a String receiver.")
        return runtimeNullSentinelInt
    }
    return kk_box_int(runtimeStringUTF16CodeUnits(receiver).count)
}
private let builtinStringLengthDelegate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, _, thrown in
    thrown?.pointee = 0
    return runtimeNullSentinelInt
}

private func runtimeBuiltinStringMember(
    _ member: Int, _ arguments: Int, _: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let values = runtimeListBox(from: arguments)?.elements, let receiver = values.first else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Missing String receiver.")
        return runtimeNullSentinelInt
    }
    switch member {
    case 0: return kk_box_int(runtimeStringUTF16CodeUnits(receiver).count)
    case 1:
        let result = kk_string_get(receiver, kk_unbox_int(values[1]), outThrown)
        return outThrown == nil || outThrown?.pointee == 0 ? kk_box_char(result) : runtimeNullSentinelInt
    case 2: return receiver
    case 3: return kk_box_int(__kk_string_compareTo_member(receiver, values[1]))
    case 4:
        guard let lhs = runtimeStringFromRaw(receiver), let rhs = runtimeStringFromRaw(values[1]) else {
            return kk_box_bool(0)
        }
        return kk_box_bool(runtimeStringsEqual(lhs, rhs) ? 1 : 0)
    case 5: return kk_box_int(kk_any_member_hashCode(receiver))
    case 6: return __kk_string_plus(receiver, values[1])
    case 7: return kk_char_sequence_subSequence(receiver, kk_unbox_int(values[1]), kk_unbox_int(values[2]), outThrown)
    default: return runtimeNullSentinelInt
    }
}

private func ensureBuiltinStringMembers(_ kclassRaw: Int) {
    guard let box = runtimeKClassBox(from: kclassRaw),
          Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask
            == RuntimeTypeTokenEncoding.stringBase
    else { return }
    builtinStringMemberLock.lock()
    defer { builtinStringMemberLock.unlock() }
    guard !runtimeKMemberRegistry.builtinMembersInitialized(for: kclassRaw) else { return }

    let invoke: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = runtimeBuiltinStringMember
    let invoker = unsafeBitCast(invoke, to: Int.self)
    let emptyList = registerRuntimeObject(RuntimeListBox(elements: []))
    func makeType(_ name: String, token: Int64) -> Int {
        let nameRaw = runtimeMakeStringRaw(name)
        let classifier = __kk_kclass_create(Int(token & ~RuntimeTypeTokenEncoding.nullableBit), nameRaw)
        return registerRuntimeObject(RuntimeKTypeBox(
            classifierRaw: classifier, argumentRaws: [],
            isMarkedNullable: token & RuntimeTypeTokenEncoding.nullableBit != 0, typeNameRaw: nameRaw
        ))
    }
    func add(_ name: String, result: String, resultToken: Int64, arguments: [(name: String, type: String, token: Int64)], member: Int, property: Bool = false, flags: Int = 0) {
        let nameRaw = runtimeMakeStringRaw(name)
        let resultRaw = runtimeMakeStringRaw(result)
        let raw: Int
        if property {
            raw = kk_kproperty_stub_create_cached_typed(nameRaw, resultRaw, runtimeMakeStringRaw("kotlin.String.length"), 0, 1, 0)
            _ = kk_callable_ref_tag_kproperty(raw, nameRaw, resultRaw, arguments.count + 1)
            // KUU-3947: render the builtin member handle like the JVM —
            // `val kotlin.String.length: kotlin.Int` — not the stub's bare
            // `val length: kotlin.Int`.
            __kk_function_set_description(raw, runtimeMakeStringRaw("val kotlin.String.\(name): \(result)"), 0)
            _ = kk_object_register_itable_iface(raw, Int(kProperty1RuntimeTypeID), 1)
            _ = kk_object_register_itable_method(raw, 1, 0, unsafeBitCast(builtinStringLengthGet, to: Int.self))
            _ = kk_object_register_itable_method(raw, 1, 1, unsafeBitCast(builtinStringLengthDelegate, to: Int.self))
            _ = kk_object_register_itable_method(raw, 1, 2, unsafeBitCast(builtinStringLengthGet, to: Int.self))
        } else {
            raw = __kk_kfunction_create(nameRaw, arguments.count + 1, resultRaw, flags, 0, 0)
            _ = kk_callable_ref_tag_kfunction(raw, nameRaw, resultRaw, arguments.count + 1, flags)
            // KUU-3947: builtin member-function handles render like the JVM —
            // `fun kotlin.String.get(kotlin.Int): kotlin.Char`.
            let paramTypes = arguments.map { $0.type }.joined(separator: ", ")
            __kk_function_set_description(raw, runtimeMakeStringRaw("fun kotlin.String.\(name)(\(paramTypes)): \(result)"), 0)
        }
        let receiver = __kk_kparameter_create_typed(0, runtimeNullSentinelInt, runtimeMakeStringRaw("kotlin.String"), 0, 0, Int(RuntimeTypeTokenEncoding.stringBase), raw)
        runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = makeType("kotlin.String", token: RuntimeTypeTokenEncoding.stringBase)
        let parameters = [receiver] + arguments.enumerated().map { index, argument in
            let parameter = __kk_kparameter_create_typed(index + 1, runtimeMakeStringRaw(argument.name), runtimeMakeStringRaw(argument.type), 0, 2, Int(argument.token), raw)
            runtimeKParameterBox(from: parameter)?.reflectedTypeRaw = makeType(argument.type, token: argument.token)
            return parameter
        }
        let parameterList = registerRuntimeObject(RuntimeListBox(elements: parameters))
        _ = __kk_kcallable_register(raw, invoker, member, parameterList, emptyList, 1, 0, 0, 0)
        _ = __kk_kcallable_register_return_type(raw, makeType(result, token: resultToken))
        _ = __kk_kclass_register_member(kclassRaw, raw)
    }
    let anyNullable = RuntimeTypeTokenEncoding.anyBase | RuntimeTypeTokenEncoding.nullableBit
    add("length", result: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase, arguments: [], member: 0, property: true)
    add("get", result: "kotlin.Char", resultToken: RuntimeTypeTokenEncoding.charBase, arguments: [("index", "kotlin.Int", RuntimeTypeTokenEncoding.intBase)], member: 1, flags: 4)
    add("toString", result: "kotlin.String", resultToken: RuntimeTypeTokenEncoding.stringBase, arguments: [], member: 2)
    add("compareTo", result: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase, arguments: [("other", "kotlin.String", RuntimeTypeTokenEncoding.stringBase)], member: 3, flags: 4)
    add("equals", result: "kotlin.Boolean", resultToken: RuntimeTypeTokenEncoding.booleanBase, arguments: [("other", "kotlin.Any?", anyNullable)], member: 4, flags: 4)
    add("hashCode", result: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase, arguments: [], member: 5)
    add("plus", result: "kotlin.String", resultToken: RuntimeTypeTokenEncoding.stringBase, arguments: [("other", "kotlin.Any?", anyNullable)], member: 6, flags: 4)
    let charSequenceToken = (runtimeStableNominalTypeID(fqName: "kotlin.CharSequence") << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
    add("subSequence", result: "kotlin.CharSequence", resultToken: charSequenceToken, arguments: [("startIndex", "kotlin.Int", RuntimeTypeTokenEncoding.intBase), ("endIndex", "kotlin.Int", RuntimeTypeTokenEncoding.intBase)], member: 7)
    runtimeKMemberRegistry.markBuiltinMembersInitialized(for: kclassRaw)
}

private func runtimeEmptyStringConstructor(
    _: Int, _: Int, _: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return runtimeMakeStringRaw("")
}

private func ensureBuiltinStringConstructor(_ kclassRaw: Int) {
    guard let box = runtimeKClassBox(from: kclassRaw),
          Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask
            == RuntimeTypeTokenEncoding.stringBase
    else { return }
    builtinStringConstructorLock.lock()
    defer { builtinStringConstructorLock.unlock() }
    guard runtimeKConstructorRegistry.constructors(for: kclassRaw).isEmpty else { return }
    let constructor = __kk_kconstructor_create(
        runtimeMakeStringRaw("<init>"), 0, runtimeMakeStringRaw("kotlin.String"),
        0, 1, 0, kclassRaw
    )
    let invoke: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = runtimeEmptyStringConstructor
    let emptyList = registerRuntimeObject(RuntimeListBox(elements: []))
    _ = __kk_kcallable_register(constructor, unsafeBitCast(invoke, to: Int.self), 0, emptyList, emptyList, 1, 0, 0, 0)
    let resultType = registerRuntimeObject(RuntimeKTypeBox(
        classifierRaw: kclassRaw, argumentRaws: [], isMarkedNullable: false,
        typeNameRaw: runtimeMakeStringRaw("kotlin.String")
    ))
    _ = __kk_kcallable_register_return_type(constructor, resultType)
}


@_cdecl("__kk_kclass_isInstance")
public func __kk_kclass_isInstance(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return 0
    }
    return kk_op_is(valueRaw, box.typeToken)
}

/// Called during module initialization to attach compile-time member data.
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass returned by `__kk_kclass_create`.
///   - memberRaw: Opaque handle to the member callable (KFunction or KPropertyStub).
/// - Returns: 0 on success.
@_cdecl("__kk_kclass_register_member")
public func __kk_kclass_register_member(_ kclassRaw: Int, _ memberRaw: Int) -> Int {
    runtimeKMemberRegistry.register(classRaw: kclassRaw, memberRaw: memberRaw)
    return 0
}

/// KUU-4029: interned KClass handles for `kclassRaw`'s transitive supertypes,
/// nearest first — a BFS over `state.typeParents`, the same stable-nominal-
/// type-ID graph `kk_op_is` walks (`kk_type_register_super`/`_iface` edges are
/// emitted at class-literal evaluation and construction sites).
///
/// `kotlin.Any` is the only ancestor whose KClass encodes the dedicated
/// `anyBase` token rather than a nominal token — the synthetic `kotlin.Any`
/// symbol is a disguised builtin (`encodeBuiltinDisguisedNominal`) — so its
/// builtin toString/hashCode/equals handles live under that handle.
private func runtimeInheritedKClassRaws(for kclassRaw: Int) -> [Int] {
    guard let box = runtimeKClassBox(from: kclassRaw) else { return [] }
    let token = Int64(truncatingIfNeeded: box.typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let selfNominalID: Int64
    if base == RuntimeTypeTokenEncoding.nominalBase {
        selfNominalID = (token >> RuntimeTypeTokenEncoding.payloadShift)
            & RuntimeTypeTokenEncoding.payloadMask
    } else if let primitiveID = runtimePrimitiveNominalTypeID(forTypeTokenBase: base) {
        selfNominalID = primitiveID
    } else {
        return []
    }
    guard selfNominalID != 0 else { return [] }

    var ancestorIDs: [Int64] = []
    var visited: Set<Int64> = [selfNominalID]
    var queue: [Int64] = [selfNominalID]
    var index = 0
    runtimeStorage.withMetadataLock { state in
        while index < queue.count {
            let current = queue[index]
            index += 1
            guard let parents = state.typeParents[current] else { continue }
            // `typeParents` is a Set — sort for a deterministic merge order.
            for parent in parents.sorted() where visited.insert(parent).inserted {
                queue.append(parent)
                ancestorIDs.append(parent)
            }
        }
    }
    guard !ancestorIDs.isEmpty else { return [] }

    let anyNominalID = runtimeStableNominalTypeID(fqName: "kotlin.Any")
    return ancestorIDs.map { typeID in
        if typeID == anyNominalID {
            return __kk_kclass_create(Int(RuntimeTypeTokenEncoding.anyBase), 0)
        }
        let ancestorToken = (typeID & RuntimeTypeTokenEncoding.payloadMask)
            << RuntimeTypeTokenEncoding.payloadShift
            | RuntimeTypeTokenEncoding.nominalBase
        return __kk_kclass_create(Int(truncatingIfNeeded: ancestorToken), 0)
    }
}

private enum RuntimeMemberKindSelection {
    case all, functionsOnly, propertiesOnly
}

/// KUU-4029: `member*` accessors merge inherited members — the class's own
/// registered members first, then each ancestor's in BFS order. An override
/// shadows the inherited signature: functions dedupe on name + value-
/// parameter count, properties on name. Handles record no parameter types,
/// so same-name/same-arity overloads across a hierarchy collapse (JVM keeps
/// both); within a class every registered member emits.
///
/// `fnPtr == 0` marks builtin handles whose `arity` counts the dispatch
/// receiver (String/primitive/array members); class-registered handles carry
/// a symbol `fnPtr` and count only value parameters.
private func runtimeKClassCollectedMembers(
    _ kclassRaw: Int,
    selection: RuntimeMemberKindSelection,
    includeInherited: Bool
) -> [Int] {
    var classRaws = [kclassRaw]
    if includeInherited {
        classRaws += runtimeInheritedKClassRaws(for: kclassRaw)
    }
    var elements: [Int] = []
    var shadowedSignatures: Set<String> = []
    for classRaw in classRaws {
        ensureBuiltinStringMembers(classRaw)
        ensureBuiltinPrimitiveMembers(classRaw)
        ensureBuiltinArrayMembers(classRaw)
        var emittedKeys: [String] = []
        for member in runtimeKMemberRegistry.members(for: classRaw) {
            let key: String
            if let function = resolveRuntimeHandle(member, as: RuntimeKFunctionBox.self) {
                guard selection != .propertiesOnly else { continue }
                let name = runtimeStringFromRaw(function.nameRaw) ?? ""
                let arity = function.fnPtr == 0 ? max(0, function.arity - 1) : function.arity
                key = "f:\(name):\(arity)"
            } else if let stub = resolveRuntimeHandle(member, as: RuntimeKPropertyStub.self) {
                guard selection != .functionsOnly else { continue }
                let name = runtimeStringFromRaw(stub.name) ?? ""
                key = "p:\(name)"
            } else {
                continue
            }
            if !shadowedSignatures.contains(key) {
                elements.append(member)
            }
            emittedKeys.append(key)
        }
        shadowedSignatures.formUnion(emittedKeys)
    }
    return elements
}

@_cdecl("__kk_kclass_members")
public func __kk_kclass_members(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(
        elements: runtimeKClassCollectedMembers(
            kclassRaw, selection: .all, includeInherited: true
        )
    ))
}

/// Only constructors registered through `__kk_kconstructor_create` are returned.
@_cdecl("__kk_kclass_constructors")
public func __kk_kclass_constructors(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    ensureBuiltinStringConstructor(kclassRaw)
    ensureBuiltinPrimitiveConstructor(kclassRaw)
    ensureBuiltinArrayConstructors(kclassRaw)
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKConstructorRegistry.constructors(for: kclassRaw)))
}

/// Nested classes are attached per parent type token via
/// `__kk_kclass_register_nested_class` (KUU-1357 / MIGRATION-REFLECT-002).
@_cdecl("__kk_kclass_nested_classes")
public func __kk_kclass_nested_classes(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = runtimeKNestedClassRegistry.nestedClasses(for: box.typeToken).map {
        __kk_kclass_create($0.token, $0.nameRaw)
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

/// Emitted during class reflection metadata setup.
@_cdecl("__kk_kclass_register_companion")
public func __kk_kclass_register_companion(
    _ typeToken: Int,
    _ companionToken: Int,
    _ companionNameRaw: Int
) -> Int {
    runtimeKCompanionRegistry.register(
        typeToken: typeToken,
        companionToken: companionToken,
        companionNameRaw: companionNameRaw
    )
    return 0
}

@_cdecl("__kk_kclass_companion_object")
public func __kk_kclass_companion_object(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let entry = runtimeKCompanionRegistry.companion(for: box.typeToken)
    else {
        return runtimeNullSentinelInt
    }
    return __kk_kclass_create(entry.token, entry.nameRaw)
}

/// Emitted once per nested class during class reflection metadata
/// setup (KUU-1357 / MIGRATION-REFLECT-002).
@_cdecl("__kk_kclass_register_nested_class")
public func __kk_kclass_register_nested_class(
    _ typeToken: Int,
    _ nestedToken: Int,
    _ nestedNameRaw: Int
) -> Int {
    runtimeKNestedClassRegistry.register(
        typeToken: typeToken,
        nestedToken: nestedToken,
        nestedNameRaw: nestedNameRaw
    )
    return 0
}

@_cdecl("__kk_kclass_primary_constructor")
public func __kk_kclass_primary_constructor(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return runtimeNullSentinelInt
    }
    ensureBuiltinStringConstructor(kclassRaw)
    ensureBuiltinPrimitiveConstructor(kclassRaw)
    ensureBuiltinArrayConstructors(kclassRaw)
    return runtimeKConstructorRegistry.primaryConstructor(for: kclassRaw) ?? runtimeNullSentinelInt
}


/// Returns registered `RuntimeKPropertyStub` handles only.
@_cdecl("__kk_kclass_properties")
public func __kk_kclass_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    ensureBuiltinStringMembers(kclassRaw)
    ensureBuiltinPrimitiveMembers(kclassRaw)
    ensureBuiltinArrayMembers(kclassRaw)
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.properties(for: kclassRaw)))
}

/// JVM `memberProperties` includes inherited properties — unlike
/// `declaredMemberProperties`/`properties`, which stay self-only.
@_cdecl("__kk_kclass_member_properties")
public func __kk_kclass_member_properties(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(
        elements: runtimeKClassCollectedMembers(
            kclassRaw, selection: .propertiesOnly, includeInherited: true
        )
    ))
}

@_cdecl("__kk_kclass_declared_member_properties")
public func __kk_kclass_declared_member_properties(_ kclassRaw: Int) -> Int {
    __kk_kclass_properties(kclassRaw)
}

/// Returns registered `RuntimeKFunctionBox` handles only.
@_cdecl("__kk_kclass_functions")
public func __kk_kclass_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    ensureBuiltinStringMembers(kclassRaw)
    ensureBuiltinPrimitiveMembers(kclassRaw)
    ensureBuiltinArrayMembers(kclassRaw)
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKMemberRegistry.functions(for: kclassRaw)))
}

/// JVM `memberFunctions` includes inherited functions — unlike
/// `declaredMemberFunctions`/`functions`, which stay self-only.
@_cdecl("__kk_kclass_member_functions")
public func __kk_kclass_member_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(
        elements: runtimeKClassCollectedMembers(
            kclassRaw, selection: .functionsOnly, includeInherited: true
        )
    ))
}

@_cdecl("__kk_kclass_declared_member_functions")
public func __kk_kclass_declared_member_functions(_ kclassRaw: Int) -> Int {
    guard runtimeKClassBox(from: kclassRaw) != nil else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    ensureBuiltinStringMembers(kclassRaw)
    ensureBuiltinPrimitiveMembers(kclassRaw)
    ensureBuiltinArrayMembers(kclassRaw)
    let functions = runtimeKMemberRegistry.functions(for: kclassRaw)
    let declared = filterBuiltinDeclaredFunctions(functions, classRaw: kclassRaw)
    return registerRuntimeObject(RuntimeListBox(elements: filterBuiltinArrayDeclaredFunctions(declared, classRaw: kclassRaw)))
}


/// Casts `valueRaw` to the type represented by this KClass.
/// If the value is an instance of the type, returns it unchanged.
/// If not, sets `outThrown` to a `ClassCastException` and returns the null sentinel.
///
/// - Parameters:
///   - kclassRaw: Opaque handle to the KClass.
///   - valueRaw: The value to cast.
///   - outThrown: Out-pointer for the thrown exception (nullable).
/// - Returns: `valueRaw` on success, or `runtimeNullSentinelInt` on failure.
@_cdecl("__kk_kclass_cast")
public func __kk_kclass_cast(
    _ kclassRaw: Int,
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        outThrown?.pointee = runtimeAllocateClassCastException(
            message: "Invalid KClass handle."
        )
        return runtimeNullSentinelInt
    }
    let isInstance = kk_op_is(valueRaw, box.typeToken)
    if isInstance != 0 {
        return valueRaw
    }
    let typeName: String
    if let metadata = box.metadata {
        typeName = metadata.qualifiedName.isEmpty ? metadata.simpleName : metadata.qualifiedName
    } else {
        typeName = "Unknown"
    }
    outThrown?.pointee = runtimeAllocateClassCastException(
        message: "Value cannot be cast to \(typeName)."
    )
    return runtimeNullSentinelInt
}

/// Never throws; equivalent to Kotlin's `safeCast` (`value as? T`).
@_cdecl("__kk_kclass_safeCast")
public func __kk_kclass_safeCast(_ kclassRaw: Int, _ valueRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    let isInstance = kk_op_is(valueRaw, box.typeToken)
    return isInstance != 0 ? valueRaw : runtimeNullSentinelInt
}
