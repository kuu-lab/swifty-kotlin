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
