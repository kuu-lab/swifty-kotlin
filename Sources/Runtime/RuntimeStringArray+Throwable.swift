import Foundation
import RuntimeABI

func runtimeThrowableBox(from raw: Int) -> RuntimeThrowableBox? {
    resolveRuntimeHandle(raw, as: RuntimeThrowableBox.self)
}

private let runtimeThrowableToStringVtableMethod: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int =
    __kk_throwable_toString

private let runtimeThrowableStackTraceVtableMethod: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int =
    __kk_throwable_rawStackFrames

private let runtimeThrowableMessageVtableMethod: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return __kk_throwable_message(raw)
}

private let runtimeThrowableCauseVtableMethod: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return __kk_throwable_cause(raw)
}

// Keep these slots aligned with the bundled Throwable layout: methods are
// numbered first (getStackTrace, toString), then the open property getters
// (message, cause).
enum RuntimeThrowableVtableSlot {
    static let getStackTrace = 0
    static let toString = 1
    static let message = 2
    static let cause = 3
}

func runtimeThrowableVtableMethodRaw(_ receiver: Int, slot: Int) -> Int? {
    guard runtimeIsThrowableRaw(receiver) else {
        return nil
    }
    if runtimeThrowableBox(from: receiver) == nil,
       let pointer = UnsafeMutableRawPointer(bitPattern: receiver)
    {
        let objectKey = UInt(bitPattern: pointer)
        if let registered = runtimeStorage.withMetadataLock({ state in
            state.objectVtableMethods[objectKey]?[slot]
        }), registered != 0 {
            return registered
        }
    }
    switch slot {
    case RuntimeThrowableVtableSlot.getStackTrace:
        return unsafeBitCast(runtimeThrowableStackTraceVtableMethod, to: Int.self)
    case RuntimeThrowableVtableSlot.toString:
        return unsafeBitCast(runtimeThrowableToStringVtableMethod, to: Int.self)
    case RuntimeThrowableVtableSlot.message:
        return unsafeBitCast(runtimeThrowableMessageVtableMethod, to: Int.self)
    case RuntimeThrowableVtableSlot.cause:
        return unsafeBitCast(runtimeThrowableCauseVtableMethod, to: Int.self)
    default:
        return nil
    }
}

/// `message` of a Kotlin-defined Throwable subclass, read through its vtable
/// slot so an `override val message` is honoured; falls back to the stored
/// constructor message when there is no override or the getter throws.
func runtimeSourceThrowableMessage(_ raw: Int, object: RuntimeObjectBox) -> String? {
    guard let methodRaw = runtimeThrowableVtableMethodRaw(raw, slot: RuntimeThrowableVtableSlot.message),
          methodRaw != unsafeBitCast(runtimeThrowableMessageVtableMethod, to: Int.self)
    else {
        return object.throwableMessage
    }
    let method = unsafeBitCast(methodRaw, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let messageRaw = method(raw, &thrown)
    if thrown != 0 {
        return object.throwableMessage
    }
    if messageRaw == runtimeNullSentinelInt || messageRaw == 0 {
        return nil
    }
    return extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw))
}

func runtimeThrowableToString(_ receiver: Int) -> String? {
    guard let methodRaw = runtimeThrowableVtableMethodRaw(
        receiver,
        slot: RuntimeThrowableVtableSlot.toString
    ) else {
        return nil
    }
    let method = unsafeBitCast(
        methodRaw,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    guard let rendered = UnsafeMutableRawPointer(bitPattern: method(receiver, nil)) else {
        return nil
    }
    return extractString(from: rendered)
}

private func runtimeThrowableStackTraceText(from throwableRaw: Int) -> String {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return ""
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return ""
    }
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        return throwable.renderedMessage
    }
    if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
        return cancellation.message ?? "CancellationException"
    }
    return ""
}

/// RuntimeObjectBox stores only the stable nominal type ID. Keep the names of
/// bundled throwable classes here because the hashed ID is intentionally not
/// reversible; user-defined types are resolved through registered metadata.
private let runtimeSourceThrowableNames = [
    ("kotlin.Error", "Error"),
    ("kotlin.Exception", "Exception"),
    ("kotlin.RuntimeException", "RuntimeException"),
    ("kotlin.IllegalArgumentException", "IllegalArgumentException"),
    ("kotlin.IllegalStateException", "IllegalStateException"),
    ("kotlin.ConcurrentModificationException", "ConcurrentModificationException"),
    ("kotlin.UnsupportedOperationException", "UnsupportedOperationException"),
    ("kotlin.NumberFormatException", "NumberFormatException"),
    ("kotlin.NullPointerException", "NullPointerException"),
    ("kotlin.ClassCastException", "ClassCastException"),
    ("kotlin.TypeCastException", "TypeCastException"),
    ("kotlin.AssertionError", "AssertionError"),
    ("kotlin.NoSuchElementException", "NoSuchElementException"),
    ("kotlin.ArithmeticException", "ArithmeticException"),
    ("kotlin.NoWhenBranchMatchedException", "NoWhenBranchMatchedException"),
    ("kotlin.UninitializedPropertyAccessException", "UninitializedPropertyAccessException"),
    ("kotlin.IndexOutOfBoundsException", "IndexOutOfBoundsException"),
    ("kotlin.ArrayIndexOutOfBoundsException", "ArrayIndexOutOfBoundsException"),
    ("java.lang.StringIndexOutOfBoundsException", "StringIndexOutOfBoundsException"),
    ("kotlin.KotlinNothingValueException", "KotlinNothingValueException"),
    ("kotlin.OutOfMemoryError", "OutOfMemoryError"),
    ("kotlin.NotImplementedError", "NotImplementedError"),
    ("kotlin.text.CharacterCodingException", "CharacterCodingException"),
    ("java.nio.charset.MalformedInputException", "MalformedInputException"),
    ("java.nio.charset.CharacterCodingException", "CharacterCodingException"),
    ("kotlin.io.FileSystemException", "FileSystemException"),
    ("kotlin.io.FileAlreadyExistsException", "FileAlreadyExistsException"),
    ("kotlin.io.AccessDeniedException", "AccessDeniedException"),
    ("kotlin.io.NoSuchFileException", "NoSuchFileException"),
]

private let runtimeSourceThrowableQualifiedNames: [Int64: String] = {
    Dictionary(uniqueKeysWithValues: runtimeSourceThrowableNames.map { entry in
        (runtimeStableNominalTypeID(fqName: entry.0), entry.0)
    })
}()

func runtimeSourceThrowableQualifiedName(for classID: Int64) -> String {
    // Nominal type tokens use the same payload as classID, with the nominal
    // base and nullability bit encoded around it. KClass metadata therefore
    // provides the source name for user-defined throwable classes as well.
    let payloadMask: UInt64 = (1 << 55) - 1
    let tokenBits = (UInt64(bitPattern: classID) & payloadMask) << 9 | 6
    let typeToken = Int(truncatingIfNeeded: tokenBits)
    return runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.qualifiedName
        ?? runtimeSourceThrowableQualifiedNames[classID]
        ?? "kotlin.Throwable"
}

func runtimeIsThrowableRaw(_ raw: Int) -> Bool {
    guard raw != runtimeNullSentinelInt, raw != 0 else {
        return false
    }
    if runtimeThrowableBox(from: raw) != nil {
        return true
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return false
    }
    let object: RuntimeObjectBox? = runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeObjectBox.self)
    }
    guard let object else {
        return false
    }
    return runtimeIsAssignable(
        sourceTypeID: object.classID,
        targetTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Throwable")
    )
}

/// Header and saved native frames for a single throwable. Kotlin-side
/// formatting walks cause and suppressed chains and adds their prefixes.
/// Also used by the uncaught coroutine-exception reporter
/// (`runtimeHandleUncaughtCoroutineException` in RuntimeCoroutine.swift).
func runtimeThrowableRawStackFrameStrings(from throwableRaw: Int) -> [String] {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return []
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return []
    }
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        let header = runtimeThrowableToString(throwableRaw) ?? throwable.renderedMessage
        return [header] + runtimeThrowableStackFrameLines(throwable.stackTraceAddresses)
    }
    if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        let header = runtimeThrowableToString(throwableRaw) ?? "java.lang.Throwable"
        return [header] + runtimeThrowableStackFrameLines(object.throwableStackTraceAddresses ?? [])
    }
    return []
}

private func runtimeAllocateArrayBox(length: Int) -> Int {
    let arrayBox = RuntimeArrayBox(length: length)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(arrayBox).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("__kk_throwable_new")
public func __kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let text = extractString(from: message)
    let throwableInt = runtimeAllocateThrowable(message: text)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("__kk_throwable_new: allocation returned null")
    }
    return ptr
}

@_cdecl("__kk_throwable_new_with_cause")
public func __kk_throwable_new_with_cause(_ message: UnsafeMutableRawPointer?, _ causeRaw: Int) -> UnsafeMutableRawPointer {
    let text = extractString(from: message)
    let cause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    let throwableInt = runtimeAllocateThrowable(message: text, cause: cause)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("__kk_throwable_new_with_cause: allocation returned null")
    }
    return ptr
}

@_cdecl("__kk_throwable_new_cause")
public func __kk_throwable_new_cause(_ causeRaw: Int) -> UnsafeMutableRawPointer {
    let cause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    let message = runtimeCauseToString(from: cause)
    let throwableInt = runtimeAllocateThrowable(message: message, cause: cause)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("__kk_throwable_new_cause: allocation returned null")
    }
    return ptr
}

@_cdecl("kk_throwable_new_cause")
public func kk_throwable_new_cause(_ causeRaw: Int) -> UnsafeMutableRawPointer {
    let cause = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    let message = runtimeThrowableStackTraceText(from: cause)
    let throwableInt = runtimeAllocateThrowable(message: message.isEmpty ? "Throwable" : message, cause: cause)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableInt) else {
        runtimeStructuredPanic("kk_throwable_new_cause: allocation returned null")
    }
    return ptr
}

@_cdecl("kk_throwable_is_cancellation")
public func kk_throwable_is_cancellation(_ throwableRaw: Int) -> Int {
    kk_is_cancellation_exception(throwableRaw)
}

@_cdecl("__kk_throwable_message")
public func __kk_throwable_message(_ throwableRaw: Int) -> Int {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return runtimeNullSentinelInt
    }
    let message: String?
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        message = throwable.message
    } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
        message = cancellation.message
    } else if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        message = object.throwableMessage
    } else {
        return runtimeNullSentinelInt
    }
    guard let message else { return runtimeNullSentinelInt }
    let box = RuntimeStringBox(message)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Stores a message for a Kotlin-defined Throwable subclass allocated through
/// the ordinary object path rather than a RuntimeThrowableBox bridge.
@_cdecl("__kk_throwable_setMessage")
public func __kk_throwable_setMessage(_ throwableRaw: Int, _ messageRaw: Int) -> Int {
    guard throwableRaw != runtimeNullSentinelInt,
          throwableRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          let object = tryCast(ptr, to: RuntimeObjectBox.self)
    else {
        return throwableRaw
    }
    object.throwableMessage = extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw))
    runtimeRegisterTypeEdge(
        childTypeID: object.classID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Throwable")
    )
    return throwableRaw
}

@_cdecl("__kk_throwable_cause")
public func __kk_throwable_cause(_ throwableRaw: Int) -> Int {
    if throwableRaw == runtimeNullSentinelInt || throwableRaw == 0 {
        return runtimeNullSentinelInt
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) else {
        return runtimeNullSentinelInt
    }
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        return throwable.cause == 0 ? runtimeNullSentinelInt : throwable.cause
    }
    if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        return object.throwableCause == 0 ? runtimeNullSentinelInt : object.throwableCause
    }
    return runtimeNullSentinelInt
}

@_cdecl("__kk_throwable_rawStackFrames")
public func __kk_throwable_rawStackFrames(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    let frameStrings = runtimeThrowableRawStackFrameStrings(from: throwableRaw)
    let arrayRaw = kk_array_new(frameStrings.count)
    guard let arrayBox = runtimeArrayBox(from: arrayRaw) else {
        runtimeStructuredPanic("__kk_throwable_rawStackFrames: array allocation failed")
    }
    for (i, frame) in frameStrings.enumerated() {
        arrayBox[i] = registerRuntimeObject(RuntimeStringBox(frame))
    }
    return arrayRaw
}

@_cdecl("__kk_throwable_toString")
public func __kk_throwable_toString(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    let typeName: String
    let message: String?
    if let throwable = runtimeThrowableBox(from: throwableRaw) {
        typeName = runtimeJVMExceptionFQName(from: throwable.exceptionFQName)
        message = throwable.message
    } else if let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) {
        let object: RuntimeObjectBox? = runtimeStorage.withGCLock { state in
            guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
                return nil
            }
            return tryCast(ptr, to: RuntimeObjectBox.self)
        }
        if let object {
            typeName = runtimeJVMExceptionFQName(from: runtimeSourceThrowableQualifiedName(for: object.classID))
            message = runtimeSourceThrowableMessage(throwableRaw, object: object)
        } else {
            typeName = "kotlin.Throwable"
            message = nil
        }
    } else {
        typeName = "kotlin.Throwable"
        message = nil
    }
    return Int(bitPattern: runtimeMakeStringPointer(runtimeRenderedExceptionMessage(typeName, message)))
}

// MARK: - Advanced exception features (STDLIB-EXCEPT-105)

/// Storage bridge for `Throwable.initCause`: overwrites the cause slot.
@_cdecl("__kk_throwable_setCause")
public func __kk_throwable_setCause(_ throwableRaw: Int, _ causeRaw: Int) -> Int {
    guard throwableRaw != runtimeNullSentinelInt, throwableRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw)
    else {
        return throwableRaw
    }
    let causeValue = (causeRaw == runtimeNullSentinelInt || causeRaw == 0) ? 0 : causeRaw
    if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
        throwable.cause = causeValue
    } else if let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        object.throwableCause = causeValue
        runtimeRegisterTypeEdge(
            childTypeID: object.classID,
            parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Throwable")
        )
    }
    return throwableRaw
}

/// Storage bridge for `Throwable.addSuppressed`: appends to the suppressed list.
@_cdecl("__kk_throwable_appendSuppressed")
public func __kk_throwable_appendSuppressed(_ throwableRaw: Int, _ suppressedRaw: Int) -> Int {
    guard let suppressedPtr = UnsafeMutableRawPointer(bitPattern: suppressedRaw),
          runtimeStorage.withGCLock({ state in
              state.objectPointers.contains(UInt(bitPattern: suppressedPtr))
          }),
          (tryCast(suppressedPtr, to: RuntimeThrowableBox.self) != nil
              || tryCast(suppressedPtr, to: RuntimeObjectBox.self) != nil)
    else {
        return 0
    }

    guard let throwablePtr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          runtimeStorage.withGCLock({ state in
              state.objectPointers.contains(UInt(bitPattern: throwablePtr))
          })
    else {
        return 0
    }

    // Match Kotlin/JVM's major behavior by rejecting self-suppression while
    // remaining ABI-compatible with this non-throwing runtime entrypoint.
    guard throwableRaw != suppressedRaw else { return 0 }
    if let throwable = tryCast(throwablePtr, to: RuntimeThrowableBox.self) {
        throwable.suppressed.append(suppressedRaw)
    } else if let throwable = tryCast(throwablePtr, to: RuntimeObjectBox.self) {
        throwable.throwableSuppressed.append(suppressedRaw)
    } else {
        return 0
    }

    return 0
}

/// Storage bridge for `Throwable.getSuppressed`: the raw `Array<Throwable>`.
@_cdecl("__kk_throwable_suppressedRaw")
public func __kk_throwable_suppressedRaw(_ throwableRaw: Int) -> Int {
    let suppressed: [Int]
    if let throwable = runtimeThrowableBox(from: throwableRaw) {
        suppressed = throwable.suppressed
    } else if let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw),
              let object = tryCast(ptr, to: RuntimeObjectBox.self) {
        suppressed = object.throwableSuppressed
    } else {
        return runtimeAllocateArrayBox(length: 0)
    }

    let arrayBox = RuntimeArrayBox(length: suppressed.count)
    for (i, elem) in suppressed.enumerated() {
        arrayBox[i] = elem
    }
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(arrayBox).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}
