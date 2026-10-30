//
// All C memory here is real `malloc`'d unmanaged memory: `memScoped`/`Arena`
// allocations are owned by a `RuntimeCInteropArenaBox` and freed in bulk by
// `kk_arena_clear`, `nativeHeap` allocations are individually owned and freed
// by `kk_native_placement_free`. Pointer handles carry real machine-word
// addresses inside `RuntimeCPointerBox` / `RuntimeCOpaquePointerBox`, so the
// values can be passed to genuine C callsites.

import Foundation

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

/// `aggregate` covers struct vars (CPointerVar-like opaque pointees) where a
/// machine word is stored.
enum RuntimeCInteropVarKind: Equatable {
    case boolean, int8, uint8, int16, uint16, int32, uint32
    case int64, uint64, float32, float64, char16
    case pointer, aggregate, vector128

    var size: Int {
        switch self {
        case .boolean, .int8, .uint8: return 1
        case .int16, .uint16, .char16: return 2
        case .int32, .uint32, .float32: return 4
        case .int64, .uint64, .float64, .pointer, .aggregate: return 8
        case .vector128: return 16
        }
    }

    var align: Int {
        switch self {
        case .vector128: return 16
        default: return min(size, 8)
        }
    }
}

func runtimeCInteropVarKind(forTypeToken token: Int) -> RuntimeCInteropVarKind? {
    let wide = Int64(truncatingIfNeeded: token)
    let base = wide & RuntimeTypeTokenEncoding.baseMask
    switch base {
    case RuntimeTypeTokenEncoding.booleanBase: return .boolean
    case RuntimeTypeTokenEncoding.byteBase: return .int8
    case RuntimeTypeTokenEncoding.ubyteBase: return .uint8
    case RuntimeTypeTokenEncoding.shortBase: return .int16
    case RuntimeTypeTokenEncoding.ushortBase: return .uint16
    case RuntimeTypeTokenEncoding.intBase: return .int32
    case RuntimeTypeTokenEncoding.uintBase: return .uint32
    case RuntimeTypeTokenEncoding.longBase: return .int64
    case RuntimeTypeTokenEncoding.ulongBase: return .uint64
    case RuntimeTypeTokenEncoding.floatBase: return .float32
    case RuntimeTypeTokenEncoding.doubleBase: return .float64
    case RuntimeTypeTokenEncoding.charBase: return .char16
    case RuntimeTypeTokenEncoding.nominalBase:
        let payload = (wide >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
        return runtimeCInteropVarKind(forNominalTypeID: payload)
    default:
        return nil
    }
}

/// Both the `FooVar` typealias target spelling and the generic `FooVarOf`
/// class resolve to the same kind so `alloc<IntVar>()` and
/// `alloc<IntVarOf<Int>>()` allocate identically.
func runtimeCInteropVarKind(forNominalTypeID typeID: Int64) -> RuntimeCInteropVarKind? {
    let names: [(String, RuntimeCInteropVarKind)] = [
        ("BooleanVar", .boolean), ("BooleanVarOf", .boolean),
        ("ByteVar", .int8), ("ByteVarOf", .int8),
        ("UByteVar", .uint8), ("UByteVarOf", .uint8),
        ("ShortVar", .int16), ("ShortVarOf", .int16),
        ("UShortVar", .uint16), ("UShortVarOf", .uint16),
        ("IntVar", .int32), ("IntVarOf", .int32),
        ("UIntVar", .uint32), ("UIntVarOf", .uint32),
        ("LongVar", .int64), ("LongVarOf", .int64),
        ("ULongVar", .uint64), ("ULongVarOf", .uint64),
        ("FloatVar", .float32), ("FloatVarOf", .float32),
        ("DoubleVar", .float64), ("DoubleVarOf", .float64),
        ("CPointerVar", .pointer), ("CPointerVarOf", .pointer),
        ("COpaquePointerVar", .pointer), ("CEnumVar", .int32),
        ("Vector128", .vector128),
        ("CStructVar", .aggregate), ("CVariable", .aggregate),
    ]
    for (name, kind) in names
    where runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.\(name)") == typeID {
        return kind
    }
    return nil
}

/// Returns the raw payload when the token is nominal, else 0 (opaque).
func runtimeCInteropNominalTypeID(forTypeToken token: Int) -> Int64 {
    let wide = Int64(truncatingIfNeeded: token)
    guard wide & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.nominalBase else {
        return 0
    }
    return (wide >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
}


final class RuntimeCInteropArenaBox: @unchecked Sendable {
    private let lock = NSLock()
    private var allocations: [UInt] = []
    /// `() -> Unit` Kotlin block handles registered via `defer`, run LIFO.
    private var deferredBlocks: [Int] = []
    /// Set once `clear()` has run; later allocation attempts trap.
    private var cleared = false
    init() {}

    func addDeferred(_ block: Int) {
        lock.lock()
        defer { lock.unlock() }
        if cleared {
            runtimeStructuredPanic("kotlinx.cinterop: defer on a cleared scope")
        }
        deferredBlocks.append(block)
    }

    func allocate(size: Int, align: Int) -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }
        if cleared {
            runtimeStructuredPanic("kotlinx.cinterop: allocation into a cleared scope")
        }
        let byteSize = max(1, size)
        let raw: UnsafeMutableRawPointer
        if align > MemoryLayout<UnsafeMutableRawPointer>.alignment {
            var ptr: UnsafeMutableRawPointer?
            if posix_memalign(&ptr, align, byteSize) != 0 || ptr == nil {
                runtimeStructuredPanic("kotlinx.cinterop: allocation failed")
            }
            raw = ptr.unsafelyUnwrapped
        } else {
            guard let allocated = malloc(byteSize) else {
                runtimeStructuredPanic("kotlinx.cinterop: allocation failed")
            }
            raw = allocated
        }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: byteSize)
        allocations.append(UInt(bitPattern: raw))
        return raw
    }

    /// Free one tracked allocation early (NativeFreeablePlacement.free).
    /// Arena allocations are arena-owned; `free` on them releases immediately
    /// and untracks the address so `clear()` does not double-free it.
    func freeNow(_ address: UInt) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = allocations.firstIndex(of: address) else { return false }
        allocations.remove(at: index)
        free(UnsafeMutableRawPointer(bitPattern: address))
        return true
    }

    func clear(outThrown: UnsafeMutablePointer<Int>?) {
        lock.lock()
        if cleared {
            lock.unlock()
            return
        }
        cleared = true
        let deferred = deferredBlocks.reversed() as [Int]
        let addrs = allocations
        allocations.removeAll()
        deferredBlocks.removeAll()
        lock.unlock()

        var firstThrow = 0
        for block in deferred {
            var thrown = 0
            _ = kk_function_invoke_0(block, &thrown)
            if thrown != 0 && firstThrow == 0 {
                firstThrow = thrown
            }
        }
        for addr in addrs {
            free(UnsafeMutableRawPointer(bitPattern: addr))
        }
        if firstThrow != 0 {
            if let outThrown {
                outThrown.pointee = firstThrow
            } else {
                runtimeStructuredPanic("kotlinx.cinterop: defer block threw in a non-throwing clear()")
            }
        }
    }
}

final class RuntimeCInteropNativeHeapBox: @unchecked Sendable {
    private let lock = NSLock()
    var allocations: Set<UInt> = []

    func allocate(size: Int, align: Int) -> UnsafeMutableRawPointer {
        let byteSize = max(1, size)
        let raw: UnsafeMutableRawPointer
        if align > MemoryLayout<UnsafeMutableRawPointer>.alignment {
            var ptr: UnsafeMutableRawPointer?
            if posix_memalign(&ptr, align, byteSize) != 0 || ptr == nil {
                runtimeStructuredPanic("kotlinx.cinterop: nativeHeap allocation failed")
            }
            raw = ptr.unsafelyUnwrapped
        } else {
            guard let allocated = malloc(byteSize) else {
                runtimeStructuredPanic("kotlinx.cinterop: nativeHeap allocation failed")
            }
            raw = allocated
        }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: byteSize)
        lock.lock()
        allocations.insert(UInt(bitPattern: raw))
        lock.unlock()
        return raw
    }

    func freeNow(_ address: UInt) -> Bool {
        lock.lock()
        let tracked = allocations.remove(address) != nil
        lock.unlock()
        if tracked {
            free(UnsafeMutableRawPointer(bitPattern: address))
        }
        return tracked
    }
}

final class RuntimeCInteropNativePtrBox: @unchecked Sendable {
    let address: UInt
    init(address: UInt) {
        self.address = address
    }
}

/// `owner` keeps the arena alive while any var aliasing its memory survives.
final class RuntimeCInteropVarBox: @unchecked Sendable {
    let address: UInt
    /// Nominal typeID of the pointee type (IntVar, CPointerVar, ...), 0 for
    /// untyped aggregate storage.
    let pointeeTypeID: Int64
    let owner: AnyObject?

    init(
        address: UInt,
        pointeeTypeID: Int64,
        owner: AnyObject?
    ) {
        self.address = address
        self.pointeeTypeID = pointeeTypeID
        self.owner = owner
    }
}


private let cinteropMemScopeTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.MemScope")
private let cinteropArenaTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.Arena")
private let cinteropArenaBaseTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ArenaBase")
private let cinteropAutofreeScopeTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.AutofreeScope")
private let cinteropDeferScopeTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.DeferScope")
private let cinteropNativePlacementTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.NativePlacement")
private let cinteropNativeFreeablePlacementTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.NativeFreeablePlacement")
private let cinteropNativeHeapObjectTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.nativeHeap")
private let cinteropNativePtrTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.NativePtr")
private let cinteropCPointerTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.CPointer")
private let cinteropCVariableTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.CVariable")
private let cinteropCPrimitiveVarTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.CPrimitiveVar")
private let cinteropCPointedTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.CPointed")
private let cinteropNativePointedTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.NativePointed")
private let cinteropByteVarTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")
private let cinteropByteVarOfTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVarOf")

private func cinteropVariableClassID(for pointeeTypeID: Int64) -> Int64 {
    // ByteVar is an alias; runtime casts use its concrete ByteVarOf class.
    if pointeeTypeID == cinteropByteVarTypeID { return cinteropByteVarOfTypeID }
    return pointeeTypeID != 0 ? pointeeTypeID : cinteropCVariableTypeID
}

/// Installs the MemScope/Arena/nativeHeap subtype edges once per metadata
/// generation. Mirrors `registerReflectionRuntimeTypeMetadata`'s flag
/// handling: `kk_runtime_reset_metadata` clears `typeParents` and the flag so
/// test isolation re-registers on the next arena creation.
func registerCInteropRuntimeTypeMetadata() {
    runtimeStorage.withMetadataLock { state in
        if state.cinteropTypeEdgesRegistered {
            return
        }
        var edges: [(Int64, Int64)] = [
            (cinteropMemScopeTypeID, cinteropArenaBaseTypeID),
            (cinteropArenaTypeID, cinteropArenaBaseTypeID),
            (cinteropArenaBaseTypeID, cinteropAutofreeScopeTypeID),
            (cinteropAutofreeScopeTypeID, cinteropDeferScopeTypeID),
            (cinteropAutofreeScopeTypeID, cinteropNativePlacementTypeID),
            (cinteropNativeHeapObjectTypeID, cinteropNativeFreeablePlacementTypeID),
            (cinteropNativeFreeablePlacementTypeID, cinteropNativePlacementTypeID),
            (cinteropCPrimitiveVarTypeID, cinteropCVariableTypeID),
            (cinteropCVariableTypeID, cinteropCPointedTypeID),
            (cinteropCPointedTypeID, cinteropNativePointedTypeID),
        ]
        for name in [
            "BooleanVar", "BooleanVarOf", "ByteVar", "ByteVarOf",
            "UByteVar", "UByteVarOf", "ShortVar", "ShortVarOf",
            "UShortVar", "UShortVarOf", "IntVar", "IntVarOf",
            "UIntVar", "UIntVarOf", "LongVar", "LongVarOf",
            "ULongVar", "ULongVarOf", "FloatVar", "FloatVarOf",
            "DoubleVar", "DoubleVarOf", "CEnumVar",
        ] {
            edges.append((runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.\(name)"), cinteropCPrimitiveVarTypeID))
        }
        for name in ["CStructVar", "CPointerVar", "CPointerVarOf", "COpaquePointerVar", "Vector128"] {
            edges.append((runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.\(name)"), cinteropCVariableTypeID))
        }
        for (child, parent) in edges {
            state.typeParents[child, default: []].insert(parent)
        }
        state.cinteropTypeEdgesRegistered = true
    }
}


func resolveCInteropArenaBox(from handle: Int) -> RuntimeCInteropArenaBox? {
    guard handle != 0, handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) })
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCInteropArenaBox.self)
}

func resolveCInteropNativeHeapBox(from handle: Int) -> RuntimeCInteropNativeHeapBox? {
    guard handle != 0, handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) })
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCInteropNativeHeapBox.self)
}

func resolveCInteropVarBox(from handle: Int) -> RuntimeCInteropVarBox? {
    guard handle != 0, handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) })
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCInteropVarBox.self)
}

func resolveCInteropNativePtrBox(from handle: Int) -> RuntimeCInteropNativePtrBox? {
    guard handle != 0, handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) })
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCInteropNativePtrBox.self)
}

func resolveCOpaquePointerBox(from handle: Int) -> RuntimeCOpaquePointerBox? {
    guard handle != 0, handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) })
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCOpaquePointerBox.self)
}


/// `MemScope()` / `memScoped` scope object. Registered as MemScope so `is`
/// checks see MemScope <: ArenaBase <: AutofreeScope <: NativePlacement.
@_cdecl("kk_memscope_new")
public func kk_memscope_new() -> Int {
    registerCInteropRuntimeTypeMetadata()
    return registerRuntimeObject(
        RuntimeCInteropArenaBox(),
        typeID: cinteropMemScopeTypeID
    )
}

@_cdecl("kk_arena_new")
public func kk_arena_new() -> Int {
    registerCInteropRuntimeTypeMetadata()
    return registerRuntimeObject(
        RuntimeCInteropArenaBox(),
        typeID: cinteropArenaTypeID
    )
}

@_cdecl("kk_native_heap_get")
public func kk_native_heap_get() -> Int {
    registerCInteropRuntimeTypeMetadata()
    return registerRuntimeObject(
        RuntimeCInteropNativeHeapBox(),
        typeID: cinteropNativeHeapObjectTypeID
    )
}


/// Returns a `NativePtr` box. `size` arrives as a boxed Long, `align` as a
/// boxed Int (unboxers pass raw ints through unchanged).
@_cdecl("kk_arena_alloc_raw")
public func kk_arena_alloc_raw(_ scope: Int, _ size: Int, _ align: Int) -> Int {
    let byteCount = kk_unbox_long(size)
    let alignment = max(1, kk_unbox_int(align))
    guard byteCount >= 0 else { return 0 }
    let address: UInt
    if let arena = resolveCInteropArenaBox(from: scope) {
        address = UInt(bitPattern: arena.allocate(size: byteCount, align: alignment))
    } else if let heap = resolveCInteropNativeHeapBox(from: scope) {
        address = UInt(bitPattern: heap.allocate(size: byteCount, align: alignment))
    } else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeCInteropNativePtrBox(address: address),
        typeID: cinteropNativePtrTypeID
    )
}

@_cdecl("kk_arena_alloc_var")
public func kk_arena_alloc_var(_ scope: Int, _ typeToken: Int) -> Int {
    guard let kind = runtimeCInteropVarKind(forTypeToken: typeToken) else {
        return 0
    }
    let typeID = runtimeCInteropNominalTypeID(forTypeToken: typeToken)
    let owner: AnyObject?
    let address: UInt
    if let arena = resolveCInteropArenaBox(from: scope) {
        address = UInt(bitPattern: arena.allocate(size: kind.size, align: kind.align))
        owner = arena
    } else if let heap = resolveCInteropNativeHeapBox(from: scope) {
        address = UInt(bitPattern: heap.allocate(size: kind.size, align: kind.align))
        owner = heap
    } else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeCInteropVarBox(
            address: address, pointeeTypeID: typeID, owner: owner
        ),
        typeID: typeID != 0 ? typeID : cinteropCVariableTypeID
    )
}

@_cdecl("kk_arena_alloc_array")
public func kk_arena_alloc_array(_ scope: Int, _ count: Int, _ typeToken: Int) -> Int {
    let elementCount = kk_unbox_long(count)
    guard elementCount >= 0,
          let kind = runtimeCInteropVarKind(forTypeToken: typeToken)
    else {
        return 0
    }
    let typeID = runtimeCInteropNominalTypeID(forTypeToken: typeToken)
    let byteSize = kind.size * max(1, elementCount)
    let address: UInt
    if let arena = resolveCInteropArenaBox(from: scope) {
        address = UInt(bitPattern: arena.allocate(size: byteSize, align: kind.align))
    } else if let heap = resolveCInteropNativeHeapBox(from: scope) {
        address = UInt(bitPattern: heap.allocate(size: byteSize, align: kind.align))
    } else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeCPointerBox(address: address, pointeeTypeID: typeID),
        typeID: cinteropCPointerTypeID
    )
}

@_cdecl("kk_native_placement_free")
public func kk_native_placement_free(_ scope: Int, _ pointerHandle: Int) -> Int {
    let address: UInt
    if let ptr = resolveCPointerBox(from: pointerHandle) {
        address = ptr.address
    } else if let opaque = resolveCOpaquePointerBox(from: pointerHandle) {
        address = opaque.address
    } else if let varBox = resolveCInteropVarBox(from: pointerHandle) {
        address = varBox.address
    } else {
        return 0
    }
    if let arena = resolveCInteropArenaBox(from: scope) {
        _ = arena.freeNow(address)
        return 0
    }
    if let heap = resolveCInteropNativeHeapBox(from: scope) {
        _ = heap.freeNow(address)
    }
    return 0
}

@_cdecl("kk_defer_scope_defer")
public func kk_defer_scope_defer(_ scope: Int, _ block: Int) -> Int {
    guard let arena = resolveCInteropArenaBox(from: scope) else { return 0 }
    arena.addDeferred(block)
    return 0
}

/// Propagates the first deferred block exception through `outThrown` after
/// freeing all allocations.
@_cdecl("kk_arena_clear")
public func kk_arena_clear(_ scope: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let arena = resolveCInteropArenaBox(from: scope) else { return 0 }
    arena.clear(outThrown: outThrown)
    return 0
}


@_cdecl("kk_cvar_ptr")
public func kk_cvar_ptr(_ varHandle: Int) -> Int {
    guard let box = resolveCInteropVarBox(from: varHandle) else { return 0 }
    return registerRuntimeObject(
        RuntimeCPointerBox(address: box.address, pointeeTypeID: box.pointeeTypeID),
        typeID: cinteropCPointerTypeID
    )
}

@_cdecl("kk_cvar_raw_ptr")
public func kk_cvar_raw_ptr(_ varHandle: Int) -> Int {
    guard let box = resolveCInteropVarBox(from: varHandle) else { return 0 }
    return registerRuntimeObject(
        RuntimeCInteropNativePtrBox(address: box.address),
        typeID: cinteropNativePtrTypeID
    )
}

//
// `value` properties resolve to `kk_cvar_<kind>_load` reads; assignment lowers
// through the `_store` twin selected by the property-store convention.

@inline(__always)
private func cinteropLoadValue(_ varHandle: Int, _ read: (UnsafeRawPointer) -> Int) -> Int {
    guard let box = resolveCInteropVarBox(from: varHandle),
          let ptr = UnsafeRawPointer(bitPattern: box.address)
    else {
        return 0
    }
    return read(ptr)
}

@inline(__always)
private func cinteropStoreValue(_ varHandle: Int, _ write: (UnsafeMutableRawPointer) -> Void) -> Int {
    guard let box = resolveCInteropVarBox(from: varHandle),
          let ptr = UnsafeMutableRawPointer(bitPattern: box.address)
    else {
        return 0
    }
    write(ptr)
    return 0
}

// Loads return raw scalars (primitive KIR temps carry raw values, like
// `__kk_atomic_int_load`); stores consume raw scalars via the passthrough
// unboxers so either representation is accepted.
@_cdecl("kk_cvar_bool_load")
public func kk_cvar_bool_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in ptr.load(as: UInt8.self) != 0 ? 1 : 0 }
}

@_cdecl("kk_cvar_bool_store")
public func kk_cvar_bool_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: UInt8(kk_unbox_bool(value) != 0 ? 1 : 0), as: UInt8.self)
    }
}

@_cdecl("kk_cvar_byte_load")
public func kk_cvar_byte_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(Int8(bitPattern: ptr.load(as: UInt8.self))) }
}

@_cdecl("kk_cvar_byte_store")
public func kk_cvar_byte_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: UInt8(truncatingIfNeeded: kk_unbox_int(value)), as: UInt8.self)
    }
}

@_cdecl("kk_cvar_ubyte_load")
public func kk_cvar_ubyte_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(ptr.load(as: UInt8.self)) }
}

@_cdecl("kk_cvar_ubyte_store")
public func kk_cvar_ubyte_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: UInt8(truncatingIfNeeded: kk_unbox_int(value)), as: UInt8.self)
    }
}

@_cdecl("kk_cvar_short_load")
public func kk_cvar_short_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(ptr.load(as: Int16.self)) }
}

@_cdecl("kk_cvar_short_store")
public func kk_cvar_short_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: Int16(truncatingIfNeeded: kk_unbox_int(value)), as: Int16.self)
    }
}

@_cdecl("kk_cvar_ushort_load")
public func kk_cvar_ushort_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(ptr.load(as: UInt16.self)) }
}

@_cdecl("kk_cvar_ushort_store")
public func kk_cvar_ushort_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: UInt16(truncatingIfNeeded: kk_unbox_int(value)), as: UInt16.self)
    }
}

@_cdecl("kk_cvar_int_load")
public func kk_cvar_int_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(ptr.load(as: Int32.self)) }
}

@_cdecl("kk_cvar_int_store")
public func kk_cvar_int_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: Int32(truncatingIfNeeded: kk_unbox_int(value)), as: Int32.self)
    }
}

@_cdecl("kk_cvar_uint_load")
public func kk_cvar_uint_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(ptr.load(as: UInt32.self)) }
}

@_cdecl("kk_cvar_uint_store")
public func kk_cvar_uint_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: UInt32(truncatingIfNeeded: kk_unbox_int(value)), as: UInt32.self)
    }
}

@_cdecl("kk_cvar_long_load")
public func kk_cvar_long_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(ptr.load(as: Int64.self)) }
}

@_cdecl("kk_cvar_long_store")
public func kk_cvar_long_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: Int64(kk_unbox_long(value)), as: Int64.self)
    }
}

@_cdecl("kk_cvar_ulong_load")
public func kk_cvar_ulong_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in Int(truncatingIfNeeded: ptr.load(as: UInt64.self)) }
}

@_cdecl("kk_cvar_ulong_store")
public func kk_cvar_ulong_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(of: UInt64(bitPattern: Int64(kk_unbox_ulong(value))), as: UInt64.self)
    }
}

@_cdecl("kk_cvar_float_load")
public func kk_cvar_float_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in
        Int(ptr.load(as: Float.self).bitPattern)
    }
}

@_cdecl("kk_cvar_float_store")
public func kk_cvar_float_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(
            of: Float(bitPattern: UInt32(truncatingIfNeeded: kk_unbox_float(value))),
            as: Float.self
        )
    }
}

@_cdecl("kk_cvar_double_load")
public func kk_cvar_double_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in
        Int(truncatingIfNeeded: ptr.load(as: Double.self).bitPattern)
    }
}

@_cdecl("kk_cvar_double_store")
public func kk_cvar_double_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        ptr.storeBytes(
            of: Double(bitPattern: UInt64(truncatingIfNeeded: kk_unbox_double(value))),
            as: Double.self
        )
    }
}

/// `CPointerVar.value` reads a pointer word out of storage; a nonzero word is
/// boxed as a CPointer handle, zero reads back as `null` (the sentinel).
@_cdecl("kk_cvar_cpointer_load")
public func kk_cvar_cpointer_load(_ varHandle: Int) -> Int {
    cinteropLoadValue(varHandle) { ptr in
        let address = ptr.load(as: UInt.self)
        guard address != 0 else { return runtimeNullSentinelInt }
        return registerRuntimeObject(
            RuntimeCPointerBox(address: address, pointeeTypeID: 0),
            typeID: cinteropCPointerTypeID
        )
    }
}

@_cdecl("kk_cvar_cpointer_store")
public func kk_cvar_cpointer_store(_ varHandle: Int, _ value: Int) -> Int {
    cinteropStoreValue(varHandle) { ptr in
        let address: UInt
        if let box = resolveCPointerBox(from: value) {
            address = box.address
        } else if let opaque = resolveCOpaquePointerBox(from: value) {
            address = opaque.address
        } else {
            address = 0
        }
        ptr.storeBytes(of: address, as: UInt.self)
    }
}


@_cdecl("kk_cpointer_pointed")
public func kk_cpointer_pointed(_ handle: Int) -> Int {
    guard let box = resolveCPointerBox(from: handle) else { return 0 }
    return registerRuntimeObject(
        RuntimeCInteropVarBox(
            address: box.address, pointeeTypeID: box.pointeeTypeID, owner: nil
        ),
        typeID: cinteropVariableClassID(for: box.pointeeTypeID)
    )
}

/// `index` arrives as a boxed Int.
@_cdecl("kk_cpointer_get")
public func kk_cpointer_get(_ handle: Int, _ index: Int) -> Int {
    guard let box = resolveCPointerBox(from: handle) else { return 0 }
    let kind = runtimeCInteropVarKind(forNominalTypeID: box.pointeeTypeID) ?? .aggregate
    let offset = UInt(bitPattern: kk_unbox_int(index)) * UInt(kind.size)
    return registerRuntimeObject(
        RuntimeCInteropVarBox(
            address: box.address + offset,
            pointeeTypeID: box.pointeeTypeID,
            owner: nil
        ),
        typeID: cinteropVariableClassID(for: box.pointeeTypeID)
    )
}

@_cdecl("kk_cpointer_reinterpret")
public func kk_cpointer_reinterpret(_ handle: Int, _ typeToken: Int) -> Int {
    guard let box = resolveCPointerBox(from: handle) else { return 0 }
    let typeID = runtimeCInteropNominalTypeID(forTypeToken: typeToken)
    return registerRuntimeObject(
        RuntimeCPointerBox(address: box.address, pointeeTypeID: typeID),
        typeID: cinteropCPointerTypeID
    )
}

@_cdecl("kk_interpret_cpointer")
public func kk_interpret_cpointer(_ nativePtrHandle: Int, _ typeToken: Int) -> Int {
    guard let box = resolveCInteropNativePtrBox(from: nativePtrHandle), box.address != 0 else {
        return runtimeNullSentinelInt
    }
    let typeID = runtimeCInteropNominalTypeID(forTypeToken: typeToken)
    return registerRuntimeObject(
        RuntimeCPointerBox(address: box.address, pointeeTypeID: typeID),
        typeID: cinteropCPointerTypeID
    )
}

/// `Long.toCPointer<T>()` / `NativePtr.toCPointer<T>()` — resolves a boxed
/// Long or NativePtr box; nonzero addresses box, zero produces null.
@_cdecl("kk_long_to_cpointer")
public func kk_long_to_cpointer(_ value: Int, _ typeToken: Int) -> Int {
    let address: UInt
    if let ptrBox = resolveCInteropNativePtrBox(from: value) {
        address = ptrBox.address
    } else {
        address = UInt(bitPattern: kk_unbox_long(value))
    }
    guard address != 0 else { return runtimeNullSentinelInt }
    let typeID = runtimeCInteropNominalTypeID(forTypeToken: typeToken)
    return registerRuntimeObject(
        RuntimeCPointerBox(address: address, pointeeTypeID: typeID),
        typeID: cinteropCPointerTypeID
    )
}

@_cdecl("kk_cpointer_toKString")
public func kk_cpointer_toKString(_ handle: Int) -> Int {
    guard let box = resolveCPointerBox(from: handle),
          box.address != 0,
          let bytes = UnsafePointer<UInt8>(bitPattern: box.address)
    else {
        return runtimeNullSentinelInt
    }
    var collected: [UInt8] = []
    var index = 0
    while bytes[index] != 0 {
        collected.append(bytes[index])
        index += 1
    }
    return runtimeMakeStringRaw(String(decoding: collected, as: UTF8.self))
}


@_cdecl("kk_string_to_cptr")
public func kk_string_to_cptr(_ scope: Int, _ stringHandle: Int) -> Int {
    guard let swiftString = extractString(from: UnsafeMutableRawPointer(bitPattern: stringHandle))
    else {
        return runtimeNullSentinelInt
    }
    var bytes = Array(swiftString.utf8)
    bytes.append(0)
    let address: UInt
    if let arena = resolveCInteropArenaBox(from: scope) {
        address = UInt(bitPattern: arena.allocate(size: bytes.count, align: 1))
    } else if let heap = resolveCInteropNativeHeapBox(from: scope) {
        address = UInt(bitPattern: heap.allocate(size: bytes.count, align: 1))
    } else {
        return runtimeNullSentinelInt
    }
    bytes.withUnsafeBytes { src in
        if let base = src.baseAddress, let dst = UnsafeMutableRawPointer(bitPattern: address) {
            dst.copyMemory(from: base, byteCount: bytes.count)
        }
    }
    return registerRuntimeObject(
        RuntimeCPointerBox(address: address, pointeeTypeID: cinteropByteVarTypeID),
        typeID: cinteropCPointerTypeID
    )
}

/// `CValuesRef.getPointer(scope)` — copies the buffered C bytes into the scope
/// so the returned pointer outlives the CValues handle.
@_cdecl("kk_cvalues_get_pointer")
public func kk_cvalues_get_pointer(_ cvaluesHandle: Int, _ scope: Int) -> Int {
    guard cvaluesHandle != 0, cvaluesHandle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: cvaluesHandle),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let box = tryCast(ptr, to: RuntimeCValuesBox.self),
          let base = box.storage.baseAddress
    else {
        return runtimeNullSentinelInt
    }
    let byteCount = box.storage.count
    let address: UInt
    if let arena = resolveCInteropArenaBox(from: scope) {
        address = UInt(bitPattern: arena.allocate(size: byteCount, align: 8))
    } else if let heap = resolveCInteropNativeHeapBox(from: scope) {
        address = UInt(bitPattern: heap.allocate(size: byteCount, align: 8))
    } else {
        return runtimeNullSentinelInt
    }
    UnsafeMutableRawPointer(bitPattern: address)?.copyMemory(from: base, byteCount: byteCount)
    return registerRuntimeObject(
        RuntimeCPointerBox(address: address, pointeeTypeID: cinteropByteVarTypeID),
        typeID: cinteropCPointerTypeID
    )
}


/// `NativePtr.toLong()` — raw Long (primitive values are raw in KIR temps).
@_cdecl("kk_native_ptr_toLong")
public func kk_native_ptr_toLong(_ handle: Int) -> Int {
    guard let box = resolveCInteropNativePtrBox(from: handle) else { return 0 }
    return Int(bitPattern: box.address)
}

@_cdecl("kk_native_null_ptr")
public func kk_native_null_ptr() -> Int {
    registerRuntimeObject(
        RuntimeCInteropNativePtrBox(address: 0),
        typeID: cinteropNativePtrTypeID
    )
}


/// Returns a raw Long.
@_cdecl("kk_cinterop_sizeof")
public func kk_cinterop_sizeof(_ typeToken: Int) -> Int {
    runtimeCInteropVarKind(forTypeToken: typeToken)?.size ?? 0
}

/// Returns a raw Long.
@_cdecl("kk_cinterop_alignof")
public func kk_cinterop_alignof(_ typeToken: Int) -> Int {
    runtimeCInteropVarKind(forTypeToken: typeToken)?.align ?? 0
}
