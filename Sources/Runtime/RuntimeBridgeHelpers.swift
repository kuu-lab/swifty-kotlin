//
// RuntimeBridgeHelpers.swift
// KSwiftK Runtime
//
// Lightweight inline helpers to eliminate repetitive boilerplate in @_cdecl runtime bridges:
// - Initializing outThrown pointer to 0
// - Catching and converting Swift throws to runtime-thrown handles
// - Unwrapping handles safely
//

import Foundation

/// Thrown within a runtime bridge closure to indicate an explicit runtime error handle.
public struct RuntimeThrownHandle: Error, Sendable {
    public let handle: Int
    public init(_ handle: Int) {
        self.handle = handle
    }
}

/// Executes a throwing bridge closure, initializing `outThrown` to 0 and
/// capturing any thrown errors into `outThrown`.
///
/// Returns 0 (or `defaultOnFailure`) on failure.
@inline(__always)
public func runtimeThrowingBridge<R: BinaryInteger>(
    _ outThrown: UnsafeMutablePointer<Int>?,
    defaultOnFailure: R = 0,
    _ body: () throws -> R
) -> R {
    runtimeBridgeRun(outThrown, defaultOnFailure: defaultOnFailure, body)
}

/// Void-returning variant for bridges whose Kotlin-facing result carries no
/// value (Unit externals). Failures are reported through `outThrown` only.
@inline(__always)
public func runtimeThrowingBridge(
    _ outThrown: UnsafeMutablePointer<Int>?,
    _ body: () throws -> Void
) {
    _ = runtimeBridgeRun(outThrown, defaultOnFailure: 0) {
        try body()
        return 0
    }
}

/// Value-returning variant for bridges whose result is not a `BinaryInteger`
/// (pointers, optionals, tuples, `Bool`, ...). `defaultOnFailure` is required
/// so integer call sites keep resolving to the `BinaryInteger` overload.
@inline(__always)
public func runtimeThrowingBridge<R>(
    _ outThrown: UnsafeMutablePointer<Int>?,
    defaultOnFailure: R,
    _ body: () throws -> R
) -> R {
    runtimeBridgeRun(outThrown, defaultOnFailure: defaultOnFailure, body)
}

@inline(__always)
func runtimeBridgeRun<R>(
    _ outThrown: UnsafeMutablePointer<Int>?,
    defaultOnFailure: R,
    _ body: () throws -> R
) -> R {
    outThrown?.pointee = 0
    do {
        return try body()
    } catch let thrown as RuntimeThrownHandle {
        runtimeSetThrown(outThrown, thrown.handle)
        return defaultOnFailure
    } catch {
        runtimeSetThrown(outThrown, runtimeAllocateException(message: String(describing: error)))
        return defaultOnFailure
    }
}

