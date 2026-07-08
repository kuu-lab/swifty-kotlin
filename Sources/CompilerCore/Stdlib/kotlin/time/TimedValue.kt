package kotlin.time

// KSP-472
// TimedValue member accessors.
// Migration source: Sources/Runtime/RuntimeDuration.swift
//   kk_timedvalue_value, kk_timedvalue_duration
//
// Both properties delegate to __kk_timedvalue_* bridges backed by kk_* ABI
// functions. Bridge stubs are registered in
// HeaderHelpers+SyntheticDurationStubs.swift.
//
// TimedValue's constructor (kk_timedvalue_new) is only invoked from the
// measureTimedValue lowering (CallLowerer+StdlibLoops.swift), so it has no
// Kotlin-source-visible equivalent.

public val TimedValue.value: Any?
    get() = this.__kk_timedvalue_value()

public val TimedValue.duration: Duration
    get() = this.__kk_timedvalue_duration()
