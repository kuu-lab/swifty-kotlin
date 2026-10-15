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
    let className: String?
    let enclosingClassName: String?

    init(typeToken: Int, nameHint: Int = 0, className: String? = nil, enclosingClassName: String? = nil) {
        self.typeToken = typeToken
        self.nameHint = nameHint
        self.className = className
        self.enclosingClassName = enclosingClassName
    }
}

private func runtimeJavaClassHandle(typeToken: Int, nameHint: @autoclosure () -> Int) -> Int {
    if let cached = runtimeStorage.withMetadataLock({ $0.javaClassCache[typeToken] }) {
        return cached
    }
    let raw = registerRuntimeObject(
        RuntimeJavaClassBox(typeToken: typeToken, nameHint: nameHint()),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.Class")
    )
    let winner = runtimeStorage.withMetadataLock { state -> Int in
        if let cached = state.javaClassCache[typeToken] { return cached }
        state.javaClassCache[typeToken] = raw
        return raw
    }
    if winner != raw { _ = runtimeReleaseObject(raw) }
    return winner
}

@_cdecl("__kk_any_javaClass")
public func __kk_any_javaClass(_ receiverRaw: Int) -> Int {
    // A Class describes a classifier, independently of the source object's lifetime.
    let classifier = runtimeKClassBox(from: receiverRaw)
        ?? runtimeKClassBox(from: __kk_kclass_of(receiverRaw, Int(RuntimeTypeTokenEncoding.anyBase), 0))
    guard let classifier else {
        runtimeStructuredPanic("invalid runtime classifier")
    }
    return registerRuntimeObject(
        RuntimeJavaClassBox(
            typeToken: classifier.typeToken,
            nameHint: classifier.nameHint,
            enclosingClassName: runtimeFunctionEnclosingClassName(for: receiverRaw)
        ),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.Class")
    )
}

@_cdecl("__kk_kclass_java")
public func __kk_kclass_java(_ kclassRaw: Int) -> Int {
    guard let classifier = runtimeKClassBox(from: kclassRaw) else {
        runtimeStructuredPanic("invalid KClass handle")
    }
    return runtimeJavaClassHandle(typeToken: classifier.typeToken, nameHint: classifier.nameHint)
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
    for (index, constructorRaw) in constructors.enumerated() {
        array[index] = constructorRaw
    }
    return registerRuntimeObject(array)
}

@_cdecl("__kk_kclass_java_primitive_type")
public func __kk_kclass_java_primitive_type(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        runtimeStructuredPanic("invalid KClass handle")
    }
    let token = box.typeToken
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
    }
    return runtimeJavaClassHandle(typeToken: token, nameHint: box.nameHint)
}
