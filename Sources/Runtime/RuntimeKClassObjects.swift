import Foundation

/// Registration is separate from mutable class metadata, which literals can re-register.
final class RuntimeKClassObjectRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var objects: [Int: (object: Int, initializer: Int)] = [:]
    private var subclasses: [Int: [Int]] = [:]

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        objects.removeAll()
        subclasses.removeAll()
    }

    func registerObject(token: Int, object: Int, initializer: Int) {
        lock.lock()
        defer { lock.unlock() }
        objects[token] = (object, initializer)
    }

    func object(token: Int) -> (object: Int, initializer: Int)? {
        lock.lock()
        defer { lock.unlock() }
        return objects[token]
    }

    func registerSubclass(token: Int, subclass: Int) {
        lock.lock()
        defer { lock.unlock() }
        if !(subclasses[token] ?? []).contains(subclass) {
            subclasses[token, default: []].append(subclass)
        }
    }

    func subclasses(token: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return subclasses[token] ?? []
    }
}

let runtimeKClassObjectRegistry = RuntimeKClassObjectRegistry()

@_cdecl("__kk_kclass_register_object")
public func __kk_kclass_register_object(_ typeToken: Int, _ objectRaw: Int, _ initializerRaw: Int) -> Int {
    runtimeKClassObjectRegistry.registerObject(token: typeToken, object: objectRaw, initializer: initializerRaw)
    return 0
}

@_cdecl("__kk_kclass_object_instance")
public func __kk_kclass_object_instance(_ kclassRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeKClassBox(from: kclassRaw),
          let entry = runtimeKClassObjectRegistry.object(token: box.typeToken) else {
        return runtimeNullSentinelInt
    }
    if let pointer = UnsafeRawPointer(bitPattern: entry.initializer) {
        // Kotlin initializer functions return the raw Unit value and carry an exception channel.
        let initialize = unsafeBitCast(pointer, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        _ = initialize(&thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return runtimeNullSentinelInt
        }
    }
    return entry.object
}

@_cdecl("__kk_kclass_register_sealed_subclass")
public func __kk_kclass_register_sealed_subclass(_ typeToken: Int, _ subclassToken: Int, _ nameHint: Int) -> Int {
    let subclass = __kk_kclass_create(subclassToken, nameHint)
    runtimeKClassObjectRegistry.registerSubclass(token: typeToken, subclass: subclass)
    return 0
}

@_cdecl("__kk_kclass_sealed_subclasses")
public func __kk_kclass_sealed_subclasses(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw), box.metadata?.isSealedClass == true else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: runtimeKClassObjectRegistry.subclasses(token: box.typeToken)))
}
