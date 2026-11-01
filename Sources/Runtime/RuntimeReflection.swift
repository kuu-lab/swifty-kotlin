import Foundation


private let runtimeHiddenAnnotationFQNames: Set<String> = [
    "kotlin.Metadata",
]

private func runtimeShouldExposeAnnotation(fqName: String) -> Bool {
    !runtimeHiddenAnnotationFQNames.contains(fqName)
}

private extension RuntimeKClassBox {
    var reflectionSimpleName: String {
        if let metadata {
            return metadata.simpleName
        }
        if nameHint != 0,
           nameHint != runtimeNullSentinelInt,
           let hint = extractString(from: UnsafeMutableRawPointer(bitPattern: nameHint))
        {
            return hint
        }
        return ""
    }

    var reflectionQualifiedName: String {
        if let metadata {
            return metadata.isLocal ? "" : metadata.qualifiedName
        }
        let raw = __kk_type_token_qualified_name(typeToken, nameHint)
        let qualifiedName = extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
        if let qualifiedName, qualifiedName.contains(".") {
            return qualifiedName
        }
        let simpleName = reflectionSimpleName
        if let qualifiedName, !qualifiedName.isEmpty, qualifiedName != simpleName {
            return qualifiedName
        }
        if let stdlibQualifiedName = runtimeReflectionStdlibQualifiedName(for: simpleName) {
            return stdlibQualifiedName
        }
        return simpleName
    }
}

private func runtimeReflectionStdlibQualifiedName(for simpleName: String) -> String? {
    switch simpleName {
    case "Array":
        return "kotlin.Array"
    case "Iterable", "Collection", "MutableCollection", "List", "MutableList", "Set", "MutableSet", "Map", "MutableMap":
        return "kotlin.collections.\(simpleName)"
    case "Iterator", "MutableIterator":
        return "kotlin.collections.\(simpleName)"
    default:
        return nil
    }
}

/// `KClass.toString` renders the JVM classifier name for Kotlin platform
/// typealiases — `Nothing::class` is `Void::class` — while `qualifiedName`
/// keeps the registered Kotlin reflection name.
private func runtimeKClassToStringDisplayName(_ name: String) -> String {
    switch name {
    case "kotlin.Nothing":
        return "java.lang.Void"
    case "kotlin.RuntimeException":
        return "java.lang.RuntimeException"
    default:
        return name
    }
}

/// Renders class handles consistently across Any.toString, printing, and collections.
func runtimeKClassToString(_ box: RuntimeKClassBox) -> String {
    if let arrayName = runtimeArrayKClassQualifiedName(typeToken: box.typeToken) {
        return "class \(arrayName)"
    }
    let className = box.metadata.map { metadata in
        metadata.isLocal ? metadata.simpleName : (metadata.displayName ?? metadata.qualifiedName)
    } ?? box.reflectionQualifiedName
    return "class \(runtimeKClassToStringDisplayName(className))"
}


// (a) RF-DEAD-002: 配線予定 → STDLIB-REFLECT-067 (KClass.typeParameters.size)
public func __kk_kclass_get_arity(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeKClassBox(from: kclassRaw) else {
        return 0
    }
    return kclass.metadata?.typeParameterCount ?? 0
}


/// Returns the annotations list for a KClass as a RuntimeListBox.
/// Each element is a RuntimeAnnotationBox raw handle.
/// - Parameter kclassRaw: Opaque pointer to a RuntimeKClassBox.
/// - Returns: Opaque pointer to a RuntimeListBox of annotation handles.
@_cdecl("__kk_kclass_get_annotations")
public func __kk_kclass_get_annotations(_ kclassRaw: Int) -> Int {
    guard let kclass = runtimeKClassBox(from: kclassRaw),
          let metadata = kclass.metadata
    else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    return runtimeAnnotationList(metadata.annotations)
}

/// Distinguishes native KClass boxes from source implementations of KClass.
@_cdecl("__kk_kclass_is_runtime")
public func __kk_kclass_is_runtime(_ raw: Int) -> Int {
    runtimeKClassBox(from: raw) == nil ? 0 : 1
}

@_cdecl("__kk_kclass_get_annotations_typed")
public func __kk_kclass_get_annotations_typed(_ kclassRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let records = runtimeKClassBox(from: kclassRaw)?.metadata?.annotations ?? []
    return runtimeAnnotationList(records, materializeFactories: true, outThrown: outThrown)
}

func runtimeAnnotationValue(_ record: RuntimeAnnotationRecord, materializeFactory: Bool,
                            outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if materializeFactory, record.factory != 0 {
        return kk_function_invoke_0(record.factory, outThrown)
    }
    return registerRuntimeObject(RuntimeAnnotationBox(
        annotationFQName: record.annotationFQName, arguments: record.arguments, annotationClassRaw: 0
    ))
}

func runtimeAnnotationList(_ records: [RuntimeAnnotationRecord], materializeFactories: Bool = false,
                           outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    var annotationHandles: [Int] = []
    // Stable slots keep earlier results rooted while a later factory executes.
    let roots = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: max(1, records.count))
    roots.initialize(repeating: nil, count: max(1, records.count))
    defer {
        for index in annotationHandles.indices { kk_unregister_global_root(roots.advanced(by: index)) }
        roots.deinitialize(count: max(1, records.count))
        roots.deallocate()
    }
    for record in records where runtimeShouldExposeAnnotation(fqName: record.annotationFQName) {
        var thrown = 0
        let handle = runtimeAnnotationValue(record, materializeFactory: materializeFactories, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return runtimeNullSentinelInt
        }
        roots[annotationHandles.count] = UnsafeMutableRawPointer(bitPattern: handle)
        kk_register_global_root(roots.advanced(by: annotationHandles.count))
        annotationHandles.append(handle)
    }
    return registerRuntimeObject(RuntimeListBox(elements: annotationHandles))
}

func runtimeAnnotationArray(
    _ records: [RuntimeAnnotationRecord],
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let visibleRecords = records.filter { runtimeShouldExposeAnnotation(fqName: $0.annotationFQName) }
    let array = RuntimeArrayBox(length: visibleRecords.count)
    let annotationTypeID = runtimeStableNominalTypeID(fqName: "kotlin.Annotation")
    let annotationTypeToken = Int(
        ((annotationTypeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.nominalBase
    )
    array.installComponentTypeIfAbsent(__kk_array_component_type(annotationTypeToken, 0))
    let arrayRaw = registerRuntimeObject(array)
    runtimeRegisterArrayType(rawValue: arrayRaw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))

    let rootCapacity = max(1, visibleRecords.count + 1)
    let roots = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: rootCapacity)
    roots.initialize(repeating: nil, count: rootCapacity)
    var rootCount = 0
    defer {
        for index in 0..<rootCount { kk_unregister_global_root(roots.advanced(by: index)) }
        roots.deinitialize(count: rootCapacity)
        roots.deallocate()
    }

    roots[0] = UnsafeMutableRawPointer(bitPattern: arrayRaw)
    kk_register_global_root(roots)
    rootCount = 1
    for (index, record) in visibleRecords.enumerated() {
        var thrown = 0
        let handle = runtimeAnnotationValue(record, materializeFactory: true, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return runtimeNullSentinelInt
        }
        roots[rootCount] = UnsafeMutableRawPointer(bitPattern: handle)
        kk_register_global_root(roots.advanced(by: rootCount))
        rootCount += 1
        array[index] = handle
    }
    return arrayRaw
}

@_cdecl("__kk_kcallable_get_annotations_typed")
public func __kk_kcallable_get_annotations_typed(_ callableRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let records = runtimeStorage.withDelegateLock { $0.callableRefMetadataByValue[callableRaw]?.annotations ?? [] }
    return runtimeAnnotationList(records, materializeFactories: true, outThrown: outThrown)
}

@_cdecl("__kk_kcallable_register_annotation_factory")
public func __kk_kcallable_register_annotation_factory(
    _ callableRaw: Int, _ fqNameRaw: Int, _ argsEncodedRaw: Int, _ argCount: Int, _ factory: Int
) -> Int {
    let fqName = extractString(from: UnsafeMutableRawPointer(bitPattern: fqNameRaw)) ?? "Unknown"
    guard runtimeShouldExposeAnnotation(fqName: fqName) else { return 0 }
    let encoded = extractString(from: UnsafeMutableRawPointer(bitPattern: argsEncodedRaw)) ?? ""
    let record = RuntimeAnnotationRecord(annotationFQName: fqName,
        arguments: argCount > 0 && !encoded.isEmpty ? encoded.components(separatedBy: "|") : [], factory: factory)
    runtimeStorage.withDelegateLock { state in
        guard var metadata = state.callableRefMetadataByValue[callableRaw] else { return }
        runtimeAppendAnnotationRecord(record, to: &metadata.annotations)
        state.callableRefMetadataByValue[callableRaw] = metadata
    }
    return 0
}

@_cdecl("__kk_kcallable_register_single_annotation")
public func __kk_kcallable_register_single_annotation(
    _ callableRaw: Int, _ fqNameRaw: Int, _ argsEncodedRaw: Int, _ argCount: Int
) -> Int {
    let fqName = extractString(from: UnsafeMutableRawPointer(bitPattern: fqNameRaw)) ?? "Unknown"
    guard runtimeShouldExposeAnnotation(fqName: fqName) else { return 0 }
    let encoded = extractString(from: UnsafeMutableRawPointer(bitPattern: argsEncodedRaw)) ?? ""
    let arguments = argCount > 0 && !encoded.isEmpty ? encoded.components(separatedBy: "|") : []
    let record = RuntimeAnnotationRecord(annotationFQName: fqName, arguments: arguments)
    runtimeStorage.withDelegateLock { state in
        guard var metadata = state.callableRefMetadataByValue[callableRaw] else { return }
        runtimeAppendAnnotationRecord(record, to: &metadata.annotations)
        state.callableRefMetadataByValue[callableRaw] = metadata
    }
    return 0
}

@_cdecl("__kk_kclass_find_annotation_typed")
public func __kk_kclass_find_annotation_typed(
    _ kclassRaw: Int, _ typeToken: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let records = runtimeKClassBox(from: kclassRaw)?.metadata?.annotations else {
        return runtimeNullSentinelInt
    }
    for record in records where runtimeShouldExposeAnnotation(fqName: record.annotationFQName) {
        var thrown = 0
        let value = runtimeAnnotationValue(record, materializeFactory: true, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return runtimeNullSentinelInt
        }
        if kk_op_is(value, typeToken) != 0 { return value }
    }
    return runtimeNullSentinelInt
}

/// The current metadata pipeline records annotation arguments as strings, so
/// this returns null unless a future emitter stores a runtime object handle.
@_cdecl("__kk_kclass_find_associated_object")
public func __kk_kclass_find_associated_object(_ kclassRaw: Int, _ keyNameRaw: Int) -> Int {
    guard let kclass = runtimeKClassBox(from: kclassRaw),
          let metadata = kclass.metadata,
          let keyName = extractString(from: UnsafeMutableRawPointer(bitPattern: keyNameRaw))
    else {
        return runtimeNullSentinelInt
    }

    for record in metadata.annotations where runtimeShouldExposeAnnotation(fqName: record.annotationFQName) {
        let simpleName = record.annotationFQName.split(separator: ".").last.map(String.init) ?? record.annotationFQName
        guard record.annotationFQName == keyName || simpleName == keyName else {
            continue
        }
        return runtimeAssociatedObjectHandle(from: record.arguments)
    }
    return runtimeNullSentinelInt
}

private func runtimeAssociatedObjectHandle(from arguments: [String]) -> Int {
    for argument in arguments {
        if argument.hasPrefix("runtimeObjectRaw="),
           let raw = Int(argument.dropFirst("runtimeObjectRaw=".count))
        {
            return raw
        }
    }
    return runtimeNullSentinelInt
}

/// Called during module initialization (once per annotation) to attach compile-time
/// annotation data to the already-registered metadata entry.
/// - Parameters:
///   - typeToken: The type token identifying the type.
///   - fqNameRaw: Runtime string pointer for the annotation FQ name.
///   - argsEncodedRaw: Runtime string pointer for pipe-delimited argument values (empty string if none).
///   - argCount: Number of arguments encoded in the argsEncoded string.
@_cdecl("__kk_kclass_register_single_annotation")
public func __kk_kclass_register_single_annotation(
    _ typeToken: Int,
    _ fqNameRaw: Int,
    _ argsEncodedRaw: Int,
    _ argCount: Int
) -> Int {
    let fqName = extractString(from: UnsafeMutableRawPointer(bitPattern: fqNameRaw)) ?? "Unknown"
    guard runtimeShouldExposeAnnotation(fqName: fqName) else {
        return 0
    }

    var arguments: [String] = []
    if argCount > 0,
       let argsEncoded = extractString(from: UnsafeMutableRawPointer(bitPattern: argsEncodedRaw)),
       !argsEncoded.isEmpty
    {
        arguments = argsEncoded.components(separatedBy: "|")
    }

    let record = RuntimeAnnotationRecord(annotationFQName: fqName, arguments: arguments)
    runtimeKClassMetadataRegistry.appendAnnotations(typeToken: typeToken, annotations: [record])
    return 0
}

@_cdecl("__kk_kclass_register_annotation_factory")
public func __kk_kclass_register_annotation_factory(
    _ typeToken: Int, _ fqNameRaw: Int, _ argsEncodedRaw: Int, _ argCount: Int, _ factory: Int
) -> Int {
    let fqName = extractString(from: UnsafeMutableRawPointer(bitPattern: fqNameRaw)) ?? "Unknown"
    guard runtimeShouldExposeAnnotation(fqName: fqName) else { return 0 }
    let encoded = extractString(from: UnsafeMutableRawPointer(bitPattern: argsEncodedRaw)) ?? ""
    let record = RuntimeAnnotationRecord(annotationFQName: fqName,
        arguments: argCount > 0 && !encoded.isEmpty ? encoded.components(separatedBy: "|") : [], factory: factory)
    runtimeKClassMetadataRegistry.appendAnnotations(typeToken: typeToken, annotations: [record])
    return 0
}

// MARK: - KFunction Dynamic Call (STDLIB-REFLECT-067)

private func runtimeKFunctionBox(from raw: Int) -> RuntimeKFunctionBox? {
    resolveRuntimeHandle(raw, as: RuntimeKFunctionBox.self)
}


/// - Parameters:
///   - index: 0-based parameter index.
///   - nameRaw: KKString for the parameter name (0 if unnamed).
///   - typeRaw: KKString for the parameter type name.
///   - flags: RuntimeKParameterFlags bitmask — bit0 = isOptional
///     (has a default value), bit1 = isVararg.
///   - kind: internal kind encoding — 0 = INSTANCE, 1 = EXTENSION_RECEIVER,
///     2 = VALUE (see RuntimeKParameterBox.kind).
@_cdecl("__kk_kparameter_create")
public func __kk_kparameter_create(
    _ index: Int,
    _ nameRaw: Int,
    _ typeRaw: Int,
    _ flags: Int,
    _ kind: Int
) -> Int {
    let box = RuntimeKParameterBox(
        index: index,
        nameRaw: nameRaw,
        typeRaw: typeRaw,
        isOptional: flags & RuntimeKParameterFlags.isOptional != 0,
        kind: kind,
        isVararg: flags & RuntimeKParameterFlags.isVararg != 0
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kParameterRuntimeTypeID)
}

func runtimeKParameterBox(from raw: Int) -> RuntimeKParameterBox? {
    resolveRuntimeHandle(raw, as: RuntimeKParameterBox.self)
}

@_cdecl("__kk_kparameter_create_typed")
public func __kk_kparameter_create_typed(
    _ index: Int, _ nameRaw: Int, _ typeRaw: Int, _ flags: Int, _ kind: Int, _ typeToken: Int, _ callableOwner: Int = 0
) -> Int {
    let raw = __kk_kparameter_create(index, nameRaw, typeRaw, flags, kind)
    runtimeKParameterBox(from: raw)?.typeToken = typeToken
    runtimeKParameterBox(from: raw)?.callableOwner = callableOwner
    return raw
}

@_cdecl("__kk_kparameter_set_type")
public func __kk_kparameter_set_type(_ raw: Int, _ typeRaw: Int) -> Int {
    runtimeKParameterBox(from: raw)?.reflectedTypeRaw = typeRaw
    return 1
}

@_cdecl("__kk_kparameter_get_index")
public func __kk_kparameter_get_index(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.index
}

@_cdecl("__kk_kparameter_get_name")
public func __kk_kparameter_get_name(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.nameRaw
}

@_cdecl("__kk_kparameter_get_type")
public func __kk_kparameter_get_type(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return runtimeNullSentinelInt
    }
    return box.reflectedTypeRaw != 0 ? box.reflectedTypeRaw : box.typeRaw
}

@_cdecl("__kk_kparameter_is_optional")
public func __kk_kparameter_is_optional(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return 0
    }
    return box.isOptional ? 1 : 0
}

@_cdecl("__kk_kparameter_is_vararg")
public func __kk_kparameter_is_vararg(_ raw: Int) -> Int {
    guard let box = runtimeKParameterBox(from: raw) else {
        return 0
    }
    return box.isVararg ? 1 : 0
}

@_cdecl("__kk_kparameter_get_kind")
public func __kk_kparameter_get_kind(_ raw: Int) -> Int {
    // RuntimeKParameterBox.kind keeps the runtime's own ordering
    // (0 = INSTANCE, 1 = EXTENSION_RECEIVER, 2 = VALUE, 3 = CONTEXT);
    // Kotlin 2.3.10 declares KParameter.Kind as INSTANCE, CONTEXT,
    // EXTENSION_RECEIVER, VALUE, so the internal ordinals are
    // translated to the Kotlin declaration ordinals here at the ABI
    // boundary — the same split __kk_ktypeprojection_get_variance
    // uses for KVariance.
    switch runtimeKParameterBox(from: raw)?.kind ?? 2 {
    case 0: return 0  // INSTANCE
    case 1: return 2  // EXTENSION_RECEIVER
    case 3: return 1  // CONTEXT
    default: return 3 // VALUE
    }
}

/// Distinguishes native KParameter boxes from source implementations of
/// KParameter so `KAnnotatedElement.annotations` reads can bypass the
/// interface getter (KUU-4017).
@_cdecl("__kk_kparameter_is_runtime")
public func __kk_kparameter_is_runtime(_ raw: Int) -> Int {
    runtimeKParameterBox(from: raw) == nil ? 0 : 1
}

/// Returns the annotations list for a KParameter as a RuntimeListBox.
/// Parameter-annotation metadata is not yet emitted for runtime
/// KParameter boxes, so this returns an empty list; source-backed
/// KParameter implementations keep their own `annotations` through
/// interface dispatch.
@_cdecl("__kk_kparameter_get_annotations_typed")
public func __kk_kparameter_get_annotations_typed(_ raw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let records = runtimeKParameterBox(from: raw)?.annotations ?? []
    return runtimeAnnotationList(records, materializeFactories: true, outThrown: outThrown)
}

/// The owning callable's runtime handle for a `RuntimeKParameterBox`, when it
/// can be resolved. `__kk_kcallable_register` back-fills `callableRaw` for
/// compiler-emitted lists whose `callableOwner` is an encoded SymbolID;
/// runtime-created reflection members pass the callable's raw handle as
/// `callableOwner` directly, which is itself the handle.
func runtimeKParameterCallableRaw(_ box: RuntimeKParameterBox) -> Int {
    if box.callableRaw != 0 {
        return box.callableRaw
    }
    if resolveRuntimeObjectHandle(box.callableOwner) != nil {
        return box.callableOwner
    }
    return 0
}

/// Value equality for KParameter boxes, mirroring the JVM's
/// `ReflectKParameter.equals` (`callable == other.callable && index ==
/// other.index`). `callableOwner` is the callable's value identity — an
/// encoded SymbolID for compiler-emitted parameter lists, the owning
/// callable's handle for runtime-created reflection members — so two
/// `::f.parameters[i]` handles produced by separate evaluations of `::f`
/// compare equal. Bound callable references additionally compare their
/// captured arguments, the same components `runtimeCallableReferenceValuesEqual`
/// checks on the callable itself; `callBy`'s key-matching fallback
/// (`callableParameterMatches`) delegates here so both paths agree.
func runtimeKParameterBoxesEqual(_ lhs: RuntimeKParameterBox, _ rhs: RuntimeKParameterBox) -> Bool {
    guard lhs.callableOwner != 0,
          lhs.callableOwner == rhs.callableOwner,
          lhs.index == rhs.index,
          lhs.boundArguments.count == rhs.boundArguments.count
    else {
        return false
    }
    return zip(lhs.boundArguments, rhs.boundArguments)
        .allSatisfy { runtimeValuesEqual($0, $1) }
}

/// `ReflectKParameter.hashCode` = `callable.hashCode() * 31 + index`. The
/// callable side hashes the same identity token equality compares, so equal
/// parameters hash identically.
func runtimeKParameterHashCode(_ box: RuntimeKParameterBox) -> Int {
    var hash = Int32(truncatingIfNeeded: box.callableOwner ^ (box.callableOwner >> 32))
    for argument in box.boundArguments {
        hash = 31 &* hash &+ Int32(truncatingIfNeeded: runtimeValueHash(argument))
    }
    return Int(31 &* hash &+ Int32(truncatingIfNeeded: box.index))
}

/// `ReflectionObjectRenderer.renderParameter`: "<kind text> of <callable>".
/// The callable text reuses the JVM-shaped description already pinned on
/// callable references (`fun f(kotlin.Int): kotlin.Unit`) and property stubs
/// (`val C.v: kotlin.Int`), matching `renderCallable`.
func runtimeKParameterToString(_ box: RuntimeKParameterBox) -> String {
    let name: String? = box.nameRaw == 0 || box.nameRaw == runtimeNullSentinelInt
        ? nil
        : extractString(from: UnsafeMutableRawPointer(bitPattern: box.nameRaw))
    let head: String
    switch box.kind {
    case 0:
        head = "instance parameter"
    case 1:
        head = "extension receiver parameter"
    case 3:
        head = "context parameter \(name ?? "null")"
    default:
        head = "parameter #\(box.index) \(name ?? "null")"
    }
    guard let callable = runtimeKParameterCallableDescription(box) else {
        return head
    }
    return "\(head) of \(callable)"
}

private func runtimeKParameterCallableDescription(_ box: RuntimeKParameterBox) -> String? {
    let raw = runtimeKParameterCallableRaw(box)
    guard raw != 0 else { return nil }
    if let description = runtimeFunctionDescription(raw) {
        return description
    }
    if let stub = runtimeReflectionObject(from: raw, as: RuntimeKPropertyStub.self) {
        return runtimeKPropertyStubToString(stub)
    }
    if let function = runtimeKFunctionBox(from: raw),
       function.nameRaw != 0,
       function.nameRaw != runtimeNullSentinelInt,
       let name = extractString(from: UnsafeMutableRawPointer(bitPattern: function.nameRaw))
    {
        return "fun \(name)"
    }
    return nil
}


/// - Parameters:
///   - nameRaw: Opaque pointer to the KKString for the function name.
///   - arity: Number of parameters (excluding receiver for member functions).
///   - returnTypeRaw: Opaque pointer to the KKString for the return type (0 if unknown).
///   - flags: Packed modifier flags (bit0=suspend, bit1=inline, bit2=operator,
///            bit3=infix, bit4=external). Legacy callers pass 0/1 for suspend
///            which is compatible with the packed layout.
///   - fnPtr: C function pointer integer for direct dispatch (0 if unavailable).
///   - closureRaw: Closure environment pointer (0 for top-level functions).
@_cdecl("__kk_kfunction_create")
public func __kk_kfunction_create(
    _ nameRaw: Int,
    _ arity: Int,
    _ returnTypeRaw: Int,
    _ flags: Int,
    _ fnPtr: Int,
    _ closureRaw: Int
) -> Int {
    let box = RuntimeKFunctionBox(
        nameRaw: nameRaw,
        arity: arity,
        returnTypeRaw: returnTypeRaw,
        flags: flags,
        fnPtr: fnPtr,
        closureRaw: closureRaw
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kFunctionRuntimeTypeID)
}

/// - Parameters:
///   - nameRaw: KKString for the function name.
///   - arity: Number of value parameters.
///   - returnTypeRaw: KKString for the return type.
///   - flags: Packed modifier flags (see `__kk_kfunction_create`; bit0=suspend,
///            bit1=inline, bit2=operator, bit3=infix, bit4=external).
///   - fnPtr: C function pointer.
///   - closureRaw: Closure environment pointer.
///   - paramListRaw: Runtime list of KParameter handles (0 for empty).
///   - typeStringRaw: KKString for the function type signature (0 if unknown).
@_cdecl("__kk_kfunction_create_full")
public func __kk_kfunction_create_full(
    _ nameRaw: Int,
    _ arity: Int,
    _ returnTypeRaw: Int,
    _ flags: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ paramListRaw: Int,
    _ typeStringRaw: Int
) -> Int {
    var paramRaws: [Int] = []
    if paramListRaw != 0, paramListRaw != runtimeNullSentinelInt {
        let isValidPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: paramListRaw))
        }
        if isValidPtr,
           let ptr = UnsafeMutableRawPointer(bitPattern: paramListRaw),
           let listBox = tryCast(ptr, to: RuntimeListBox.self)
        {
            paramRaws = listBox.elements
        }
    }
    let box = RuntimeKFunctionBox(
        nameRaw: nameRaw,
        arity: arity,
        returnTypeRaw: returnTypeRaw,
        flags: flags,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        parameterRaws: paramRaws,
        typeStringRaw: typeStringRaw
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kFunctionRuntimeTypeID)
}

/// Resolves packed modifier flags for a handle that is either a
/// `RuntimeKFunctionBox` (class member reflection) or a callable-reference
/// object tagged via `kk_callable_ref_tag_kfunction` (KUU-1357).
private func runtimeKFunctionFlags(for raw: Int) -> Int {
    if let box = runtimeKFunctionBox(from: raw) {
        return box.flags
    }
    var flags = 0
    runtimeStorage.withDelegateLock { state in
        if let metadata = state.callableRefMetadataByValue[raw], metadata.kind == .function {
            flags = metadata.modifierFlags
            if metadata.isSuspend {
                flags |= RuntimeKFunctionFlags.suspend
            }
        }
    }
    return flags
}

@_cdecl("__kk_kfunction_is_suspend")
public func __kk_kfunction_is_suspend(_ kfunctionRaw: Int) -> Int {
    (runtimeKFunctionFlags(for: kfunctionRaw) & RuntimeKFunctionFlags.suspend) != 0 ? 1 : 0
}

@_cdecl("__kk_kfunction_is_inline")
public func __kk_kfunction_is_inline(_ kfunctionRaw: Int) -> Int {
    (runtimeKFunctionFlags(for: kfunctionRaw) & RuntimeKFunctionFlags.`inline`) != 0 ? 1 : 0
}

@_cdecl("__kk_kfunction_is_operator")
public func __kk_kfunction_is_operator(_ kfunctionRaw: Int) -> Int {
    (runtimeKFunctionFlags(for: kfunctionRaw) & RuntimeKFunctionFlags.`operator`) != 0 ? 1 : 0
}

@_cdecl("__kk_kfunction_is_infix")
public func __kk_kfunction_is_infix(_ kfunctionRaw: Int) -> Int {
    (runtimeKFunctionFlags(for: kfunctionRaw) & RuntimeKFunctionFlags.`infix`) != 0 ? 1 : 0
}

@_cdecl("__kk_kfunction_is_external")
public func __kk_kfunction_is_external(_ kfunctionRaw: Int) -> Int {
    (runtimeKFunctionFlags(for: kfunctionRaw) & RuntimeKFunctionFlags.`external`) != 0 ? 1 : 0
}

@_cdecl("__kk_kfunction_get_parameters")
public func __kk_kfunction_get_parameters(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.parameterRaws))
}

@_cdecl("__kk_kfunction_get_value_parameters")
public func __kk_kfunction_get_value_parameters(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    let valueParams = box.parameterRaws.filter { raw in
        guard let paramBox = runtimeKParameterBox(from: raw) else { return true }
        return paramBox.kind == 2 // VALUE
    }
    return registerRuntimeObject(RuntimeListBox(elements: valueParams))
}

@_cdecl("__kk_kfunction_get_type")
public func __kk_kfunction_get_type(_ kfunctionRaw: Int) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        return runtimeNullSentinelInt
    }
    if box.typeStringRaw != 0, box.typeStringRaw != runtimeNullSentinelInt {
        return box.typeStringRaw
    }
    if box.returnTypeRaw != 0, box.returnTypeRaw != runtimeNullSentinelInt {
        return box.returnTypeRaw
    }
    return runtimeNullSentinelInt
}


@_cdecl("__kk_kfunction_call_0")
public func __kk_kfunction_call_0(
    _ kfunctionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 0.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
        return fn(box.closureRaw, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKThunkEntryPoint.self)
        return fn(outThrown)
    }
}


@_cdecl("__kk_kfunction_call_1")
public func __kk_kfunction_call_1(
    _ kfunctionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 1 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 1.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return fn(box.closureRaw, arg, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint1.self)
        return fn(arg, outThrown)
    }
}


@_cdecl("__kk_kfunction_call_2")
public func __kk_kfunction_call_2(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 2 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 2.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return fn(box.closureRaw, arg1, arg2, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint2.self)
        return fn(arg1, arg2, outThrown)
    }
}


@_cdecl("__kk_kfunction_call_3")
public func __kk_kfunction_call_3(
    _ kfunctionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    guard box.arity == 3 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with 3.")
        return runtimeNullSentinelInt
    }
    guard box.fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction has no callable function pointer.")
        return runtimeNullSentinelInt
    }
    if box.closureRaw != 0 {
        let fn = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return fn(box.closureRaw, arg1, arg2, arg3, outThrown)
    } else {
        let fn = unsafeBitCast(box.fnPtr, to: KKFunctionEntryPoint3.self)
        return fn(arg1, arg2, arg3, outThrown)
    }
}


@_cdecl("__kk_kfunction_call_vararg")
public func __kk_kfunction_call_vararg(
    _ kfunctionRaw: Int,
    _ argsListRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = runtimeKFunctionBox(from: kfunctionRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid KFunction handle.")
        return runtimeNullSentinelInt
    }
    var args: [Int] = []
    if argsListRaw != 0, argsListRaw != runtimeNullSentinelInt {
        let isValidPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: argsListRaw))
        }
        guard isValidPtr,
              let listPtr = UnsafeMutableRawPointer(bitPattern: argsListRaw),
              let listBox = tryCast(listPtr, to: RuntimeListBox.self)
        else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Invalid argument list handle in KFunction.call().")
            return runtimeNullSentinelInt
        }
        args = listBox.elements
    }
    guard args.count == box.arity else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "KFunction expects \(box.arity) argument(s) but call() was invoked with \(args.count).")
        return runtimeNullSentinelInt
    }
    switch args.count {
    case 0:
        return __kk_kfunction_call_0(kfunctionRaw, outThrown)
    case 1:
        return __kk_kfunction_call_1(kfunctionRaw, args[0], outThrown)
    case 2:
        return __kk_kfunction_call_2(kfunctionRaw, args[0], args[1], outThrown)
    case 3:
        return __kk_kfunction_call_3(kfunctionRaw, args[0], args[1], args[2], outThrown)
    default:
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "KFunction.call() supports at most 3 arguments via vararg dispatch; got \(args.count).")
        return runtimeNullSentinelInt
    }
}


func runtimeKTypeProjectionToString(_ box: RuntimeKTypeProjectionBox) -> String {
    if box.variance == nil {
        return "*"
    }
    let typeString: String
    if box.typeRaw == 0 || box.typeRaw == runtimeNullSentinelInt {
        typeString = "kotlin.Any"
    } else {
        typeString = runtimeKTypeToString(raw: box.typeRaw)
    }
    switch box.variance {
    case .in:
        return "in \(typeString)"
    case .out:
        return "out \(typeString)"
    case .invariant:
        return typeString
    case nil:
        return "*"
    }
}

private func runtimeKTypeProjectionRendered(_ raw: Int) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let box = tryCast(ptr, to: RuntimeKTypeProjectionBox.self)
    else {
        return "*"
    }
    return runtimeKTypeProjectionToString(box)
}

private func runtimeKTypeArgumentsToString(_ argumentRaws: [Int]) -> String {
    guard !argumentRaws.isEmpty else {
        return ""
    }
    let renderedArguments = argumentRaws.map(runtimeKTypeProjectionRendered)
    return "<\(renderedArguments.joined(separator: ", "))>"
}

/// KUU-1084: renders a KType whose classifier token is a FunctionN in Kotlin's
/// function-type notation — `suspend (P1, P2) -> R` — instead of the nominal
/// `kotlin.FunctionN<P1, P2, R>` form. Argument projections follow Kotlin
/// order: context receivers, extension receiver, value parameters, then the
/// return type.
private func runtimeFunctionKTypeToString(_ box: RuntimeKTypeBox, classifier kclassBox: RuntimeKClassBox) -> String {
    let payload = (Int64(truncatingIfNeeded: kclassBox.typeToken) >> RuntimeTypeTokenEncoding.payloadShift)
        & RuntimeTypeTokenEncoding.payloadMask
    let (arity, isSuspend) = RuntimeTypeTokenEncoding.functionPayloadParts(payload)
    let argumentRaws = box.argumentRaws
    guard argumentRaws.count == arity + 1 else {
        // A function classifier without its full projection list (e.g. built
        // through a path that could not see the static type) keeps the nominal
        // classifier spelling.
        let baseName = isSuspend
            ? "kotlin.coroutines.intrinsics.SuspendFunction\(arity)"
            : "kotlin.Function\(arity)"
        return baseName
            + runtimeKTypeArgumentsToString(argumentRaws)
            + (box.isMarkedNullable ? "?" : "")
    }
    var parts: [String] = []
    if isSuspend {
        parts.append("suspend")
    }
    // kotlinc renders parameter projections bare inside the param parens —
    // `(() -> kotlin.Unit, kotlin.Int) -> kotlin.String` — no extra wrapper.
    let renderedParams = argumentRaws[..<arity].map(runtimeKTypeProjectionRendered)
    let renderedReturn = runtimeKTypeProjectionRendered(argumentRaws[arity])
    parts.append("(\(renderedParams.joined(separator: ", "))) -> \(renderedReturn)")
    let notation = parts.joined(separator: " ")
    return box.isMarkedNullable ? "(\(notation))?" : notation
}

private func runtimeKTypeToString(raw ktypeRaw: Int) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: ktypeRaw),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let box = tryCast(ptr, to: RuntimeKTypeBox.self)
    else {
        return "kotlin.Any"
    }
    return runtimeKTypeToString(box)
}

func runtimeQualifiedTypeName(_ name: String) -> String {
    switch name {
    case "Unit", "Nothing", "Any", "String", "Boolean", "Byte", "Short", "Int", "Long", "Float", "Double", "Char",
         "UByte", "UShort", "UInt", "ULong":
        return "kotlin.\(name)"
    default:
        return name
    }
}

func runtimeKTypeToString(_ box: RuntimeKTypeBox) -> String {
    if box.typeNameRaw != 0,
       box.typeNameRaw != runtimeNullSentinelInt,
       let typeName = extractString(from: UnsafeMutableRawPointer(bitPattern: box.typeNameRaw)),
       !typeName.isEmpty
    {
        let descriptorIsNullable = typeName.hasSuffix("?")
        let baseTypeName = descriptorIsNullable ? String(typeName.dropLast()) : typeName
        let arguments = runtimeKTypeArgumentsToString(box.argumentRaws)
        let nullableSuffix = box.isMarkedNullable || descriptorIsNullable ? "?" : ""
        return runtimeQualifiedTypeName(baseTypeName) + arguments + nullableSuffix
    }

    var baseName = "kotlin.Any"
    if let typeParameter = runtimeReflectionObject(
        from: box.classifierRaw,
        as: RuntimeKTypeParameterBox.self
    ) {
        baseName = extractString(from: UnsafeMutableRawPointer(bitPattern: typeParameter.nameRaw)) ?? "T"
        return baseName
            + runtimeKTypeArgumentsToString(box.argumentRaws)
            + (box.isMarkedNullable ? "?" : "")
    }
    if box.classifierRaw != 0,
       box.classifierRaw != runtimeNullSentinelInt,
       let classifierPtr = UnsafeMutableRawPointer(bitPattern: box.classifierRaw),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: classifierPtr)) }),
       let kclassBox = tryCast(classifierPtr, to: RuntimeKClassBox.self)
    {
        if (Int64(truncatingIfNeeded: kclassBox.typeToken) & RuntimeTypeTokenEncoding.baseMask)
            == RuntimeTypeTokenEncoding.functionBase {
            return runtimeFunctionKTypeToString(box, classifier: kclassBox)
        }
        let qualName = kclassBox.reflectionQualifiedName
        if !qualName.isEmpty {
            baseName = qualName
        } else {
            let simpleName = kclassBox.reflectionSimpleName
            if !simpleName.isEmpty {
                baseName = simpleName
            }
        }
    }
    let arguments = runtimeKTypeArgumentsToString(box.argumentRaws)
    let nullableSuffix = box.isMarkedNullable ? "?" : ""
    return baseName + arguments + nullableSuffix
}


/// - Parameters:
///   - nameRaw: Opaque pointer to the KKString for the constructor name (typically "<init>").
///   - arity: Number of parameters.
///   - returnTypeRaw: Opaque pointer to the KKString for the return type (0 if unknown).
///   - fnPtr: C function pointer integer for direct dispatch (0 if unavailable).
///   - isPrimary: 1 if this is the primary constructor, 0 otherwise.
///   - visibilityRaw: Opaque pointer to the KKString for visibility (0 for default/PUBLIC).
///   - declaringClassRaw: Opaque pointer to the declaring KClass box (0 if unknown).
@_cdecl("__kk_kconstructor_create")
public func __kk_kconstructor_create(
    _ nameRaw: Int,
    _ arity: Int,
    _ returnTypeRaw: Int,
    _ fnPtr: Int,
    _ isPrimary: Int,
    _ visibilityRaw: Int,
    _ declaringClassRaw: Int
) -> Int {
    let box = RuntimeKConstructorBox(
        nameRaw: nameRaw,
        arity: arity,
        returnTypeRaw: returnTypeRaw,
        fnPtr: fnPtr,
        isPrimary: isPrimary != 0,
        visibilityRaw: visibilityRaw,
        declaringClassRaw: declaringClassRaw
    )
    registerReflectionRuntimeTypeMetadata()
    let raw = registerRuntimeObject(box, typeID: kConstructorRuntimeTypeID)
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[raw] = RuntimeCallableRefMetadata(
            nameRaw: nameRaw,
            returnTypeRaw: returnTypeRaw,
            arity: arity,
            kind: .function,
            isSuspend: false
        )
    }
    runtimeKConstructorRegistry.register(classRaw: declaringClassRaw, constructorRaw: raw)
    return raw
}

/// Adds one JVM-erased parameter class token to a constructor reflection handle.
@_cdecl("__kk_kconstructor_set_parameter_type")
public func __kk_kconstructor_set_parameter_type(
    _ constructorRaw: Int,
    _ index: Int,
    _ typeToken: Int
) -> Int {
    guard let box = resolveRuntimeHandle(constructorRaw, as: RuntimeKConstructorBox.self), index >= 0 else {
        return 0
    }
    box.setParameterTypeToken(typeToken, at: index)
    return 1
}

@_cdecl("__kk_kconstructor_set_jvm_visibility")
public func __kk_kconstructor_set_jvm_visibility(_ constructorRaw: Int, _ visibilityOrdinal: Int) -> Int {
    guard (0..<4).contains(visibilityOrdinal),
          let constructor = runtimeReflectionObject(from: constructorRaw, as: RuntimeKConstructorBox.self)
    else {
        return 0
    }
    constructor.jvmVisibilityOrdinal = visibilityOrdinal
    return constructorRaw
}
