import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct RuntimeMemorySnapshot: Equatable, Sendable {
    let totalBytes: Int64
    let freeBytes: Int64
    let maxBytes: Int64
}

final class RuntimeMemoryHandle: @unchecked Sendable {
    static let shared = RuntimeMemoryHandle()
    private init() {}
}

private let runtimeMemoryHandleRaw: Int = registerRuntimeObject(RuntimeMemoryHandle.shared)

func runtimeCaptureMemorySnapshot() -> RuntimeMemorySnapshot {
    let usedBytes = runtimeCurrentMemoryUsageBytes()
    let maxBytes = runtimeMaximumMemoryBytes()
    let totalBytes = min(max(usedBytes, 0), maxBytes)
    let freeBytes = max(maxBytes - totalBytes, 0)
    return RuntimeMemorySnapshot(
        totalBytes: totalBytes,
        freeBytes: freeBytes,
        maxBytes: maxBytes
    )
}

private func runtimeMaximumMemoryBytes() -> Int64 {
    Int64(clamping: ProcessInfo.processInfo.physicalMemory)
}

private func runtimeCurrentMemoryUsageBytes() -> Int64 {
#if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundPtr, &count)
        }
    }
    if result == KERN_SUCCESS {
        return Int64(info.resident_size)
    }
    return 0
#elseif canImport(Glibc)
    guard let statm = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) else {
        return 0
    }
    let fields = statm.split(whereSeparator: \.isWhitespace)
    guard fields.count > 1, let residentPages = Int64(fields[1]) else {
        return 0
    }
    let pageSize = Int64(sysconf(Int32(_SC_PAGESIZE)))
    return residentPages * max(pageSize, 1)
#else
    return 0
#endif
}

@_cdecl("__kk_system_gc")
public func __kk_system_gc() {
    kk_gc_collect()
}

@_cdecl("__kk_runtime_getRuntime")
public func __kk_runtime_getRuntime() -> Int {
    runtimeMemoryHandleRaw
}

@_cdecl("__kk_runtime_totalMemory")
public func __kk_runtime_totalMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().totalBytes)
}

@_cdecl("__kk_runtime_freeMemory")
public func __kk_runtime_freeMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().freeBytes)
}

@_cdecl("__kk_runtime_maxMemory")
public func __kk_runtime_maxMemory() -> Int {
    Int(clamping: runtimeCaptureMemorySnapshot().maxBytes)
}

@_cdecl("__kk_runtime_availableProcessors")
public func __kk_runtime_availableProcessors() -> Int {
    kk_platform_getAvailableProcessors(0)
}

final class RuntimeJavaClassBox: @unchecked Sendable {
    let typeToken: Int
    let nameHint: Int
    let javaNameOverride: String?
    let canonicalNameOverride: String?
    let className: String?
    let enclosingClassName: String?
    let displayText: String

    init(
        typeToken: Int,
        nameHint: Int = 0,
        javaNameOverride: String? = nil,
        canonicalNameOverride: String? = nil,
        className: String? = nil,
        enclosingClassName: String? = nil,
        displayText: String? = nil
    ) {
        self.typeToken = typeToken
        self.nameHint = nameHint
        self.javaNameOverride = javaNameOverride
        self.canonicalNameOverride = canonicalNameOverride
        self.className = className
        self.enclosingClassName = enclosingClassName
        self.displayText = displayText
            ?? className.map { "class \($0)" }
            ?? runtimeJavaClassDisplayText(receiverRaw: 0, typeToken: typeToken, nameHint: nameHint)
    }
}

func runtimeJavaClassHandle(typeToken: Int, nameHint: @autoclosure () -> Int) -> Int {
    runtimeJavaClassHandle(
        cacheKey: JavaClassCacheKey(typeToken: typeToken),
        typeToken: typeToken,
        nameHint: nameHint
    )
}

private func runtimeJavaClassHandle(
    cacheKey: JavaClassCacheKey,
    typeToken: Int,
    nameHint: () -> Int,
    enclosingClassName: String? = nil,
    javaNameOverride: String? = nil,
    canonicalNameOverride: String? = nil,
    className: String? = nil,
    displayText: (() -> String)? = nil
) -> Int {
    if let cached = runtimeStorage.withMetadataLock({ $0.javaClassCache[cacheKey] }) {
        return cached
    }
    let raw = registerRuntimeObject(
        RuntimeJavaClassBox(
            typeToken: typeToken,
            nameHint: nameHint(),
            javaNameOverride: javaNameOverride,
            canonicalNameOverride: canonicalNameOverride,
            className: className,
            enclosingClassName: enclosingClassName,
            displayText: displayText?()
        ),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.Class")
    )
    let winner = runtimeStorage.withMetadataLock { state -> Int in
        if let cached = state.javaClassCache[cacheKey] { return cached }
        state.javaClassCache[cacheKey] = raw
        return raw
    }
    if winner != raw { _ = runtimeReleaseObject(raw) }
    return winner
}

private func runtimeJavaWrapperClassName(typeToken: Int, kclassRaw: Int) -> String? {
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_kclass_qualified_name(kclassRaw)))
    if name == "java.lang.Void" || name == "kotlin.Nothing" {
        return "java.lang.Void"
    }

    switch Int64(truncatingIfNeeded: typeToken) & RuntimeTypeTokenEncoding.baseMask {
    case RuntimeTypeTokenEncoding.booleanBase: return "java.lang.Boolean"
    case RuntimeTypeTokenEncoding.byteBase: return "java.lang.Byte"
    case RuntimeTypeTokenEncoding.shortBase: return "java.lang.Short"
    case RuntimeTypeTokenEncoding.intBase: return "java.lang.Integer"
    case RuntimeTypeTokenEncoding.longBase: return "java.lang.Long"
    case RuntimeTypeTokenEncoding.charBase: return "java.lang.Character"
    case RuntimeTypeTokenEncoding.floatBase: return "java.lang.Float"
    case RuntimeTypeTokenEncoding.doubleBase: return "java.lang.Double"
    default:
        return nil
    }
}

@_cdecl("__kk_kclass_java_object_type")
public func __kk_kclass_java_object_type(_ kclassRaw: Int) -> Int {
    guard let classifier = runtimeKClassBox(from: kclassRaw) else {
        runtimeStructuredPanic("invalid KClass handle")
    }
    guard let wrapperClassName = runtimeJavaWrapperClassName(
        typeToken: classifier.typeToken,
        kclassRaw: kclassRaw
    ) else {
        return runtimeJavaClassHandle(typeToken: classifier.typeToken, nameHint: classifier.nameHint)
    }

    return runtimeJavaClassHandle(
        cacheKey: JavaClassCacheKey(
            typeToken: classifier.typeToken,
            runtimeClassName: wrapperClassName
        ),
        typeToken: classifier.typeToken,
        nameHint: { classifier.nameHint },
        javaNameOverride: wrapperClassName,
        canonicalNameOverride: wrapperClassName,
        className: wrapperClassName,
        displayText: { "class \(wrapperClassName)" }
    )
}

@_cdecl("__kk_any_javaClass")
public func __kk_any_javaClass(_ receiverRaw: Int) -> Int {
    // A Class describes a classifier, independently of the source object's lifetime.
    let classifier = runtimeKClassBox(from: receiverRaw)
        ?? runtimeKClassBox(from: __kk_kclass_of(receiverRaw, Int(RuntimeTypeTokenEncoding.anyBase), 0))
    guard let classifier else {
        runtimeStructuredPanic("invalid runtime classifier")
    }
    // KClass-sourced lookups canonicalize through javaClassCache so
    // Class.forName and KClass.java agree on identity, matching JVM Class
    // interning. Object receivers use the same classifier cache, with a
    // runtime-class discriminator for arrays, collection implementations,
    // and generated functions.
    if runtimeKClassBox(from: receiverRaw) != nil {
        return runtimeJavaClassHandle(typeToken: classifier.typeToken, nameHint: classifier.nameHint)
    }
    let cacheKey = runtimeJavaClassCacheKey(
        receiverRaw: receiverRaw,
        typeToken: classifier.typeToken,
        nameHint: classifier.nameHint
    )
    return runtimeJavaClassHandle(
        cacheKey: cacheKey,
        typeToken: classifier.typeToken,
        nameHint: { classifier.nameHint },
        enclosingClassName: runtimeFunctionEnclosingClassName(for: receiverRaw),
        displayText: {
            runtimeJavaClassDisplayText(
                receiverRaw: receiverRaw,
                typeToken: classifier.typeToken,
                nameHint: classifier.nameHint
            )
        }
    )
}

private func runtimeKotlinClassName(forJavaClassName name: String) -> String {
    switch name {
    case "java.lang.Object": return "kotlin.Any"
    case "java.lang.String": return "kotlin.String"
    case "java.lang.CharSequence": return "kotlin.CharSequence"
    case "java.lang.Throwable": return "kotlin.Throwable"
    case "java.lang.Exception": return "kotlin.Exception"
    case "java.lang.RuntimeException": return "kotlin.RuntimeException"
    default:
        // Kotlin nested classifiers use dots in their semantic names; JVM
        // binary class names use '$' between the same classifiers.
        return name.replacingOccurrences(of: "$", with: ".")
    }
}

@_cdecl("__kk_class_for_name")
public func __kk_class_for_name(_ classNameRaw: Int) -> Int {
    guard let className = extractString(from: UnsafeMutableRawPointer(bitPattern: classNameRaw)) else {
        runtimeStructuredPanic("invalid runtime classifier")
    }
    let kotlinName = runtimeKotlinClassName(forJavaClassName: className)
    let token = Int(truncatingIfNeeded: runtimeTypeToken(forQualifiedName: kotlinName))
    return runtimeJavaClassHandle(typeToken: token, nameHint: runtimeMakeStringRaw(kotlinName))
}

@_cdecl("__kk_class_toString")
public func __kk_class_toString(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeMakeStringRaw(box.displayText)
}

@_cdecl("__kk_class_kotlin")
public func __kk_class_kotlin(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return __kk_kclass_create(box.typeToken, box.nameHint)
}

@_cdecl("__kk_class_declared_constructors")
public func __kk_class_declared_constructors(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    let kclassRaw = __kk_kclass_create(box.typeToken, box.nameHint)
    let constructors = runtimeKConstructorRegistry.constructors(for: kclassRaw)
    let array = RuntimeArrayBox(length: constructors.count)
    let constructorTypeID = runtimeStableNominalTypeID(fqName: "java.lang.reflect.Constructor")
    for (index, constructorRaw) in constructors.enumerated() {
        array[index] = registerRuntimeObject(
            RuntimeJavaConstructorBox(callableRaw: constructorRaw, usesDefaultArguments: false),
            typeID: constructorTypeID
        )
    }
    return registerRuntimeObject(array)
}

@_cdecl("__kk_class_declared_constructor")
public func __kk_class_declared_constructor(_ classRaw: Int, _ parameterTypesRaw: Int) -> Int {
    guard let classBox = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self),
          let parameterTypes = runtimeArrayBox(from: parameterTypesRaw)
    else {
        runtimeStructuredPanic("invalid Java Class constructor lookup")
    }

    let requestedTypeTokens = parameterTypes.elements.map { parameterClassRaw -> Int in
        guard let parameterClass = resolveRuntimeHandle(parameterClassRaw, as: RuntimeJavaClassBox.self) else {
            runtimeStructuredPanic("invalid constructor parameter Class handle")
        }
        return parameterClass.typeToken
    }
    let requestedJavaTypeTokens = requestedTypeTokens.map(normalizedJavaClassTypeToken)
    let classKotlin = __kk_kclass_create(classBox.typeToken, classBox.nameHint)
    for constructorRaw in runtimeKConstructorRegistry.constructors(for: classKotlin) {
        guard let constructor = resolveRuntimeHandle(constructorRaw, as: RuntimeKConstructorBox.self),
              constructor.parameterTypeTokens.count == requestedJavaTypeTokens.count
        else {
            continue
        }
        let matches = zip(constructor.parameterTypeTokens, requestedJavaTypeTokens).allSatisfy { expected, actual in
            guard let expected else { return false }
            return normalizedJavaClassTypeToken(expected) == actual
        }
        if matches {
            return registerRuntimeObject(
                RuntimeJavaConstructorBox(callableRaw: constructorRaw, usesDefaultArguments: false),
                typeID: runtimeStableNominalTypeID(fqName: "java.lang.reflect.Constructor")
            )
        }
    }

    runtimeStructuredPanic("NoSuchMethodException: no declared constructor matches the requested parameter classes")
}

private func normalizedJavaClassTypeToken(_ token: Int) -> Int64 {
    Int64(truncatingIfNeeded: token) & ~RuntimeTypeTokenEncoding.nullableBit
}

@_cdecl("__kk_kclass_java_class")
public func __kk_kclass_java_class(_ kclassRaw: Int) -> Int {
    guard let classifier = runtimeKClassBox(from: kclassRaw) else {
        runtimeStructuredPanic("invalid KClass handle")
    }
    // KClass-sourced lookups canonicalize through javaClassCache so
    // Class.forName and KClass.java agree on identity, matching JVM Class
    // interning.
    return runtimeJavaClassHandle(typeToken: classifier.typeToken, nameHint: classifier.nameHint)
}

@_cdecl("__kk_class_canonical_name")
public func __kk_class_canonical_name(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    if let canonicalName = box.canonicalNameOverride {
        return runtimeMakeStringRaw(canonicalName)
    }
    let base = Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask
    let canonicalName: String?
    switch base {
    case RuntimeTypeTokenEncoding.booleanBase:
        canonicalName = "boolean"
    case RuntimeTypeTokenEncoding.charBase:
        canonicalName = "char"
    case RuntimeTypeTokenEncoding.byteBase:
        canonicalName = "byte"
    case RuntimeTypeTokenEncoding.shortBase:
        canonicalName = "short"
    case RuntimeTypeTokenEncoding.intBase:
        canonicalName = "int"
    case RuntimeTypeTokenEncoding.floatBase:
        canonicalName = "float"
    case RuntimeTypeTokenEncoding.longBase:
        canonicalName = "long"
    case RuntimeTypeTokenEncoding.doubleBase:
        canonicalName = "double"
    case RuntimeTypeTokenEncoding.nullBase:
        canonicalName = "void"
    case RuntimeTypeTokenEncoding.anyBase:
        canonicalName = "java.lang.Object"
    case RuntimeTypeTokenEncoding.stringBase:
        canonicalName = "java.lang.String"
    default:
        let qualifiedNameRaw = __kk_type_token_qualified_name(box.typeToken, box.nameHint)
        guard qualifiedNameRaw != 0, qualifiedNameRaw != runtimeNullSentinelInt,
              let qualifiedName = extractString(from: UnsafeMutableRawPointer(bitPattern: qualifiedNameRaw)),
              !qualifiedName.isEmpty, qualifiedName != "Unknown"
        else {
            return runtimeNullSentinelInt
        }
        canonicalName = runtimeJVMExceptionFQName(from: qualifiedName)
    }
    guard let canonicalName else { return runtimeNullSentinelInt }
    return runtimeMakeStringRaw(canonicalName)
}

@_cdecl("__kk_kclass_java_primitive_type")
public func __kk_kclass_java_primitive_type(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        runtimeStructuredPanic("invalid KClass handle")
    }
    let token = box.typeToken
    var canonicalNameOverride: String?
    // Kotlin's eight value primitives and Nothing (the JVM Void classifier) map
    // to primitive Class handles.
    // Unit and unsigned value classes are reference types on the JVM.
    switch Int64(token) & RuntimeTypeTokenEncoding.baseMask {
    case RuntimeTypeTokenEncoding.booleanBase, RuntimeTypeTokenEncoding.byteBase,
         RuntimeTypeTokenEncoding.shortBase, RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.longBase, RuntimeTypeTokenEncoding.charBase,
         RuntimeTypeTokenEncoding.floatBase, RuntimeTypeTokenEncoding.doubleBase:
        break
    default:
        let name = extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_kclass_qualified_name(kclassRaw)))
        guard name == "java.lang.Void" || name == "kotlin.Nothing" else {
            return runtimeNullSentinelInt
        }
        canonicalNameOverride = "void"
    }
    if let cached = runtimeStorage.withMetadataLock({ $0.primitiveJavaClassCache[token] }) {
        return cached
    }
    let raw = registerRuntimeObject(
        RuntimeJavaClassBox(
            typeToken: token,
            nameHint: box.nameHint,
            canonicalNameOverride: canonicalNameOverride,
            displayText: runtimeJavaPrimitiveClassDisplayText(typeToken: token)
        ),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.Class")
    )
    let winner = runtimeStorage.withMetadataLock { state -> Int in
        if let cached = state.primitiveJavaClassCache[token] { return cached }
        state.primitiveJavaClassCache[token] = raw
        return raw
    }
    if winner != raw { _ = runtimeReleaseObject(raw) }
    return winner
}
