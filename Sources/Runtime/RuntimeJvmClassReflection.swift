import RuntimeABI

private let runtimeJavaClassTypeID = runtimeStableNominalTypeID(fqName: "java.lang.Class")

@_cdecl("__kk_class_get_name")
public func __kk_class_get_name(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    if let className = box.className {
        return runtimeMakeStringRaw(className)
    }
    return __kk_type_token_qualified_name(box.typeToken, box.nameHint)
}

@_cdecl("__kk_java_class_isInstance")
public func __kk_java_class_isInstance(_ classRaw: Int, _ valueRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        return 0
    }
    return kk_op_is(valueRaw, javaClass.typeToken)
}

@_cdecl("__kk_class_get_enclosing_class")
public func __kk_class_get_enclosing_class(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    guard let enclosingClassName = box.enclosingClassName else {
        return runtimeNullSentinelInt
    }

    let typeID = runtimeStableNominalTypeID(fqName: enclosingClassName)
    let typeToken = Int(truncatingIfNeeded: (
        (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
    ) | RuntimeTypeTokenEncoding.nominalBase)
    return registerRuntimeObject(
        RuntimeJavaClassBox(typeToken: typeToken, className: enclosingClassName),
        typeID: runtimeJavaClassTypeID
    )
}
