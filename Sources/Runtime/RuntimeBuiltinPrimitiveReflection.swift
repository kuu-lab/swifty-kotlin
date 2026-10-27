import Foundation

private let builtinPrimitiveMemberLock = NSLock()
private let builtinPrimitiveConstructorLock = NSLock()

private let builtinUnsignedDataGet: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    property, receiver, thrown in
    let arguments = registerRuntimeObject(RuntimeListBox(elements: [receiver]))
    return __kk_kcallable_call(property, arguments, thrown)
}
private let builtinUIntDataDelegate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, _, thrown in
    thrown?.pointee = 0
    return runtimeNullSentinelInt
}

private func invokeBuiltinPrimitiveConstructor(
    _ token: Int, _ arguments: Int, _ mask: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if token == Int(RuntimeTypeTokenEncoding.anyBase) {
        return kk_object_new(0, Int(runtimeStableNominalTypeID(fqName: "kotlin.Any")))
    }
    guard let value = runtimeListBox(from: arguments)?.elements.first else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Missing unsigned value.")
        return runtimeNullSentinelInt
    }
    switch Int64(token) {
    case RuntimeTypeTokenEncoding.uintBase: return kk_box_uint(Int(UInt32(truncatingIfNeeded: kk_unbox_int(value))))
    case RuntimeTypeTokenEncoding.ubyteBase: return kk_box_ubyte(Int(UInt8(truncatingIfNeeded: kk_unbox_int(value))))
    case RuntimeTypeTokenEncoding.ushortBase: return kk_box_ushort(Int(UInt16(truncatingIfNeeded: kk_unbox_int(value))))
    case RuntimeTypeTokenEncoding.ulongBase: return kk_box_ulong_nonnull(kk_unbox_long(value))
    default: return runtimeNullSentinelInt
    }
}

func ensureBuiltinPrimitiveConstructor(_ kclassRaw: Int) {
    guard let box = runtimeKClassBox(from: kclassRaw) else { return }
    let token = Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask
    let descriptor: (name: String, visibility: Int, parameter: (String, Int64)?)
    switch token {
    case RuntimeTypeTokenEncoding.anyBase: descriptor = ("Any", 0, nil)
    case RuntimeTypeTokenEncoding.intBase: descriptor = ("Int", 3, nil)
    case RuntimeTypeTokenEncoding.longBase: descriptor = ("Long", 3, nil)
    case RuntimeTypeTokenEncoding.shortBase: descriptor = ("Short", 3, nil)
    case RuntimeTypeTokenEncoding.byteBase: descriptor = ("Byte", 3, nil)
    case RuntimeTypeTokenEncoding.floatBase: descriptor = ("Float", 3, nil)
    case RuntimeTypeTokenEncoding.doubleBase: descriptor = ("Double", 3, nil)
    case RuntimeTypeTokenEncoding.booleanBase: descriptor = ("Boolean", 3, nil)
    case RuntimeTypeTokenEncoding.charBase: descriptor = ("Char", 3, nil)
    case RuntimeTypeTokenEncoding.uintBase: descriptor = ("UInt", 2, ("Int", RuntimeTypeTokenEncoding.intBase))
    case RuntimeTypeTokenEncoding.ulongBase: descriptor = ("ULong", 2, ("Long", RuntimeTypeTokenEncoding.longBase))
    case RuntimeTypeTokenEncoding.ubyteBase: descriptor = ("UByte", 2, ("Byte", RuntimeTypeTokenEncoding.byteBase))
    case RuntimeTypeTokenEncoding.ushortBase: descriptor = ("UShort", 2, ("Short", RuntimeTypeTokenEncoding.shortBase))
    default: return
    }
    builtinPrimitiveConstructorLock.lock()
    defer { builtinPrimitiveConstructorLock.unlock() }
    guard runtimeKConstructorRegistry.constructors(for: kclassRaw).isEmpty else { return }
    let typeName = runtimeMakeStringRaw("kotlin.\(descriptor.name)")
    let visibility = ["PUBLIC", "PROTECTED", "INTERNAL", "PRIVATE"][descriptor.visibility]
    let constructor = __kk_kconstructor_create(
        runtimeMakeStringRaw("<init>"), descriptor.parameter == nil ? 0 : 1, typeName,
        0, 1, runtimeMakeStringRaw(visibility), kclassRaw
    )
    _ = __kk_kconstructor_set_jvm_visibility(constructor, descriptor.visibility == 0 ? 0 : 3)
    let emptyList = registerRuntimeObject(RuntimeListBox(elements: []))
    var parameters = emptyList
    if let (parameterName, parameterToken) = descriptor.parameter {
        let parameterTypeName = runtimeMakeStringRaw("kotlin.\(parameterName)")
        let parameter = __kk_kparameter_create_typed(
            0, runtimeMakeStringRaw("data"), parameterTypeName, 0, 2, Int(parameterToken), constructor
        )
        let parameterClass = __kk_kclass_create(Int(parameterToken), parameterTypeName)
        runtimeKParameterBox(from: parameter)?.reflectedTypeRaw = registerRuntimeObject(RuntimeKTypeBox(
            classifierRaw: parameterClass, argumentRaws: [], isMarkedNullable: false, typeNameRaw: parameterTypeName
        ))
        parameters = registerRuntimeObject(RuntimeListBox(elements: [parameter]))
        _ = __kk_kconstructor_set_parameter_type(constructor, 0, Int(parameterToken))
    }
    let invoke: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = invokeBuiltinPrimitiveConstructor
    let invoker = descriptor.visibility == 3 ? 0 : unsafeBitCast(invoke, to: Int.self)
    _ = __kk_kcallable_register(constructor, invoker, Int(token), parameters, emptyList, 1, descriptor.visibility, 0, 0)
    let resultType = registerRuntimeObject(RuntimeKTypeBox(
        classifierRaw: kclassRaw, argumentRaws: [], isMarkedNullable: false, typeNameRaw: typeName
    ))
    _ = __kk_kcallable_register_return_type(constructor, resultType)
}

func filterBuiltinDeclaredFunctions(_ functions: [Int], classRaw: Int) -> [Int] {
    guard let box = runtimeKClassBox(from: classRaw) else { return functions }
    let token = Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask
    let exclude: Set<String>
    switch token {
    case RuntimeTypeTokenEncoding.stringBase, RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.longBase, RuntimeTypeTokenEncoding.shortBase,
         RuntimeTypeTokenEncoding.byteBase, RuntimeTypeTokenEncoding.floatBase,
         RuntimeTypeTokenEncoding.doubleBase:
        exclude = ["hashCode"]
    case RuntimeTypeTokenEncoding.unitBase:
        exclude = ["equals", "hashCode"]
    default:
        return functions
    }
    return functions.filter { raw in
        guard let name = runtimeStringFromRaw(__kk_kcallable_get_name(raw)) else { return true }
        return !exclude.contains(name)
    }
}

private func invokeBuiltinPrimitiveMember(
    _ member: Int, _ arguments: Int, _ mask: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let values = runtimeListBox(from: arguments)?.elements, let receiver = values.first else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Missing primitive receiver.")
        return runtimeNullSentinelInt
    }
    if member >= 3000 {
        return invokeBuiltinUnsignedMember(member, values: values, outThrown: outThrown)
    }
    if member >= 2000 {
        return invokeBuiltinFloatingUnary(member, receiver: receiver)
    }
    if member >= 1800 {
        return invokeBuiltinFloatingArithmetic(member, values: values)
    }
    if member >= 1500 {
        let value = UInt16(truncatingIfNeeded: kk_unbox_char(receiver))
        switch member - 1500 {
        case 0:
            let other = UInt16(truncatingIfNeeded: kk_unbox_char(values[1]))
            return kk_box_int(value < other ? -1 : value > other ? 1 : 0)
        case 1: return kk_box_char(Int(value &+ 1))
        case 2: return kk_box_char(Int(value &- 1))
        case 3: return kk_box_int(Int(value) - kk_unbox_char(values[1]))
        case 4: return kk_box_char(Int(UInt16(truncatingIfNeeded: Int64(value) - Int64(Int32(truncatingIfNeeded: kk_unbox_int(values[1]))))))
        case 5: return kk_box_char(Int(UInt16(truncatingIfNeeded: Int64(value) + Int64(Int32(truncatingIfNeeded: kk_unbox_int(values[1]))))))
        case 6: return kk_char_rangeTo(Int(value), kk_unbox_char(values[1]))
        case 7: return __kk_char_rangeUntil(Int(value), kk_unbox_char(values[1]))
        case 8: return kk_box_byte(Int(Int8(truncatingIfNeeded: value)))
        case 9: return kk_box_char(Int(value))
        case 10: return kk_box_double_nonnull(kk_double_to_bits(Double(value)))
        case 11: return kk_box_float(kk_float_to_bits(Float(value)))
        case 12: return kk_box_int(Int(value))
        case 13: return kk_box_long_nonnull(Int(value))
        default: return kk_box_short(Int(Int16(truncatingIfNeeded: value)))
        }
    }
    if member >= 1400 {
        let lhs = kk_unbox_bool(receiver) != 0
        switch member - 1400 {
        case 0:
            let rhs = kk_unbox_bool(values[1]) != 0
            return kk_box_int(lhs == rhs ? 0 : lhs ? 1 : -1)
        case 1: return kk_box_bool(lhs ? 0 : 1)
        case 2: return kk_box_bool(lhs && kk_unbox_bool(values[1]) != 0 ? 1 : 0)
        case 3: return kk_box_bool(lhs || kk_unbox_bool(values[1]) != 0 ? 1 : 0)
        default: return kk_box_bool(lhs != (kk_unbox_bool(values[1]) != 0) ? 1 : 0)
        }
    }
    if member >= 1000 {
        let kind = (member - 1000) % 4
        let until = (member - 1000) / 4 == 1
        let left = kk_unbox_long(receiver)
        let right = kind == 3 ? kk_unbox_long(values[1]) : Int(Int32(truncatingIfNeeded: kk_unbox_int(values[1])))
        return until ? __kk_long_rangeUntil(left, right) : kk_long_rangeTo(left, right)
    }
    if member >= 900 {
        let lhs = Int64(kk_unbox_long(receiver))
        let index = member - 900
        let rhs = index < 3 ? Int64(kk_unbox_long(values[1])) : Int64(kk_unbox_int(values[1]))
        let shift = Int(UInt64(bitPattern: rhs) & 63)
        let result: Int64
        switch index {
        case 0: result = lhs & rhs
        case 1: result = lhs | rhs
        case 2: result = lhs ^ rhs
        case 3: result = lhs &<< shift
        case 4: result = lhs >> shift
        default: result = Int64(bitPattern: UInt64(bitPattern: lhs) >> shift)
        }
        return kk_box_long_nonnull(Int(result))
    }
    if member >= 800 {
        let lhs = Int64(kk_unbox_long(receiver))
        switch member - 800 {
        case 0: return kk_box_long_nonnull(Int(lhs))
        case 1: return kk_box_long_nonnull(Int(0 &- lhs))
        case 2: return kk_box_long_nonnull(Int(lhs &+ 1))
        case 3: return kk_box_long_nonnull(Int(lhs &- 1))
        case 4: return kk_box_long_nonnull(Int(~lhs))
        case 5: return kk_box_byte(Int(Int8(truncatingIfNeeded: lhs)))
        case 6: return kk_box_short(Int(Int16(truncatingIfNeeded: lhs)))
        case 7: return kk_box_int(Int(Int32(truncatingIfNeeded: lhs)))
        case 8: return kk_box_long_nonnull(Int(lhs))
        case 9: return kk_box_float(kk_float_to_bits(Float(lhs)))
        case 10: return kk_box_double_nonnull(kk_double_to_bits(Double(lhs)))
        default: return kk_box_char(Int(UInt16(truncatingIfNeeded: lhs)))
        }
    }
    if member >= 700 {
        return invokeBuiltinLongArithmetic(member, values: values, outThrown: outThrown)
    }
    if member >= 500 {
        let isByte = member < 600
        let index = member - (isByte ? 500 : 600)
        if index == 2 || index == 3 {
            let value = Int32(truncatingIfNeeded: kk_unbox_int(receiver))
            let adjusted = index == 2 ? value &+ 1 : value &- 1
            return isByte ? kk_box_byte(Int(Int8(truncatingIfNeeded: adjusted)))
                : kk_box_short(Int(Int16(truncatingIfNeeded: adjusted)))
        }
        return invokeBuiltinPrimitiveMember(200 + index, arguments, mask, outThrown)
    }
    if member >= 400 {
        let kind = (member - 400) % 4
        let until = (member - 400) / 4 == 1
        let left = Int(Int32(truncatingIfNeeded: kk_unbox_int(receiver)))
        let right = kind == 3 ? kk_unbox_long(values[1]) : Int(Int32(truncatingIfNeeded: kk_unbox_int(values[1])))
        if kind == 3 { return until ? __kk_long_rangeUntil(left, right) : kk_long_rangeTo(left, right) }
        return until ? __kk_op_rangeUntil(left, right) : kk_op_rangeTo(left, right)
    }
    if member >= 300 {
        let lhs = Int32(truncatingIfNeeded: kk_unbox_int(receiver))
        let rhs = Int32(truncatingIfNeeded: kk_unbox_int(values[1]))
        let shift = Int(UInt32(bitPattern: rhs) & 31)
        let result: Int32
        switch member - 300 {
        case 0: result = lhs & rhs
        case 1: result = lhs | rhs
        case 2: result = lhs ^ rhs
        case 3: result = lhs &<< shift
        case 4: result = lhs >> shift
        default: result = Int32(bitPattern: UInt32(bitPattern: lhs) >> shift)
        }
        return kk_box_int(Int(result))
    }
    if member >= 200 {
        let lhs = Int32(truncatingIfNeeded: kk_unbox_int(receiver))
        switch member - 200 {
        case 0: return kk_box_int(Int(lhs))
        case 1: return kk_box_int(Int(0 &- lhs))
        case 2: return kk_box_int(Int(lhs &+ 1))
        case 3: return kk_box_int(Int(lhs &- 1))
        case 4: return kk_box_int(Int(~lhs))
        case 5: return kk_box_byte(Int(Int8(truncatingIfNeeded: lhs)))
        case 6: return kk_box_short(Int(Int16(truncatingIfNeeded: lhs)))
        case 7: return kk_box_int(Int(lhs))
        case 8: return kk_box_long(Int(lhs))
        case 9: return kk_box_float(kk_float_to_bits(Float(lhs)))
        case 10: return kk_box_double(kk_double_to_bits(Double(lhs)))
        default: return kk_box_char(Int(UInt16(truncatingIfNeeded: lhs)))
        }
    }
    if member >= 100 {
        return invokeBuiltinIntArithmetic(member, values: values, outThrown: outThrown)
    }
    switch member {
    case 0: return Int(bitPattern: kk_any_member_to_string(receiver))
    case 1: return kk_box_int(kk_any_member_hashCode(receiver))
    case 2: return kk_any_member_equals(receiver, values[1])
    case 3: return kk_box_int(Int(Int32(truncatingIfNeeded: kk_unbox_int(receiver))))
    case 4: return kk_box_byte(Int(Int8(truncatingIfNeeded: kk_unbox_int(receiver))))
    case 5: return kk_box_short(Int(Int16(truncatingIfNeeded: kk_unbox_int(receiver))))
    case 6: return kk_box_long_nonnull(kk_unbox_ulong(receiver))
    default: return runtimeNullSentinelInt
    }
}

private func builtinUnsignedValue(_ raw: Int, kind: Int) -> UInt64 {
    if kind == 3 { return UInt64(bitPattern: Int64(kk_unbox_ulong(raw))) }
    return UInt64(UInt32(truncatingIfNeeded: kk_unbox_int(raw)))
}

private func boxBuiltinUnsigned(_ value: UInt64, kind: Int) -> Int {
    switch kind {
    case 0: return kk_box_ubyte(Int(UInt8(truncatingIfNeeded: value)))
    case 1: return kk_box_ushort(Int(UInt16(truncatingIfNeeded: value)))
    case 2: return kk_box_uint(Int(UInt32(truncatingIfNeeded: value)))
    default: return kk_box_ulong_nonnull(Int(bitPattern: UInt(value)))
    }
}

private func invokeBuiltinUnsignedMember(_ member: Int, values: [Int], outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let family = member / 1000
    let code = member % 1000
    let kind = code / 100
    let index = code % 100
    let lhs = builtinUnsignedValue(values[0], kind: kind)
    if family == 3 {
        let operation = index / 8
        let otherKind = index % 8
        let rhs = builtinUnsignedValue(values[1], kind: otherKind)
        if [3, 4, 6, 7].contains(operation) && rhs == 0 {
            outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
            return runtimeNullSentinelInt
        }
        if operation == 5 { return kk_box_int(lhs < rhs ? -1 : lhs > rhs ? 1 : 0) }
        let result: UInt64
        switch operation {
        case 0: result = lhs &+ rhs
        case 1: result = lhs &- rhs
        case 2: result = lhs &* rhs
        case 3, 6: result = lhs / rhs
        default: result = lhs % rhs
        }
        return boxBuiltinUnsigned(result, kind: kind == 3 || otherKind == 3 ? 3 : 2)
    }
    if family == 4 {
        switch index {
        case 0: return boxBuiltinUnsigned(lhs &+ 1, kind: kind)
        case 1: return boxBuiltinUnsigned(lhs &- 1, kind: kind)
        case 2: return boxBuiltinUnsigned(~lhs, kind: kind)
        case 3: return kk_box_byte(Int(Int8(truncatingIfNeeded: lhs)))
        case 4: return kk_box_short(Int(Int16(truncatingIfNeeded: lhs)))
        case 5: return kk_box_int(Int(Int32(truncatingIfNeeded: lhs)))
        case 6: return kk_box_long_nonnull(Int(bitPattern: UInt(lhs)))
        case 7: return kk_box_float(kk_float_to_bits(Float(lhs)))
        case 8: return kk_box_double_nonnull(kk_double_to_bits(Double(lhs)))
        default: return boxBuiltinUnsigned(lhs, kind: index - 9)
        }
    }
    if family == 5 {
        let rhs = index < 3 ? builtinUnsignedValue(values[1], kind: kind)
            : UInt64(UInt32(truncatingIfNeeded: kk_unbox_int(values[1])))
        let shift = Int(rhs & (kind == 3 ? 63 : 31))
        let result: UInt64
        switch index {
        case 0: result = lhs & rhs
        case 1: result = lhs | rhs
        case 2: result = lhs ^ rhs
        case 3: result = lhs &<< shift
        default: result = lhs >> shift
        }
        return boxBuiltinUnsigned(result, kind: kind)
    }
    let rhs = builtinUnsignedValue(values[1], kind: kind)
    if kind == 3 {
        let left = Int(bitPattern: UInt(lhs))
        let right = Int(bitPattern: UInt(rhs))
        return index == 0 ? __kk_ulong_rangeTo(left, right) : __kk_op_ulong_rangeUntil(left, right)
    }
    return index == 0 ? __kk_uint_rangeTo(Int(lhs), Int(rhs)) : __kk_uint_rangeUntil(Int(lhs), Int(rhs))
}

private func compareBuiltinFloating<T: BinaryFloatingPoint>(_ lhs: T, _ rhs: T) -> Int {
    if lhs.isNaN { return rhs.isNaN ? 0 : 1 }
    if rhs.isNaN { return -1 }
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    if lhs == 0 && rhs == 0 && lhs.sign != rhs.sign { return lhs.sign == .minus ? -1 : 1 }
    return 0
}

private func invokeBuiltinFloatingArithmetic(_ member: Int, values: [Int]) -> Int {
    let isDouble = member >= 1900
    let base = isDouble ? 1900 : 1800
    let operation = (member - base) / 8
    let kind = (member - base) % 8
    let doubleResult = isDouble || kind == 5
    if doubleResult {
        let lhs = isDouble ? kk_bits_to_double(kk_unbox_double(values[0])) : Double(kk_bits_to_float(kk_unbox_float(values[0])))
        let rhs: Double
        switch kind {
        case 0, 1, 2: rhs = Double(Int32(truncatingIfNeeded: kk_unbox_int(values[1])))
        case 3: rhs = Double(Int64(kk_unbox_long(values[1])))
        case 4: rhs = Double(kk_bits_to_float(kk_unbox_float(values[1])))
        default: rhs = kk_bits_to_double(kk_unbox_double(values[1]))
        }
        if operation == 5 { return kk_box_int(compareBuiltinFloating(lhs, rhs)) }
        let result: Double
        switch operation {
        case 0: result = lhs + rhs
        case 1: result = lhs - rhs
        case 2: result = lhs * rhs
        case 3: result = lhs / rhs
        default: result = lhs.truncatingRemainder(dividingBy: rhs)
        }
        return kk_box_double_nonnull(kk_double_to_bits(result))
    }
    let lhs = kk_bits_to_float(kk_unbox_float(values[0]))
    let rhs: Float
    switch kind {
    case 0, 1, 2: rhs = Float(Int32(truncatingIfNeeded: kk_unbox_int(values[1])))
    case 3: rhs = Float(Int64(kk_unbox_long(values[1])))
    default: rhs = kk_bits_to_float(kk_unbox_float(values[1]))
    }
    if operation == 5 { return kk_box_int(compareBuiltinFloating(lhs, rhs)) }
    let result: Float
    switch operation {
    case 0: result = lhs + rhs
    case 1: result = lhs - rhs
    case 2: result = lhs * rhs
    case 3: result = lhs / rhs
    default: result = lhs.truncatingRemainder(dividingBy: rhs)
    }
    return kk_box_float(kk_float_to_bits(result))
}

private func invokeBuiltinFloatingUnary(_ member: Int, receiver: Int) -> Int {
    let isDouble = member >= 2100
    let index = member - (isDouble ? 2100 : 2000)
    let bits = isDouble ? kk_unbox_double(receiver) : kk_unbox_float(receiver)
    if index < 4 {
        if isDouble {
            let value = kk_bits_to_double(bits)
            let result = index == 0 ? value : index == 1 ? -value : index == 2 ? value + 1 : value - 1
            return kk_box_double_nonnull(kk_double_to_bits(result))
        }
        let value = kk_bits_to_float(bits)
        let result = index == 0 ? value : index == 1 ? -value : index == 2 ? value + 1 : value - 1
        return kk_box_float(kk_float_to_bits(result))
    }
    let integer = isDouble ? __kk_double_to_int(bits) : __kk_float_to_int(bits)
    switch index {
    case 4: return kk_box_byte(Int(Int8(truncatingIfNeeded: integer)))
    case 5: return kk_box_short(Int(Int16(truncatingIfNeeded: integer)))
    case 6: return kk_box_int(integer)
    case 7: return kk_box_long_nonnull(isDouble ? __kk_double_to_long(bits) : __kk_float_to_long(bits))
    case 8: return kk_box_float(isDouble ? kk_double_to_float(bits) : bits)
    case 9: return kk_box_double_nonnull(isDouble ? bits : __kk_float_to_double_bits(bits))
    default: return kk_box_char(Int(UInt16(truncatingIfNeeded: integer)))
    }
}

private func invokeBuiltinLongArithmetic(_ member: Int, values: [Int], outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let operation = (member - 700) / 8
    let kind = (member - 700) % 8
    let left = Int64(kk_unbox_long(values[0]))
    if kind <= 3 {
        let right = kind == 3 ? Int64(kk_unbox_long(values[1])) : Int64(Int32(truncatingIfNeeded: kk_unbox_int(values[1])))
        if (operation == 3 || operation == 4) && right == 0 {
            outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
            return runtimeNullSentinelInt
        }
        if operation == 5 { return kk_box_int(left < right ? -1 : left > right ? 1 : 0) }
        let result: Int64
        switch operation {
        case 0: result = left &+ right
        case 1: result = left &- right
        case 2: result = left &* right
        case 3: result = left == .min && right == -1 ? .min : left / right
        default: result = left == .min && right == -1 ? 0 : left % right
        }
        return kk_box_long_nonnull(Int(result))
    }
    if kind == 4 {
        let lhs = Float(left)
        let rhs = kk_bits_to_float(kk_unbox_float(values[1]))
        if operation == 5 {
            return kk_box_int(rhs.isNaN ? -1 : lhs < rhs ? -1 : lhs > rhs ? 1 : (lhs == 0 && rhs.sign == .minus ? 1 : 0))
        }
        let result: Float
        switch operation {
        case 0: result = lhs + rhs
        case 1: result = lhs - rhs
        case 2: result = lhs * rhs
        case 3: result = lhs / rhs
        default: result = lhs.truncatingRemainder(dividingBy: rhs)
        }
        return kk_box_float(kk_float_to_bits(result))
    }
    let lhs = Double(left)
    let rhs = kk_bits_to_double(kk_unbox_double(values[1]))
    if operation == 5 {
        return kk_box_int(rhs.isNaN ? -1 : lhs < rhs ? -1 : lhs > rhs ? 1 : (lhs == 0 && rhs.sign == .minus ? 1 : 0))
    }
    let result: Double
    switch operation {
    case 0: result = lhs + rhs
    case 1: result = lhs - rhs
    case 2: result = lhs * rhs
    case 3: result = lhs / rhs
    default: result = lhs.truncatingRemainder(dividingBy: rhs)
    }
    return kk_box_double_nonnull(kk_double_to_bits(result))
}

private func invokeBuiltinIntArithmetic(_ member: Int, values: [Int], outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let operation = (member - 100) / 8
    let operandKind = (member - 100) % 8
    let lhs = Int32(truncatingIfNeeded: kk_unbox_int(values[0]))
    if operandKind <= 2 {
        let rhs = Int32(truncatingIfNeeded: kk_unbox_int(values[1]))
        if (operation == 3 || operation == 4) && rhs == 0 {
            outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
            return runtimeNullSentinelInt
        }
        let result: Int32
        switch operation {
        case 0: result = lhs &+ rhs
        case 1: result = lhs &- rhs
        case 2: result = lhs &* rhs
        case 3: result = lhs == .min && rhs == -1 ? .min : lhs / rhs
        case 4: result = lhs == .min && rhs == -1 ? 0 : lhs % rhs
        default: result = lhs < rhs ? -1 : lhs > rhs ? 1 : 0
        }
        return kk_box_int(Int(result))
    }
    if operandKind == 3 {
        let left = Int64(lhs)
        let rhs = Int64(kk_unbox_long(values[1]))
        if (operation == 3 || operation == 4) && rhs == 0 {
            outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
            return runtimeNullSentinelInt
        }
        if operation == 5 { return kk_box_int(left < rhs ? -1 : left > rhs ? 1 : 0) }
        let result: Int64
        switch operation {
        case 0: result = left &+ rhs
        case 1: result = left &- rhs
        case 2: result = left &* rhs
        case 3: result = left == .min && rhs == -1 ? .min : left / rhs
        default: result = left == .min && rhs == -1 ? 0 : left % rhs
        }
        return kk_box_long_nonnull(Int(result))
    }
    if operandKind == 4 {
        let left = Float(lhs)
        let rhs = kk_bits_to_float(kk_unbox_float(values[1]))
        if operation == 5 {
            let result = rhs.isNaN ? -1 : left < rhs ? -1 : left > rhs ? 1 : (left == 0 && rhs.sign == .minus ? 1 : 0)
            return kk_box_int(result)
        }
        let result: Float
        switch operation {
        case 0: result = left + rhs
        case 1: result = left - rhs
        case 2: result = left * rhs
        case 3: result = left / rhs
        default: result = left.truncatingRemainder(dividingBy: rhs)
        }
        return kk_box_float(kk_float_to_bits(result))
    }
    let left = Double(lhs)
    let rhs = kk_bits_to_double(kk_unbox_double(values[1]))
    if operation == 5 {
        let result = rhs.isNaN ? -1 : left < rhs ? -1 : left > rhs ? 1 : (left == 0 && rhs.sign == .minus ? 1 : 0)
        return kk_box_int(result)
    }
    let result: Double
    switch operation {
    case 0: result = left + rhs
    case 1: result = left - rhs
    case 2: result = left * rhs
    case 3: result = left / rhs
    default: result = left.truncatingRemainder(dividingBy: rhs)
    }
    return kk_box_double_nonnull(kk_double_to_bits(result))
}

// Primitive types have no lowered class declaration. Register their real Any
// members here; type-specific operations require separate metadata.
func ensureBuiltinPrimitiveMembers(_ kclassRaw: Int) {
    guard let box = runtimeKClassBox(from: kclassRaw) else { return }
    let token = Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask
    let name: String
    switch token {
    case RuntimeTypeTokenEncoding.anyBase: name = "Any"
    case RuntimeTypeTokenEncoding.intBase: name = "Int"
    case RuntimeTypeTokenEncoding.longBase: name = "Long"
    case RuntimeTypeTokenEncoding.shortBase: name = "Short"
    case RuntimeTypeTokenEncoding.byteBase: name = "Byte"
    case RuntimeTypeTokenEncoding.floatBase: name = "Float"
    case RuntimeTypeTokenEncoding.doubleBase: name = "Double"
    case RuntimeTypeTokenEncoding.booleanBase: name = "Boolean"
    case RuntimeTypeTokenEncoding.charBase: name = "Char"
    case RuntimeTypeTokenEncoding.uintBase: name = "UInt"
    case RuntimeTypeTokenEncoding.ulongBase: name = "ULong"
    case RuntimeTypeTokenEncoding.ubyteBase: name = "UByte"
    case RuntimeTypeTokenEncoding.ushortBase: name = "UShort"
    case RuntimeTypeTokenEncoding.unitBase: name = "Unit"
    default: return
    }
    builtinPrimitiveMemberLock.lock()
    defer { builtinPrimitiveMemberLock.unlock() }
    guard !runtimeKMemberRegistry.builtinMembersInitialized(for: kclassRaw) else { return }

    func type(_ name: String, _ token: Int64) -> Int {
        let rawName = runtimeMakeStringRaw(name)
        let classifier = __kk_kclass_create(Int(token & ~RuntimeTypeTokenEncoding.nullableBit), rawName)
        return registerRuntimeObject(RuntimeKTypeBox(
            classifierRaw: classifier, argumentRaws: [],
            isMarkedNullable: token & RuntimeTypeTokenEncoding.nullableBit != 0, typeNameRaw: rawName
        ))
    }
    let invoke: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = invokeBuiltinPrimitiveMember
    let invoker = unsafeBitCast(invoke, to: Int.self)
    let emptyList = registerRuntimeObject(RuntimeListBox(elements: []))
    let receiverName = "kotlin.\(name)"
    for (index, functionName, resultName, resultToken) in [
        (0, "toString", "kotlin.String", RuntimeTypeTokenEncoding.stringBase),
        (1, "hashCode", "kotlin.Int", RuntimeTypeTokenEncoding.intBase),
        (2, "equals", "kotlin.Boolean", RuntimeTypeTokenEncoding.booleanBase),
    ] {
        let nameRaw = runtimeMakeStringRaw(functionName)
        let returnRaw = runtimeMakeStringRaw(resultName)
        let arity = index == 2 ? 2 : 1
        let flags = index == 2 ? 4 : 0
        let raw = __kk_kfunction_create(nameRaw, arity, returnRaw, flags, 0, 0)
        _ = kk_callable_ref_tag_kfunction(raw, nameRaw, returnRaw, arity, flags)
        let receiver = __kk_kparameter_create_typed(
            0, runtimeNullSentinelInt, runtimeMakeStringRaw(receiverName), 0, 0, Int(token), raw
        )
        runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = type(receiverName, token)
        var parameters = [receiver]
        if index == 2 {
            let anyNullable = RuntimeTypeTokenEncoding.anyBase | RuntimeTypeTokenEncoding.nullableBit
            let other = __kk_kparameter_create_typed(
                1, runtimeMakeStringRaw("other"), runtimeMakeStringRaw("kotlin.Any?"), 0, 2, Int(anyNullable), raw
            )
            runtimeKParameterBox(from: other)?.reflectedTypeRaw = type("kotlin.Any?", anyNullable)
            parameters.append(other)
        }
        let parameterList = registerRuntimeObject(RuntimeListBox(elements: parameters))
        _ = __kk_kcallable_register(raw, invoker, index, parameterList, emptyList, 1, 0, 0, 0)
        _ = __kk_kcallable_register_return_type(raw, type(resultName, resultToken))
        _ = __kk_kclass_register_member(kclassRaw, raw)
    }
    if token == RuntimeTypeTokenEncoding.intBase || token == RuntimeTypeTokenEncoding.byteBase
        || token == RuntimeTypeTokenEncoding.shortBase || token == RuntimeTypeTokenEncoding.longBase {
        let operandTypes: [(String, Int64)] = [
            ("Byte", RuntimeTypeTokenEncoding.byteBase), ("Short", RuntimeTypeTokenEncoding.shortBase),
            ("Int", RuntimeTypeTokenEncoding.intBase), ("Long", RuntimeTypeTokenEncoding.longBase),
            ("Float", RuntimeTypeTokenEncoding.floatBase), ("Double", RuntimeTypeTokenEncoding.doubleBase),
        ]
        for (operation, functionName) in ["plus", "minus", "times", "div", "rem", "compareTo"].enumerated() {
            for (kind, (operandName, operandToken)) in operandTypes.enumerated() {
                let isLongResult = token == RuntimeTypeTokenEncoding.longBase && kind <= 3 && operation != 5
                let resultToken = operation == 5 ? RuntimeTypeTokenEncoding.intBase
                    : isLongResult ? RuntimeTypeTokenEncoding.longBase
                    : kind <= 2 ? RuntimeTypeTokenEncoding.intBase : operandToken
                let resultName = operation == 5 ? "Int" : isLongResult ? "Long" : kind <= 2 ? "Int" : operandName
                let nameRaw = runtimeMakeStringRaw(functionName)
                let resultRaw = runtimeMakeStringRaw("kotlin.\(resultName)")
                let raw = __kk_kfunction_create(nameRaw, 2, resultRaw, 4, 0, 0)
                _ = kk_callable_ref_tag_kfunction(raw, nameRaw, resultRaw, 2, 4)
                let receiver = __kk_kparameter_create_typed(0, runtimeNullSentinelInt, runtimeMakeStringRaw(receiverName), 0, 0, Int(token), raw)
                runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = type(receiverName, token)
                let operandTypeName = "kotlin.\(operandName)"
                let other = __kk_kparameter_create_typed(1, runtimeMakeStringRaw("other"), runtimeMakeStringRaw(operandTypeName), 0, 2, Int(operandToken), raw)
                runtimeKParameterBox(from: other)?.reflectedTypeRaw = type(operandTypeName, operandToken)
                let parameters = registerRuntimeObject(RuntimeListBox(elements: [receiver, other]))
                let memberBase = token == RuntimeTypeTokenEncoding.longBase ? 700 : 100
                _ = __kk_kcallable_register(raw, invoker, memberBase + operation * 8 + kind, parameters, emptyList, 1, 0, 0, 0)
                _ = __kk_kcallable_register_return_type(raw, type("kotlin.\(resultName)", resultToken))
                _ = __kk_kclass_register_member(kclassRaw, raw)
            }
        }
        func addIntMember(
            _ functionName: String, resultName: String, resultToken: Int64,
            operand: (name: String, type: String, token: Int64)? = nil, member: Int, flags: Int
        ) {
            let nameRaw = runtimeMakeStringRaw(functionName)
            let resultRaw = runtimeMakeStringRaw(resultName)
            let raw = __kk_kfunction_create(nameRaw, operand == nil ? 1 : 2, resultRaw, flags, 0, 0)
            _ = kk_callable_ref_tag_kfunction(raw, nameRaw, resultRaw, operand == nil ? 1 : 2, flags)
            let receiver = __kk_kparameter_create_typed(0, runtimeNullSentinelInt, runtimeMakeStringRaw(receiverName), 0, 0, Int(token), raw)
            runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = type(receiverName, token)
            var parameters = [receiver]
            if let operand {
                let other = __kk_kparameter_create_typed(1, runtimeMakeStringRaw(operand.name), runtimeMakeStringRaw(operand.type), 0, 2, Int(operand.token), raw)
                runtimeKParameterBox(from: other)?.reflectedTypeRaw = type(operand.type, operand.token)
                parameters.append(other)
            }
            let list = registerRuntimeObject(RuntimeListBox(elements: parameters))
            _ = __kk_kcallable_register(raw, invoker, member, list, emptyList, 1, 0, 0, 0)
            _ = __kk_kcallable_register_return_type(raw, type(resultName, resultToken))
            _ = __kk_kclass_register_member(kclassRaw, raw)
        }
        let unary: [(String, String, Int64)] = [
            ("unaryPlus", "Int", RuntimeTypeTokenEncoding.intBase), ("unaryMinus", "Int", RuntimeTypeTokenEncoding.intBase),
            ("inc", "Int", RuntimeTypeTokenEncoding.intBase), ("dec", "Int", RuntimeTypeTokenEncoding.intBase),
            ("inv", "Int", RuntimeTypeTokenEncoding.intBase), ("toByte", "Byte", RuntimeTypeTokenEncoding.byteBase),
            ("toShort", "Short", RuntimeTypeTokenEncoding.shortBase), ("toInt", "Int", RuntimeTypeTokenEncoding.intBase),
            ("toLong", "Long", RuntimeTypeTokenEncoding.longBase), ("toFloat", "Float", RuntimeTypeTokenEncoding.floatBase),
            ("toDouble", "Double", RuntimeTypeTokenEncoding.doubleBase), ("toChar", "Char", RuntimeTypeTokenEncoding.charBase),
        ]
        for (index, entry) in unary.enumerated() {
            let narrow = token == RuntimeTypeTokenEncoding.byteBase || token == RuntimeTypeTokenEncoding.shortBase
            if narrow && index == 4 { continue }
            let receiverResult = (narrow && (index == 2 || index == 3)) || (token == RuntimeTypeTokenEncoding.longBase && index < 5)
            let memberBase = token == RuntimeTypeTokenEncoding.byteBase ? 500 : token == RuntimeTypeTokenEncoding.shortBase ? 600 : token == RuntimeTypeTokenEncoding.longBase ? 800 : 200
            addIntMember(entry.0, resultName: receiverResult ? receiverName : "kotlin.\(entry.1)", resultToken: receiverResult ? token : entry.2, member: memberBase + index, flags: index < 4 ? 4 : 0)
        }
        if token == RuntimeTypeTokenEncoding.intBase || token == RuntimeTypeTokenEncoding.longBase {
            for (index, name) in ["and", "or", "xor", "shl", "shr", "ushr"].enumerated() {
                let operandToken = index < 3 ? token : RuntimeTypeTokenEncoding.intBase
                let operandType = index < 3 ? receiverName : "kotlin.Int"
                let memberBase = token == RuntimeTypeTokenEncoding.longBase ? 900 : 300
                addIntMember(name, resultName: receiverName, resultToken: token,
                             operand: (index < 3 ? "other" : "bitCount", operandType, operandToken), member: memberBase + index, flags: 8)
            }
        }
        for (operation, name) in ["rangeTo", "rangeUntil"].enumerated() {
            for (kind, (operandName, operandToken)) in operandTypes.prefix(4).enumerated() {
                let resultName = token == RuntimeTypeTokenEncoding.longBase || kind == 3 ? "kotlin.ranges.LongRange" : "kotlin.ranges.IntRange"
                let resultToken = (runtimeStableNominalTypeID(fqName: resultName) << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
                addIntMember(name, resultName: resultName, resultToken: resultToken,
                             operand: ("other", "kotlin.\(operandName)", operandToken), member: (token == RuntimeTypeTokenEncoding.longBase ? 1000 : 400) + operation * 4 + kind, flags: 4)
            }
        }
    }
    func addSpecificMember(
        _ functionName: String, resultName: String, resultToken: Int64,
        operand: (name: String, type: String, token: Int64)? = nil, member: Int, flags: Int
    ) {
        let functionNameRaw = runtimeMakeStringRaw(functionName)
        let resultRaw = runtimeMakeStringRaw(resultName)
        let raw = __kk_kfunction_create(functionNameRaw, operand == nil ? 1 : 2, resultRaw, flags, 0, 0)
        _ = kk_callable_ref_tag_kfunction(raw, functionNameRaw, resultRaw, operand == nil ? 1 : 2, flags)
        let receiver = __kk_kparameter_create_typed(0, runtimeNullSentinelInt, runtimeMakeStringRaw(receiverName), 0, 0, Int(token), raw)
        runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = type(receiverName, token)
        var parameters = [receiver]
        if let operand {
            let other = __kk_kparameter_create_typed(1, runtimeMakeStringRaw(operand.name), runtimeMakeStringRaw(operand.type), 0, 2, Int(operand.token), raw)
            runtimeKParameterBox(from: other)?.reflectedTypeRaw = type(operand.type, operand.token)
            parameters.append(other)
        }
        let list = registerRuntimeObject(RuntimeListBox(elements: parameters))
        _ = __kk_kcallable_register(raw, invoker, member, list, emptyList, 1, 0, 0, 0)
        _ = __kk_kcallable_register_return_type(raw, type(resultName, resultToken))
        _ = __kk_kclass_register_member(kclassRaw, raw)
    }
    if token == RuntimeTypeTokenEncoding.floatBase || token == RuntimeTypeTokenEncoding.doubleBase {
        let isDouble = token == RuntimeTypeTokenEncoding.doubleBase
        let operands: [(String, Int64)] = [
            ("Byte", RuntimeTypeTokenEncoding.byteBase), ("Short", RuntimeTypeTokenEncoding.shortBase),
            ("Int", RuntimeTypeTokenEncoding.intBase), ("Long", RuntimeTypeTokenEncoding.longBase),
            ("Float", RuntimeTypeTokenEncoding.floatBase), ("Double", RuntimeTypeTokenEncoding.doubleBase),
        ]
        for (operation, name) in ["plus", "minus", "times", "div", "rem", "compareTo"].enumerated() {
            for (kind, operand) in operands.enumerated() {
                let resultToken = operation == 5 ? RuntimeTypeTokenEncoding.intBase
                    : isDouble || kind == 5 ? RuntimeTypeTokenEncoding.doubleBase : RuntimeTypeTokenEncoding.floatBase
                let resultName = operation == 5 ? "kotlin.Int"
                    : isDouble || kind == 5 ? "kotlin.Double" : "kotlin.Float"
                addSpecificMember(name, resultName: resultName, resultToken: resultToken,
                                  operand: ("other", "kotlin.\(operand.0)", operand.1),
                                  member: (isDouble ? 1900 : 1800) + operation * 8 + kind, flags: 4)
            }
        }
        let unary: [(String, String, Int64)] = [
            ("unaryPlus", name, token), ("unaryMinus", name, token), ("inc", name, token), ("dec", name, token),
            ("toByte", "Byte", RuntimeTypeTokenEncoding.byteBase), ("toShort", "Short", RuntimeTypeTokenEncoding.shortBase),
            ("toInt", "Int", RuntimeTypeTokenEncoding.intBase), ("toLong", "Long", RuntimeTypeTokenEncoding.longBase),
            ("toFloat", "Float", RuntimeTypeTokenEncoding.floatBase), ("toDouble", "Double", RuntimeTypeTokenEncoding.doubleBase),
            ("toChar", "Char", RuntimeTypeTokenEncoding.charBase),
        ]
        for (index, entry) in unary.enumerated() {
            addSpecificMember(entry.0, resultName: "kotlin.\(entry.1)", resultToken: entry.2,
                              member: (isDouble ? 2100 : 2000) + index, flags: index < 4 ? 4 : 0)
        }
    }
    if token == RuntimeTypeTokenEncoding.booleanBase {
        let boolean = (name: "other", type: "kotlin.Boolean", token: token)
        addSpecificMember("compareTo", resultName: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase, operand: boolean, member: 1400, flags: 4)
        addSpecificMember("not", resultName: receiverName, resultToken: token, member: 1401, flags: 4)
        for (index, name) in ["and", "or", "xor"].enumerated() {
            addSpecificMember(name, resultName: receiverName, resultToken: token, operand: boolean, member: 1402 + index, flags: 8)
        }
    }
    if token == RuntimeTypeTokenEncoding.charBase {
        let char = (name: "other", type: "kotlin.Char", token: token)
        let int = (name: "other", type: "kotlin.Int", token: RuntimeTypeTokenEncoding.intBase)
        addSpecificMember("compareTo", resultName: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase, operand: char, member: 1500, flags: 4)
        addSpecificMember("inc", resultName: receiverName, resultToken: token, member: 1501, flags: 4)
        addSpecificMember("dec", resultName: receiverName, resultToken: token, member: 1502, flags: 4)
        addSpecificMember("minus", resultName: "kotlin.Int", resultToken: RuntimeTypeTokenEncoding.intBase, operand: char, member: 1503, flags: 4)
        addSpecificMember("minus", resultName: receiverName, resultToken: token, operand: int, member: 1504, flags: 4)
        addSpecificMember("plus", resultName: receiverName, resultToken: token, operand: int, member: 1505, flags: 4)
        let rangeName = "kotlin.ranges.CharRange"
        let rangeToken = (runtimeStableNominalTypeID(fqName: rangeName) << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        addSpecificMember("rangeTo", resultName: rangeName, resultToken: rangeToken, operand: char, member: 1506, flags: 4)
        addSpecificMember("rangeUntil", resultName: rangeName, resultToken: rangeToken, operand: char, member: 1507, flags: 4)
        let conversions: [(String, String, Int64)] = [
            ("toByte", "Byte", RuntimeTypeTokenEncoding.byteBase), ("toChar", "Char", token),
            ("toDouble", "Double", RuntimeTypeTokenEncoding.doubleBase), ("toFloat", "Float", RuntimeTypeTokenEncoding.floatBase),
            ("toInt", "Int", RuntimeTypeTokenEncoding.intBase), ("toLong", "Long", RuntimeTypeTokenEncoding.longBase),
            ("toShort", "Short", RuntimeTypeTokenEncoding.shortBase),
        ]
        for (index, conversion) in conversions.enumerated() {
            addSpecificMember(conversion.0, resultName: "kotlin.\(conversion.1)", resultToken: conversion.2, member: 1508 + index, flags: 0)
        }
    }
    let unsignedKind: Int? = switch token {
    case RuntimeTypeTokenEncoding.ubyteBase: 0
    case RuntimeTypeTokenEncoding.ushortBase: 1
    case RuntimeTypeTokenEncoding.uintBase: 2
    case RuntimeTypeTokenEncoding.ulongBase: 3
    default: nil
    }
    if let kind = unsignedKind {
        let operands: [(String, Int64)] = [
            ("UByte", RuntimeTypeTokenEncoding.ubyteBase), ("UShort", RuntimeTypeTokenEncoding.ushortBase),
            ("UInt", RuntimeTypeTokenEncoding.uintBase), ("ULong", RuntimeTypeTokenEncoding.ulongBase),
        ]
        for (operation, functionName) in ["plus", "minus", "times", "div", "rem", "compareTo", "floorDiv", "mod"].enumerated() {
            for (otherKind, other) in operands.enumerated() {
                let resultToken = operation == 5 ? RuntimeTypeTokenEncoding.intBase
                    : kind == 3 || otherKind == 3 ? RuntimeTypeTokenEncoding.ulongBase : RuntimeTypeTokenEncoding.uintBase
                let resultName = operation == 5 ? "kotlin.Int"
                    : kind == 3 || otherKind == 3 ? "kotlin.ULong" : "kotlin.UInt"
                addSpecificMember(functionName, resultName: resultName, resultToken: resultToken,
                                  operand: ("other", "kotlin.\(other.0)", other.1),
                                  member: 3000 + kind * 100 + operation * 8 + otherKind,
                                  flags: operation >= 6 ? 2 : 6)
            }
        }
        let unary: [(String, String, Int64)] = [
            ("inc", name, token), ("dec", name, token), ("inv", name, token),
            ("toByte", "Byte", RuntimeTypeTokenEncoding.byteBase), ("toShort", "Short", RuntimeTypeTokenEncoding.shortBase),
            ("toInt", "Int", RuntimeTypeTokenEncoding.intBase), ("toLong", "Long", RuntimeTypeTokenEncoding.longBase),
            ("toFloat", "Float", RuntimeTypeTokenEncoding.floatBase), ("toDouble", "Double", RuntimeTypeTokenEncoding.doubleBase),
            ("toUByte", "UByte", RuntimeTypeTokenEncoding.ubyteBase), ("toUShort", "UShort", RuntimeTypeTokenEncoding.ushortBase),
            ("toUInt", "UInt", RuntimeTypeTokenEncoding.uintBase), ("toULong", "ULong", RuntimeTypeTokenEncoding.ulongBase),
        ]
        for (index, entry) in unary.enumerated() {
            addSpecificMember(entry.0, resultName: "kotlin.\(entry.1)", resultToken: entry.2,
                              member: 4000 + kind * 100 + index, flags: index < 2 ? 6 : 2)
        }
        let bitwise = kind >= 2 ? ["and", "or", "xor", "shl", "shr"] : ["and", "or", "xor"]
        for (index, functionName) in bitwise.enumerated() {
            let operand = index < 3 ? (name: "other", type: receiverName, token: token)
                : (name: "bitCount", type: "kotlin.Int", token: RuntimeTypeTokenEncoding.intBase)
            addSpecificMember(functionName, resultName: receiverName, resultToken: token, operand: operand,
                              member: 5000 + kind * 100 + index, flags: 10)
        }
        let rangeName = kind == 3 ? "kotlin.ranges.ULongRange" : "kotlin.ranges.UIntRange"
        let rangeToken = (runtimeStableNominalTypeID(fqName: rangeName) << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        for (index, functionName) in ["rangeTo", "rangeUntil"].enumerated() {
            addSpecificMember(functionName, resultName: rangeName, resultToken: rangeToken,
                              operand: ("other", receiverName, token), member: 6000 + kind * 100 + index, flags: 6)
        }
    }
    let unsignedData: (type: String, token: Int64, member: Int)? = switch token {
    case RuntimeTypeTokenEncoding.uintBase: ("Int", RuntimeTypeTokenEncoding.intBase, 3)
    case RuntimeTypeTokenEncoding.ubyteBase: ("Byte", RuntimeTypeTokenEncoding.byteBase, 4)
    case RuntimeTypeTokenEncoding.ushortBase: ("Short", RuntimeTypeTokenEncoding.shortBase, 5)
    case RuntimeTypeTokenEncoding.ulongBase: ("Long", RuntimeTypeTokenEncoding.longBase, 6)
    default: nil
    }
    if let unsignedData {
        let nameRaw = runtimeMakeStringRaw("data")
        let dataTypeName = "kotlin.\(unsignedData.type)"
        let dataTypeRaw = runtimeMakeStringRaw(dataTypeName)
        let property = kk_kproperty_stub_create_cached_typed(
            nameRaw, dataTypeRaw, runtimeMakeStringRaw("kotlin.\(name).data"), 0, 1, 0
        )
        _ = kk_callable_ref_tag_kproperty(property, nameRaw, dataTypeRaw, 1)
        _ = kk_object_register_itable_iface(property, Int(kProperty1RuntimeTypeID), 1)
        _ = kk_object_register_itable_method(property, 1, 0, unsafeBitCast(builtinUnsignedDataGet, to: Int.self))
        _ = kk_object_register_itable_method(property, 1, 1, unsafeBitCast(builtinUIntDataDelegate, to: Int.self))
        _ = kk_object_register_itable_method(property, 1, 2, unsafeBitCast(builtinUnsignedDataGet, to: Int.self))
        let receiver = __kk_kparameter_create_typed(
            0, runtimeNullSentinelInt, runtimeMakeStringRaw(receiverName), 0, 0, Int(token), property
        )
        runtimeKParameterBox(from: receiver)?.reflectedTypeRaw = type(receiverName, token)
        let parameters = registerRuntimeObject(RuntimeListBox(elements: [receiver]))
        _ = __kk_kcallable_register(property, invoker, unsignedData.member, parameters, emptyList, 1, 2, 0, 0)
        _ = __kk_kcallable_register_return_type(property, type(dataTypeName, unsignedData.token))
        _ = __kk_kclass_register_member(kclassRaw, property)
    }
    runtimeKMemberRegistry.markBuiltinMembersInitialized(for: kclassRaw)
}
