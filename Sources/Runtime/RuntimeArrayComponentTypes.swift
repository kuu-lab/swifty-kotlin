import Foundation

/// JVM-style reference-array component classifiers. These IDs contain only
/// type descriptors, never Kotlin handles; GC roots and object identity are
/// independent. Interning permits recursive arrays without truncating tokens.
private struct RuntimeArrayComponentType: Hashable {
    let classifier: Int
    let element: Int
}

private final class RuntimeArrayComponentTypes: @unchecked Sendable {
    let lock = NSLock()
    var nextID = 1
    var ids: [RuntimeArrayComponentType: Int] = [:]
    var types: [Int: RuntimeArrayComponentType] = [:]

    func intern(classifier: Int, element: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let classifier = classifier & ~Int(RuntimeTypeTokenEncoding.nullableBit)
        guard classifier & Int(RuntimeTypeTokenEncoding.baseMask) != 0,
              element == 0 || types[element] != nil else { return 0 }
        let base = Int64(classifier) & RuntimeTypeTokenEncoding.baseMask
        let payload = (Int64(classifier) >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
        // An erased Array classifier without its child cannot prove a nested
        // component. Fail closed until a concrete allocation tag is available.
        if base == RuntimeTypeTokenEncoding.nominalBase,
           payload == runtimeStableNominalTypeID(fqName: "kotlin.Array"), element == 0 { return 0 }
        let descriptor = RuntimeArrayComponentType(classifier: classifier, element: element)
        if let existing = ids[descriptor] { return existing }
        let id = nextID
        nextID += 1
        ids[descriptor] = id
        types[id] = descriptor
        return id
    }

    func descriptor(_ id: Int) -> RuntimeArrayComponentType? {
        lock.lock()
        defer { lock.unlock() }
        return types[id]
    }
}

private let runtimeArrayComponentTypes = RuntimeArrayComponentTypes()

func runtimeJavaArrayClassName(rawValue: Int) -> String? {
    guard let array = runtimeArrayBoxExcludingObjects(from: rawValue) else { return nil }

    if let kind = runtimePrimitiveArrayElementKind(rawValue: rawValue) {
        let descriptor: String = switch kind {
        case .boolean: "Z"
        case .byte, .uByte: "B"
        case .char: "C"
        case .double: "D"
        case .float: "F"
        case .int, .uInt: "I"
        case .long, .uLong: "J"
        case .short, .uShort: "S"
        }
        return "[\(descriptor)"
    }

    let arrayTypeID = runtimeStableNominalTypeID(fqName: "kotlin.Array")
    guard runtimeArrayTypeIDs(rawValue: rawValue).contains(arrayTypeID) else { return nil }
    let component = array.componentType.flatMap(runtimeJavaArrayComponentDescriptor)
        ?? "Ljava.lang.Object;"
    return "[\(component)"
}

private func runtimeJavaArrayComponentDescriptor(_ componentID: Int) -> String? {
    guard let component = runtimeArrayComponentTypes.descriptor(componentID) else { return nil }
    let token = Int64(truncatingIfNeeded: component.classifier)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    if base == RuntimeTypeTokenEncoding.nominalBase,
       payload == runtimeStableNominalTypeID(fqName: "kotlin.Array")
    {
        let element = component.element == 0
            ? "Ljava.lang.Object;"
            : runtimeJavaArrayComponentDescriptor(component.element) ?? "Ljava.lang.Object;"
        return "[\(element)"
    }

    let qualifiedName = runtimeJavaQualifiedName(typeToken: component.classifier)
    if let primitiveArrayDescriptor = runtimeJavaPrimitiveArrayDescriptor(qualifiedName) {
        return "[\(primitiveArrayDescriptor)"
    }
    return "L\(runtimeJavaBinaryNameForTypeToken(component.classifier));"
}

private func runtimeJavaPrimitiveArrayDescriptor(_ qualifiedName: String) -> String? {
    switch qualifiedName {
    case "kotlin.BooleanArray": "Z"
    case "kotlin.ByteArray", "kotlin.UByteArray": "B"
    case "kotlin.CharArray": "C"
    case "kotlin.DoubleArray": "D"
    case "kotlin.FloatArray": "F"
    case "kotlin.IntArray", "kotlin.UIntArray": "I"
    case "kotlin.LongArray", "kotlin.ULongArray": "J"
    case "kotlin.ShortArray", "kotlin.UShortArray": "S"
    default: nil
    }
}

@_cdecl("__kk_array_component_type")
public func __kk_array_component_type(_ classifier: Int, _ element: Int) -> Int {
    runtimeArrayComponentTypes.intern(classifier: classifier, element: element)
}

/// Whether `id` names a live interned component descriptor.
func runtimeArrayComponentDescriptorIsValid(_ id: Int) -> Bool {
    runtimeArrayComponentTypes.descriptor(id) != nil
}

/// `T::class` on a reified type parameter is passed the component descriptor
/// of T itself. When T resolves to `Array<E>` the KClass identity is E's
/// descriptor — the descriptor's element slot — so `T::class` and
/// `Array<E>::class` intern to the same box. A non-array T carries no element
/// identity: return 0 so the caller falls back to the erased classifier box.
@_cdecl("__kk_array_component_element")
public func __kk_array_component_element(_ component: Int) -> Int {
    guard let descriptor = runtimeArrayComponentTypes.descriptor(component) else { return 0 }
    let token = Int64(truncatingIfNeeded: descriptor.classifier)
    guard token & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.nominalBase,
          (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
            == runtimeStableNominalTypeID(fqName: "kotlin.Array")
    else { return 0 }
    return descriptor.element
}

/// Set at allocation, never widened by casts or a less precise return type.
/// Untagged runtime arrays cannot acquire a component by reflection invocation.
@_cdecl("__kk_array_tag_component")
public func __kk_array_tag_component(_ arrayRaw: Int, _ component: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw),
          runtimeArrayComponentTypes.descriptor(component) != nil else { return arrayRaw }
    array.installComponentTypeIfAbsent(component)
    return arrayRaw
}

@_cdecl("__kk_kparameter_set_array_component")
public func __kk_kparameter_set_array_component(_ parameterRaw: Int, _ component: Int) -> Int {
    guard let parameter = runtimeReflectionObject(from: parameterRaw, as: RuntimeKParameterBox.self),
          parameter.isVararg else { return parameterRaw }
    // Unknown/cyclic declaration metadata must remain an explicit rejecting
    // sentinel. Leaving nil would skip component checking during invocation.
    parameter.arrayComponentType = runtimeArrayComponentTypes.descriptor(component) != nil ? component : 0
    return parameterRaw
}

func runtimeArrayComponentIsAssignable(_ source: Int, to target: Int) -> Bool {
    guard let source = runtimeArrayComponentTypes.descriptor(source),
          let target = runtimeArrayComponentTypes.descriptor(target) else { return false }
    let mask = Int(RuntimeTypeTokenEncoding.baseMask)
    let sourceBase = source.classifier & mask
    let targetBase = target.classifier & mask
    if targetBase == Int(RuntimeTypeTokenEncoding.anyBase) { return true }
    if source.element != 0 || target.element != 0 {
        return source.element != 0 && target.element != 0
            && source.classifier == target.classifier
            && runtimeArrayComponentIsAssignable(source.element, to: target.element)
    }
    if source.classifier == target.classifier { return true }
    guard targetBase == Int(RuntimeTypeTokenEncoding.nominalBase) else { return false }
    func payload(_ token: Int) -> Int64 {
        (Int64(token) >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    }
    let sourceID: Int64
    if sourceBase == Int(RuntimeTypeTokenEncoding.nominalBase) {
        sourceID = payload(source.classifier)
    } else {
        let names: [Int: String] = [
            1: "Any", 2: "String", 3: "Int", 4: "Boolean", 7: "UInt", 8: "ULong",
            9: "UByte", 10: "UShort", 11: "Long", 12: "Double", 13: "Float",
            14: "Char", 15: "Unit", 16: "Byte", 17: "Short",
        ]
        guard let name = names[sourceBase] else { return false }
        sourceID = runtimeStableNominalTypeID(fqName: "kotlin.\(name)")
        // Builtin source shells may have no allocation site. Register these
        // erasure edges independently of whether the array has any elements.
        if sourceBase == 2 {
            runtimeRegisterTypeEdge(childTypeID: sourceID, parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        }
        if [3, 11, 12, 13, 16, 17].contains(sourceBase) {
            runtimeRegisterTypeEdge(childTypeID: sourceID, parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Number"))
        }
        if [2, 3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17].contains(sourceBase) {
            runtimeRegisterTypeEdge(childTypeID: sourceID, parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Comparable"))
        }
    }
    return runtimeIsAssignable(sourceTypeID: sourceID, targetTypeID: payload(target.classifier))
}

func runtimeArrayHasAssignableComponent(rawValue: Int, targetComponent: Int) -> Bool {
    guard let array = runtimeArrayBoxExcludingObjects(from: rawValue),
          let target = runtimeArrayComponentTypes.descriptor(targetComponent)
    else { return false }
    // Missing metadata cannot prove a narrower component from the contents.
    guard let sourceComponent = array.componentType else {
        let targetBase = target.classifier & Int(RuntimeTypeTokenEncoding.baseMask)
        return target.element == 0 && targetBase == Int(RuntimeTypeTokenEncoding.anyBase)
    }
    return runtimeArrayComponentIsAssignable(sourceComponent, to: targetComponent)
}

func runtimeArrayElementIsAssignable(
    _ value: RuntimeValue,
    sourceComponent: Int?,
    to targetComponent: Int?
) -> Bool {
    let rawValue = value.legacyRawValue
    if rawValue == runtimeNullSentinelInt { return true }
    guard let targetComponent,
          let target = runtimeArrayComponentTypes.descriptor(targetComponent) else { return false }

    let hasObjectIdentity = UnsafeMutableRawPointer(bitPattern: rawValue).map(runtimeIsObjectPointer) ?? false
    let targetBase = Int64(target.classifier) & RuntimeTypeTokenEncoding.baseMask
    if !hasObjectIdentity {
        // Unboxed values have no dynamic class pointer. Use the source array's
        // component as their JVM wrapper identity instead of kk_op_is, whose
        // primitive checks intentionally accept unboxed words without knowing
        // whether they came from Int, Long, Char, or another primitive.
        if targetBase == RuntimeTypeTokenEncoding.anyBase { return true }
        guard let sourceComponent,
              runtimeArrayComponentIsAssignable(sourceComponent, to: targetComponent) else { return false }
        return true
    }

    if kk_op_is(rawValue, target.classifier) != 0 {
        guard target.element != 0 else { return true }
        return runtimeArrayHasAssignableComponent(rawValue: rawValue, targetComponent: target.element)
    }

    return false
}

@_cdecl("__kk_array_new_same_component")
public func __kk_array_new_same_component(_ sourceRaw: Int, _ size: Int) -> Int {
    guard let source = runtimeArrayBox(from: sourceRaw), size >= 0 else { return runtimeNullSentinelInt }
    let result = kk_array_new(size)
    if let component = source.componentType {
        runtimeArrayBox(from: result)?.installComponentTypeIfAbsent(component)
    }
    for typeID in runtimeArrayTypeIDs(rawValue: sourceRaw) {
        runtimeRegisterArrayType(rawValue: result, typeID: typeID)
    }
    if let array = runtimeArrayBox(from: result) {
        array.elements = Array(repeating: runtimeNullSentinelInt, count: size)
    }
    return result
}
