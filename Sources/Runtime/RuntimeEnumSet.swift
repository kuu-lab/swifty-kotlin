import Foundation

@_cdecl("__kk_enum_set_class")
public func __kk_enum_set_class(_ classRaw: Int) -> Int {
    let classifierRaw: Int
    if runtimeKClassBox(from: classRaw) != nil {
        classifierRaw = classRaw
    } else if let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) {
        classifierRaw = __kk_kclass_create(javaClass.typeToken, javaClass.nameHint)
    } else {
        return runtimeNullSentinelInt
    }
    guard let classifier = runtimeKClassBox(from: classifierRaw) else { return runtimeNullSentinelInt }
    if classifier.metadata?.isEnumClass == true { return classifierRaw }
    // Boxing records enum identity independently of optional full reflection
    // records and of the original entry's lifetime.
    let token = Int64(classifier.typeToken)
    guard token & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.nominalBase else {
        return runtimeNullSentinelInt
    }
    let classID = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    return runtimeStorage.withMetadataLock { $0.enumClassifierIDs.contains(classID) }
        ? classifierRaw : runtimeNullSentinelInt
}

/// Returns the registered enum entries for a Java Class handle, or null when
/// the class is not an enum.
@_cdecl("__kk_enum_set_values")
public func __kk_enum_set_values(_ classRaw: Int) -> Int {
    let typeToken: Int
    if let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) {
        typeToken = javaClass.typeToken
    } else if let kClass = runtimeKClassBox(from: classRaw) {
        typeToken = kClass.typeToken
    } else {
        return runtimeNullSentinelInt
    }
    let isRegistered = runtimeStorage.withMetadataLock {
        $0.enumValuesByTypeToken[Int64(typeToken)] != nil
    }
    guard isRegistered else { return runtimeNullSentinelInt }
    return kk_enum_values_for_token(typeToken)
}
