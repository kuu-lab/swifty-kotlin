import Foundation

private struct BuiltinArrayDescriptor {
    let name: String
    let element: String
    let elementToken: Int64
    let storage: String?
}

private let builtinArrays: [BuiltinArrayDescriptor] = [
    .init(name: "Array", element: "Any", elementToken: RuntimeTypeTokenEncoding.anyBase, storage: nil),
    .init(name: "BooleanArray", element: "Boolean", elementToken: RuntimeTypeTokenEncoding.booleanBase, storage: nil),
    .init(name: "ByteArray", element: "Byte", elementToken: RuntimeTypeTokenEncoding.byteBase, storage: nil),
    .init(name: "ShortArray", element: "Short", elementToken: RuntimeTypeTokenEncoding.shortBase, storage: nil),
    .init(name: "IntArray", element: "Int", elementToken: RuntimeTypeTokenEncoding.intBase, storage: nil),
    .init(name: "LongArray", element: "Long", elementToken: RuntimeTypeTokenEncoding.longBase, storage: nil),
    .init(name: "FloatArray", element: "Float", elementToken: RuntimeTypeTokenEncoding.floatBase, storage: nil),
    .init(name: "DoubleArray", element: "Double", elementToken: RuntimeTypeTokenEncoding.doubleBase, storage: nil),
    .init(name: "CharArray", element: "Char", elementToken: RuntimeTypeTokenEncoding.charBase, storage: nil),
    .init(name: "UByteArray", element: "UByte", elementToken: RuntimeTypeTokenEncoding.ubyteBase, storage: "ByteArray"),
    .init(name: "UShortArray", element: "UShort", elementToken: RuntimeTypeTokenEncoding.ushortBase, storage: "ShortArray"),
    .init(name: "UIntArray", element: "UInt", elementToken: RuntimeTypeTokenEncoding.uintBase, storage: "IntArray"),
    .init(name: "ULongArray", element: "ULong", elementToken: RuntimeTypeTokenEncoding.ulongBase, storage: "LongArray"),
]
private let builtinArrayLock = NSLock()

private func builtinArrayIndex(_ classRaw: Int) -> Int? {
    guard let box = runtimeKClassBox(from: classRaw) else { return nil }
    let token = Int64(truncatingIfNeeded: box.typeToken)
    guard token & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.nominalBase else { return nil }
    let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    return builtinArrays.firstIndex { runtimeStableNominalTypeID(fqName: "kotlin.\($0.name)") == payload }
}

func filterBuiltinArrayDeclaredFunctions(_ functions: [Int], classRaw: Int) -> [Int] {
    guard let index = builtinArrayIndex(classRaw), builtinArrays[index].storage == nil else { return functions }
    let inherited: Set<String> = ["equals", "hashCode", "toString"]
    return functions.filter { function in
        guard let name = runtimeStringFromRaw(__kk_kcallable_get_name(function)) else { return true }
        return !inherited.contains(name)
    }
}

private func arrayType(_ name: String, token: Int64) -> Int {
    let nameRaw = runtimeMakeStringRaw(name)
    let classifier = __kk_kclass_create(Int(token), nameRaw)
    return registerRuntimeObject(RuntimeKTypeBox(classifierRaw: classifier, argumentRaws: [], isMarkedNullable: false, typeNameRaw: nameRaw))
}

private func arrayElementType(_ descriptor: BuiltinArrayDescriptor, classRaw: Int) -> Int {
    guard descriptor.name == "Array" else {
        return arrayType("kotlin.\(descriptor.element)", token: descriptor.elementToken)
    }
    let parameter = runtimeKClassTypeParameterHandles(qualifiedName: "kotlin.Array", metadata: runtimeKClassBox(from: classRaw)?.metadata).first
        ?? __kk_ktypeparameter_create(Int(runtimeStableNominalTypeID(fqName: "kotlin.Array.<type-parameter-T>")), runtimeMakeStringRaw("T"), 2, 0)
    return registerRuntimeObject(RuntimeKTypeBox(classifierRaw: parameter, argumentRaws: [], isMarkedNullable: false, typeNameRaw: runtimeMakeStringRaw("T")))
}

private func arrayClassType(_ descriptor: BuiltinArrayDescriptor, classRaw: Int) -> Int {
    let arguments = descriptor.name == "Array" ? [__kk_ktypeprojection_create(arrayElementType(descriptor, classRaw: classRaw), 2)] : []
    return registerRuntimeObject(RuntimeKTypeBox(classifierRaw: classRaw, argumentRaws: arguments, isMarkedNullable: false, typeNameRaw: runtimeMakeStringRaw("kotlin.\(descriptor.name)")))
}

private func arrayNominalToken(_ name: String) -> Int64 {
    (runtimeStableNominalTypeID(fqName: "kotlin.\(name)") << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
}

private func unsignedArrayValue(_ value: Int, token: Int64) -> Int {
    switch token {
    case RuntimeTypeTokenEncoding.ubyteBase: return Int(UInt8(truncatingIfNeeded: value))
    case RuntimeTypeTokenEncoding.ushortBase: return Int(UInt16(truncatingIfNeeded: value))
    case RuntimeTypeTokenEncoding.uintBase: return Int(UInt32(truncatingIfNeeded: value))
    default: return value
    }
}

private func invokeArrayMember(_ environment: Int, _ arguments: Int, _ mask: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    guard let receiver = runtimeListBox(from: arguments)?.elements.first,
          let array = runtimeArrayBox(from: receiver) else {
        thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Expected an array receiver.")
        return runtimeNullSentinelInt
    }
    if environment >= 200 {
        let index = (environment - 200) / 8
        let operation = (environment - 200) % 8
        let descriptor = builtinArrays[index]
        let values = runtimeListBox(from: arguments)?.elements ?? []
        switch operation {
        case 0:
            let copy = kk_array_new(array.count)
            if let copyBox = runtimeArrayBox(from: copy) {
                copyBox.values = array.values
                if let component = array.componentType { copyBox.installComponentTypeIfAbsent(component) }
            }
            runtimeRegisterArrayType(rawValue: copy, typeID: runtimeStableNominalTypeID(fqName: "kotlin.\(descriptor.name)"))
            return copy
        case 1: return kk_box_bool(values.count > 1 ? kk_any_member_equals(receiver, values[1]) : 0)
        case 2: return kk_box_int(kk_any_member_hashCode(receiver))
        case 3:
            let iteratorName = descriptor.name == "Array" || descriptor.storage != nil ? "kotlin.collections.Iterator" : "kotlin.collections.\(descriptor.element)Iterator"
            let iterator = registerRuntimeObject(RuntimeListIteratorBox(values: array.values, currentValue: { array.value(at: $0) }), typeID: runtimeStableNominalTypeID(fqName: iteratorName))
            registerListIteratorItable(raw: iterator)
            return iterator
        case 4: return Int(bitPattern: kk_any_member_to_string(receiver))
        case 5:
            guard values.count > 1 else { return kk_box_bool(0) }
            let value = descriptor.elementToken == RuntimeTypeTokenEncoding.ulongBase ? kk_unbox_ulong(values[1]) : kk_unbox_int(values[1])
            return kk_box_bool(array.elements.contains { unsignedArrayValue($0, token: descriptor.elementToken) == value } ? 1 : 0)
        case 6: return kk_box_bool(array.count == 0 ? 1 : 0)
        case 7:
            guard values.count > 1 else { return kk_box_bool(0) }
            let iterator = kk_list_iterator(values[1])
            while kk_list_iterator_hasNext(iterator) != 0 {
                let item = kk_list_iterator_next(iterator, thrown)
                if (thrown?.pointee ?? 0) != 0 { return runtimeNullSentinelInt }
                let value = descriptor.elementToken == RuntimeTypeTokenEncoding.ulongBase ? kk_unbox_ulong(item) : kk_unbox_int(item)
                if !array.elements.contains(where: { unsignedArrayValue($0, token: descriptor.elementToken) == value }) { return kk_box_bool(0) }
            }
            return kk_box_bool(1)
        default: return runtimeNullSentinelInt
        }
    }
    if environment >= 100 {
        let index = (environment - 100) / 2
        let setter = (environment - 100) % 2 == 1
        let descriptor = builtinArrays[index]
        guard let values = runtimeListBox(from: arguments)?.elements, values.count >= (setter ? 3 : 2) else {
            thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Missing array index or value.")
            return runtimeNullSentinelInt
        }
        let position = kk_unbox_int(values[1])
        if setter {
            let value: Int
            switch descriptor.elementToken {
            case RuntimeTypeTokenEncoding.anyBase: value = values[2]
            case RuntimeTypeTokenEncoding.booleanBase: value = kk_unbox_bool(values[2])
            case RuntimeTypeTokenEncoding.charBase: value = kk_unbox_char(values[2])
            case RuntimeTypeTokenEncoding.longBase: value = kk_unbox_long(values[2])
            case RuntimeTypeTokenEncoding.ulongBase: value = kk_unbox_ulong(values[2])
            case RuntimeTypeTokenEncoding.floatBase: value = kk_unbox_float(values[2])
            case RuntimeTypeTokenEncoding.doubleBase: value = kk_unbox_double_nonnull(values[2])
            default: value = kk_unbox_int(values[2])
            }
            _ = kk_array_set(receiver, position, value, thrown)
            return (thrown?.pointee ?? 0) == 0 ? kk_box_unit(0) : runtimeNullSentinelInt
        }
        let value = kk_array_get(receiver, position, thrown)
        guard (thrown?.pointee ?? 0) == 0 else { return runtimeNullSentinelInt }
        switch descriptor.elementToken {
        case RuntimeTypeTokenEncoding.anyBase: return value
        case RuntimeTypeTokenEncoding.booleanBase: return kk_box_bool(value)
        case RuntimeTypeTokenEncoding.byteBase: return kk_box_byte(value)
        case RuntimeTypeTokenEncoding.shortBase: return kk_box_short(value)
        case RuntimeTypeTokenEncoding.intBase: return kk_box_int(value)
        case RuntimeTypeTokenEncoding.longBase: return kk_box_long_nonnull(value)
        case RuntimeTypeTokenEncoding.charBase: return kk_box_char(value)
        case RuntimeTypeTokenEncoding.floatBase: return kk_box_float(value)
        case RuntimeTypeTokenEncoding.doubleBase: return kk_box_double_nonnull(value)
        case RuntimeTypeTokenEncoding.uintBase: return kk_box_uint(unsignedArrayValue(value, token: descriptor.elementToken))
        case RuntimeTypeTokenEncoding.ubyteBase: return kk_box_ubyte(unsignedArrayValue(value, token: descriptor.elementToken))
        case RuntimeTypeTokenEncoding.ushortBase: return kk_box_ushort(unsignedArrayValue(value, token: descriptor.elementToken))
        case RuntimeTypeTokenEncoding.ulongBase: return kk_box_ulong_nonnull(value)
        default: return runtimeNullSentinelInt
        }
    }
    if environment == 0 { return kk_box_int(array.count) }
    let descriptor = builtinArrays[environment - 1]
    guard let storage = descriptor.storage else { return runtimeNullSentinelInt }
    return array.primitiveView(rawValue: receiver,
        sourceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.\(descriptor.name)"),
        targetTypeID: runtimeStableNominalTypeID(fqName: "kotlin.\(storage)"))
}

private let arrayPropertyGet: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { property, receiver, thrown in
    __kk_kcallable_call(property, registerRuntimeObject(RuntimeListBox(elements: [receiver])), thrown)
}
private let arrayPropertyDelegate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, thrown in
    thrown?.pointee = 0
    return runtimeNullSentinelInt
}

func ensureBuiltinArrayMembers(_ classRaw: Int) {
    guard let index = builtinArrayIndex(classRaw), let classBox = runtimeKClassBox(from: classRaw) else { return }
    builtinArrayLock.lock()
    defer { builtinArrayLock.unlock() }
    guard !runtimeKMemberRegistry.builtinMembersInitialized(for: classRaw) else { return }
    let descriptor = builtinArrays[index]
    let empty = registerRuntimeObject(RuntimeListBox(elements: []))
    let invoke: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = invokeArrayMember
    func addProperty(_ name: String, resultName: String, resultToken: Int64, environment: Int, visibility: Int) {
        let nameRaw = runtimeMakeStringRaw(name)
        let resultRaw = runtimeMakeStringRaw(resultName)
        let property = kk_kproperty_stub_create_cached_typed(nameRaw, resultRaw, runtimeMakeStringRaw("kotlin.\(descriptor.name).\(name)"), 0, 1, 0)
        _ = kk_callable_ref_tag_kproperty(property, nameRaw, resultRaw, 1)
        _ = kk_object_register_itable_iface(property, Int(kProperty1RuntimeTypeID), 1)
        _ = kk_object_register_itable_method(property, 1, 0, unsafeBitCast(arrayPropertyGet, to: Int.self))
        _ = kk_object_register_itable_method(property, 1, 1, unsafeBitCast(arrayPropertyDelegate, to: Int.self))
        _ = kk_object_register_itable_method(property, 1, 2, unsafeBitCast(arrayPropertyGet, to: Int.self))
        let receiverName = runtimeMakeStringRaw("kotlin.\(descriptor.name)")
        let receiver = __kk_kparameter_create_typed(0, runtimeNullSentinelInt, receiverName, 0, 0, classBox.typeToken, property)
        runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = arrayClassType(descriptor, classRaw: classRaw)
        let parameters = registerRuntimeObject(RuntimeListBox(elements: [receiver]))
        _ = __kk_kcallable_register(property, unsafeBitCast(invoke, to: Int.self), environment, parameters, empty, 1, visibility, 0, 0)
        _ = __kk_kcallable_register_return_type(property, arrayType(resultName, token: resultToken))
        _ = __kk_kclass_register_member(classRaw, property)
    }
    // The source shells only provide compiler intrinsics and have no callable
    // reflection bridge. Replace those stubs with the actual array operations.
    let oldFunctions = runtimeKMemberRegistry.functions(for: classRaw).filter {
        guard let name = runtimeStringFromRaw(__kk_kcallable_get_name($0)) else { return false }
        return name == "get" || name == "set"
    }
    runtimeKMemberRegistry.remove(classRaw: classRaw, members: Set(oldFunctions))
    func addAccess(_ setter: Bool) {
        let name = setter ? "set" : "get"
        let nameRaw = runtimeMakeStringRaw(name)
        let resultName = setter ? "kotlin.Unit" : "kotlin.\(descriptor.element)"
        let resultToken = setter ? RuntimeTypeTokenEncoding.unitBase : descriptor.elementToken
        let resultRaw = runtimeMakeStringRaw(resultName)
        let arity = setter ? 3 : 2
        let function = __kk_kfunction_create(nameRaw, arity, resultRaw, 4, 0, 0)
        _ = kk_callable_ref_tag_kfunction(function, nameRaw, resultRaw, arity, 4)
        let receiverName = "kotlin.\(descriptor.name)"
        let receiver = __kk_kparameter_create_typed(0, runtimeNullSentinelInt, runtimeMakeStringRaw(receiverName), 0, 0, classBox.typeToken, function)
        runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = arrayClassType(descriptor, classRaw: classRaw)
        let position = __kk_kparameter_create_typed(1, runtimeMakeStringRaw("index"), runtimeMakeStringRaw("kotlin.Int"), 0, 2, Int(RuntimeTypeTokenEncoding.intBase), function)
        runtimeKParameterBox(from: position)?.reflectedTypeRaw = arrayType("kotlin.Int", token: RuntimeTypeTokenEncoding.intBase)
        var parameters = [receiver, position]
        if setter {
            let elementName = "kotlin.\(descriptor.element)"
            let value = __kk_kparameter_create_typed(2, runtimeMakeStringRaw("value"), runtimeMakeStringRaw(elementName), 0, 2, descriptor.name == "Array" ? 0 : Int(descriptor.elementToken), function)
            runtimeKParameterBox(from: value)?.reflectedTypeRaw = arrayElementType(descriptor, classRaw: classRaw)
            parameters.append(value)
        }
        _ = __kk_kcallable_register(function, unsafeBitCast(invoke, to: Int.self), 100 + index * 2 + (setter ? 1 : 0), registerRuntimeObject(RuntimeListBox(elements: parameters)), empty, 1, 0, 0, 0)
        _ = __kk_kcallable_register_return_type(function, setter ? arrayType(resultName, token: resultToken) : arrayElementType(descriptor, classRaw: classRaw))
        _ = __kk_kclass_register_member(classRaw, function)
    }
    addAccess(false)
    addAccess(true)
    func addCommon(_ name: String, operation: Int, resultName: String, resultToken: Int64, argument: (String, String, Int64)? = nil, operatorFlag: Bool = false) {
        let nameRaw = runtimeMakeStringRaw(name)
        let resultRaw = runtimeMakeStringRaw(resultName)
        let arity = argument == nil ? 1 : 2
        let flags = operatorFlag ? 4 : 0
        let function = __kk_kfunction_create(nameRaw, arity, resultRaw, flags, 0, 0)
        _ = kk_callable_ref_tag_kfunction(function, nameRaw, resultRaw, arity, flags)
        let receiverName = "kotlin.\(descriptor.name)"
        let receiver = __kk_kparameter_create_typed(0, runtimeNullSentinelInt, runtimeMakeStringRaw(receiverName), 0, 0, classBox.typeToken, function)
        runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = arrayClassType(descriptor, classRaw: classRaw)
        var parameters = [receiver]
        if let (argumentName, typeName, token) = argument {
            let parameter = __kk_kparameter_create_typed(1, runtimeMakeStringRaw(argumentName), runtimeMakeStringRaw(typeName), 0, 2, Int(token), function)
            let nullable = token & RuntimeTypeTokenEncoding.nullableBit != 0
            let classifier = __kk_kclass_create(Int(token & ~RuntimeTypeTokenEncoding.nullableBit), runtimeMakeStringRaw(typeName))
            let typeArguments = operation == 7 ? [__kk_ktypeprojection_create(arrayElementType(descriptor, classRaw: classRaw), 2)] : []
            runtimeKParameterBox(from: parameter)?.reflectedTypeRaw = registerRuntimeObject(RuntimeKTypeBox(classifierRaw: classifier, argumentRaws: typeArguments, isMarkedNullable: nullable, typeNameRaw: runtimeMakeStringRaw(typeName)))
            parameters.append(parameter)
        }
        _ = __kk_kcallable_register(function, unsafeBitCast(invoke, to: Int.self), 200 + index * 8 + operation, registerRuntimeObject(RuntimeListBox(elements: parameters)), empty, 1, 0, 0, 0)
        let returnType: Int
        if operation == 0 {
            returnType = arrayClassType(descriptor, classRaw: classRaw)
        } else if operation == 3 && (descriptor.name == "Array" || descriptor.storage != nil) {
            let classifier = __kk_kclass_create(Int(resultToken), resultRaw)
            returnType = registerRuntimeObject(RuntimeKTypeBox(classifierRaw: classifier, argumentRaws: [__kk_ktypeprojection_create(arrayElementType(descriptor, classRaw: classRaw), 2)], isMarkedNullable: false, typeNameRaw: resultRaw))
        } else {
            returnType = arrayType(resultName, token: resultToken)
        }
        _ = __kk_kcallable_register_return_type(function, returnType)
        _ = __kk_kclass_register_member(classRaw, function)
    }
    let bool = RuntimeTypeTokenEncoding.booleanBase
    if descriptor.storage == nil {
        addCommon("clone", operation: 0, resultName: "kotlin.\(descriptor.name)", resultToken: Int64(classBox.typeToken))
    }
    addCommon("equals", operation: 1, resultName: "kotlin.Boolean", resultToken: bool, argument: ("other", "kotlin.Any?", RuntimeTypeTokenEncoding.anyBase | RuntimeTypeTokenEncoding.nullableBit), operatorFlag: true)
    addCommon("hashCode", operation: 2, resultName: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase)
    let iteratorName = descriptor.name == "Array" || descriptor.storage != nil ? "kotlin.collections.Iterator" : "kotlin.collections.\(descriptor.element)Iterator"
    addCommon("iterator", operation: 3, resultName: iteratorName, resultToken: runtimeTypeToken(forQualifiedName: iteratorName), operatorFlag: true)
    addCommon("toString", operation: 4, resultName: "kotlin.String", resultToken: RuntimeTypeTokenEncoding.stringBase)
    if descriptor.storage != nil {
        addCommon("contains", operation: 5, resultName: "kotlin.Boolean", resultToken: bool, argument: ("element", "kotlin.\(descriptor.element)", descriptor.elementToken), operatorFlag: true)
        addCommon("isEmpty", operation: 6, resultName: "kotlin.Boolean", resultToken: bool)
        let collection = "kotlin.collections.Collection"
        addCommon("containsAll", operation: 7, resultName: "kotlin.Boolean", resultToken: bool, argument: ("elements", collection, runtimeTypeToken(forQualifiedName: collection)))
    }
    addProperty("size", resultName: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase, environment: 0, visibility: 0)
    if let storage = descriptor.storage {
        addProperty("storage", resultName: "kotlin.\(storage)", resultToken: arrayNominalToken(storage), environment: index + 1, visibility: 2)
    }
    runtimeKMemberRegistry.markBuiltinMembersInitialized(for: classRaw)
}

private func invokeArrayConstructor(_ environment: Int, _ arguments: Int, _ mask: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    let index = environment / 4
    let mode = environment % 4
    let descriptor = builtinArrays[index]
    guard let values = runtimeListBox(from: arguments)?.elements, let first = values.first else { return runtimeNullSentinelInt }
    let typeID = runtimeStableNominalTypeID(fqName: "kotlin.\(descriptor.name)")
    if mode == 2, let storage = descriptor.storage, let array = runtimeArrayBox(from: first) {
        return array.primitiveView(rawValue: first, sourceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.\(storage)"), targetTypeID: typeID)
    }
    let size = kk_unbox_int(first)
    let result = kk_array_new_checked(size, thrown)
    guard result != 0 else { return runtimeNullSentinelInt }
    runtimeRegisterArrayType(rawValue: result, typeID: typeID)
    if mode == 1, values.count > 1 {
        for i in 0..<size {
            let value = kk_function_invoke(values[1], i, thrown)
            if (thrown?.pointee ?? 0) != 0 { return runtimeNullSentinelInt }
            _ = kk_array_set(result, i, value, thrown)
        }
    }
    return result
}

func ensureBuiltinArrayConstructors(_ classRaw: Int) {
    guard let index = builtinArrayIndex(classRaw) else { return }
    builtinArrayLock.lock()
    defer { builtinArrayLock.unlock() }
    guard !runtimeKConstructorRegistry.builtinArrayInitialized(for: classRaw) else { return }
    runtimeKConstructorRegistry.clearBuiltinArrayConstructors(for: classRaw)
    let descriptor = builtinArrays[index]
    let typeName = "kotlin.\(descriptor.name)"
    let empty = registerRuntimeObject(RuntimeListBox(elements: []))
    let invoke: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = invokeArrayConstructor
    func addConstructor(mode: Int, primary: Bool, visibility: Int) {
        let storage = mode == 2 ? descriptor.storage : nil
        let arity = mode == 1 ? 2 : 1
        let raw = __kk_kconstructor_create(runtimeMakeStringRaw("<init>"), arity, runtimeMakeStringRaw(typeName), 0, primary ? 1 : 0, runtimeMakeStringRaw(visibility == 2 ? "INTERNAL" : "PUBLIC"), classRaw)
        _ = __kk_kconstructor_set_jvm_visibility(raw, visibility == 2 ? 3 : 0)
        let firstName = storage == nil ? "size" : "storage"
        let firstType = storage.map { "kotlin.\($0)" } ?? "kotlin.Int"
        let firstToken = storage.map(arrayNominalToken) ?? RuntimeTypeTokenEncoding.intBase
        let first = __kk_kparameter_create_typed(0, runtimeMakeStringRaw(firstName), runtimeMakeStringRaw(firstType), 0, 2, Int(firstToken), raw)
        runtimeKParameterBox(from: first)?.reflectedTypeRaw = arrayType(firstType, token: firstToken)
        _ = __kk_kconstructor_set_parameter_type(raw, 0, Int(firstToken))
        var parameters = [first]
        if mode == 1 {
            let functionToken = (Int64(1) << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.functionBase
            let functionName = "kotlin.Function1"
            let parameter = __kk_kparameter_create_typed(1, runtimeMakeStringRaw("init"), runtimeMakeStringRaw(functionName), 0, 2, Int(functionToken), raw)
            let classifier = __kk_kclass_create(Int(functionToken), runtimeMakeStringRaw(functionName))
            let intType = arrayType("kotlin.Int", token: RuntimeTypeTokenEncoding.intBase)
            let elementType = arrayElementType(descriptor, classRaw: classRaw)
            let arguments = [__kk_ktypeprojection_create(intType, 2), __kk_ktypeprojection_create(elementType, 2)]
            runtimeKParameterBox(from: parameter)?.reflectedTypeRaw = registerRuntimeObject(RuntimeKTypeBox(classifierRaw: classifier, argumentRaws: arguments, isMarkedNullable: false, typeNameRaw: runtimeMakeStringRaw(functionName)))
            _ = __kk_kconstructor_set_parameter_type(raw, 1, Int(functionToken))
            parameters.append(parameter)
        }
        let list = registerRuntimeObject(RuntimeListBox(elements: parameters))
        _ = __kk_kcallable_register(raw, unsafeBitCast(invoke, to: Int.self), index * 4 + mode, list, empty, 1, visibility, 0, 0)
        _ = __kk_kcallable_register_return_type(raw, arrayClassType(descriptor, classRaw: classRaw))
    }
    if descriptor.storage != nil {
        addConstructor(mode: 2, primary: true, visibility: 2)
        addConstructor(mode: 0, primary: false, visibility: 0)
    } else if descriptor.name == "Array" {
        addConstructor(mode: 1, primary: false, visibility: 0)
    } else {
        addConstructor(mode: 0, primary: true, visibility: 0)
        addConstructor(mode: 1, primary: false, visibility: 0)
    }
    runtimeKConstructorRegistry.markBuiltinArrayInitialized(for: classRaw)
}
