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

@_cdecl("__kk_java_class_is_assignable_from")
public func __kk_java_class_is_assignable_from(_ classRaw: Int, _ otherClassRaw: Int) -> Int {
    guard let targetClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self),
          let sourceClass = resolveRuntimeHandle(otherClassRaw, as: RuntimeJavaClassBox.self)
    else {
        return 0
    }

    let targetIsPrimitive = runtimeJavaClassIsPrimitive(targetClass)
    let sourceIsPrimitive = runtimeJavaClassIsPrimitive(sourceClass)
    if targetIsPrimitive || sourceIsPrimitive {
        return targetIsPrimitive && sourceIsPrimitive && targetClass.displayText == sourceClass.displayText ? 1 : 0
    }

    let targetBase = Int64(truncatingIfNeeded: targetClass.typeToken) & RuntimeTypeTokenEncoding.baseMask
    if targetBase == RuntimeTypeTokenEncoding.anyBase {
        return 1
    }

    guard let targetTypeID = runtimeJavaClassNominalTypeID(targetClass),
          let sourceTypeID = runtimeJavaClassNominalTypeID(sourceClass)
    else {
        return targetClass.typeToken == sourceClass.typeToken ? 1 : 0
    }
    return runtimeIsAssignable(sourceTypeID: sourceTypeID, targetTypeID: targetTypeID) ? 1 : 0
}

private func runtimeJavaClassIsPrimitive(_ javaClass: RuntimeJavaClassBox) -> Bool {
    let token = Int64(truncatingIfNeeded: javaClass.typeToken)
    switch token & RuntimeTypeTokenEncoding.baseMask {
    case RuntimeTypeTokenEncoding.booleanBase, RuntimeTypeTokenEncoding.byteBase,
         RuntimeTypeTokenEncoding.shortBase, RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.longBase, RuntimeTypeTokenEncoding.charBase,
         RuntimeTypeTokenEncoding.floatBase, RuntimeTypeTokenEncoding.doubleBase,
         RuntimeTypeTokenEncoding.nullBase:
        return javaClass.displayText == runtimeJavaPrimitiveClassDisplayText(typeToken: javaClass.typeToken)
    default:
        return false
    }
}

private func runtimeJavaClassNominalTypeID(_ javaClass: RuntimeJavaClassBox) -> Int64? {
    let token = Int64(truncatingIfNeeded: javaClass.typeToken) & ~RuntimeTypeTokenEncoding.nullableBit
    let base = token & RuntimeTypeTokenEncoding.baseMask
    if base == RuntimeTypeTokenEncoding.nominalBase {
        return (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    }
    if base == RuntimeTypeTokenEncoding.anyBase {
        return runtimeStableNominalTypeID(fqName: "kotlin.Any")
    }
    if base == RuntimeTypeTokenEncoding.stringBase {
        return runtimeStringNominalTypeID
    }
    switch base {
    case RuntimeTypeTokenEncoding.booleanBase, RuntimeTypeTokenEncoding.byteBase,
         RuntimeTypeTokenEncoding.shortBase, RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.longBase, RuntimeTypeTokenEncoding.charBase,
         RuntimeTypeTokenEncoding.floatBase, RuntimeTypeTokenEncoding.doubleBase,
         RuntimeTypeTokenEncoding.uintBase, RuntimeTypeTokenEncoding.ulongBase,
         RuntimeTypeTokenEncoding.ubyteBase, RuntimeTypeTokenEncoding.ushortBase:
        return runtimePrimitiveNominalTypeID(forTypeTokenBase: base)
    case RuntimeTypeTokenEncoding.unitBase:
        return runtimeStableNominalTypeID(fqName: "kotlin.Unit")
    default: return nil
    }
}

@_cdecl("__kk_class_get_enclosing_class")
public func __kk_class_get_enclosing_class(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    guard let enclosingClassName = box.enclosingClassName
        ?? runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken)?.enclosingClassName
    else {
        return runtimeNullSentinelInt
    }

    let typeToken = Int(truncatingIfNeeded: runtimeTypeToken(forQualifiedName: enclosingClassName))
    return runtimeJavaClassHandle(
        typeToken: typeToken,
        nameHint: runtimeMakeStringRaw(enclosingClassName)
    )
}

@_cdecl("__kk_class_get_enclosing_constructor")
public func __kk_class_get_enclosing_constructor(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    guard let enclosingMember = runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken)?.enclosingMember,
          enclosingMember.kind == .constructor,
          let signature = RuntimeJavaMethodMetadata(
            name: enclosingMember.name,
            signature: enclosingMember.signature,
            flags: 0
          )
    else {
        return runtimeNullSentinelInt
    }

    guard let enclosingClassName = runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken)?.enclosingClassName else {
        return runtimeNullSentinelInt
    }
    let enclosingTypeToken = Int(truncatingIfNeeded: runtimeTypeToken(forQualifiedName: enclosingClassName))
    let enclosingKClass = __kk_kclass_create(
        enclosingTypeToken,
        runtimeMakeStringRaw(enclosingClassName)
    )
    let constructor = runtimeKConstructorRegistry.constructors(for: enclosingKClass).first { raw in
        guard let constructor = runtimeReflectionObject(from: raw, as: RuntimeKConstructorBox.self),
              constructor.parameterTypeTokens.count == signature.parameterTypeTokens.count
        else {
            return false
        }
        return zip(constructor.parameterTypeTokens, signature.parameterTypeTokens).allSatisfy { actual, expected in
            actual == expected
        }
    }
    guard let constructor else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(
        RuntimeJavaConstructorBox(callableRaw: constructor, usesDefaultArguments: false),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.reflect.Constructor")
    )
}

@_cdecl("__kk_class_get_enclosing_method")
public func __kk_class_get_enclosing_method(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    guard let enclosingMember = runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken)?.enclosingMember,
          enclosingMember.kind == .method,
          let metadata = RuntimeJavaMethodMetadata(
            name: enclosingMember.name,
            signature: enclosingMember.signature,
            flags: 0
          )
    else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(
        RuntimeJavaMethodBox(metadata: metadata),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.reflect.Method")
    )
}

@_cdecl("__kk_class_get_declaring_class")
public func __kk_class_get_declaring_class(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    guard let declaringClassName = runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken)?.declaringClassName else {
        return runtimeNullSentinelInt
    }
    let typeToken = Int(truncatingIfNeeded: runtimeTypeToken(forQualifiedName: declaringClassName))
    return runtimeJavaClassHandle(
        typeToken: typeToken,
        nameHint: runtimeMakeStringRaw(declaringClassName)
    )
}
