package kotlinx.atomicfu

/**
 * All atomicfu declarations are annotated with [@OptionalJsName][kotlin.js.JsName] to have specific names in JS output.
 * JS output transformer relies on these mangled names to erase all atomicfu references.
 */

internal const val ATOMIC_REF_FACTORY = "atomic\$ref\$"
internal const val ATOMIC_REF_FACTORY_BINARY_COMPATIBILITY = "atomic\$ref\$1"
internal const val ATOMIC_INT_FACTORY = "atomic\$int\$"
internal const val ATOMIC_INT_FACTORY_BINARY_COMPATIBILITY = "atomic\$int\$1"
internal const val ATOMIC_LONG_FACTORY = "atomic\$long\$"
internal const val ATOMIC_LONG_FACTORY_BINARY_COMPATIBILITY = "atomic\$long\$1"
internal const val ATOMIC_BOOLEAN_FACTORY = "atomic\$boolean\$"
internal const val ATOMIC_BOOLEAN_FACTORY_BINARY_COMPATIBILITY = "atomic\$boolean\$1"

internal const val ATOMIC_VALUE = "kotlinx\$atomicfu\$value"

internal const val COMPARE_AND_SET = "atomicfu\$compareAndSet"
internal const val GET_AND_SET = "atomicfu\$getAndSet"
internal const val GET_AND_INCREMENT = "atomicfu\$getAndIncrement"
internal const val GET_AND_INCREMENT_LONG = "atomicfu\$getAndIncrement\$long"
internal const val GET_AND_DECREMENT = "atomicfu\$getAndDecrement"
internal const val GET_AND_DECREMENT_LONG = "atomicfu\$getAndDecrement\$long"
internal const val INCREMENT_AND_GET = "atomicfu\$incrementAndGet"
internal const val INCREMENT_AND_GET_LONG = "atomicfu\$incrementAndGet\$long"
internal const val DECREMENT_AND_GET = "atomicfu\$decrementAndGet"
internal const val DECREMENT_AND_GET_LONG = "atomicfu\$decrementAndGet\$long"
internal const val GET_AND_ADD = "atomicfu\$getAndAdd"
internal const val GET_AND_ADD_LONG = "atomicfu\$getAndAdd\$long"
internal const val ADD_AND_GET = "atomicfu\$addAndGet"
internal const val ADD_AND_GET_LONG = "atomicfu\$addAndGet\$long"

internal const val ATOMIC_ARRAY_OF_NULLS = "atomicfu\$AtomicRefArray\$ofNulls"
internal const val ATOMIC_INT_ARRAY = "atomicfu\$AtomicIntArray\$int"
internal const val ATOMIC_LONG_ARRAY = "atomicfu\$AtomicLongArray\$long"
internal const val ATOMIC_BOOLEAN_ARRAY = "atomicfu\$AtomicBooleanArray\$boolean"
internal const val ATOMIC_REF_ARRAY = "atomicfu\$AtomicRefArray\$ref"

internal const val ARRAY_SIZE = "atomicfu\$size"
internal const val ARRAY_ELEMENT_GET = "atomicfu\$get"

internal const val REENTRANT_LOCK = "atomicfu\$reentrantLock"

internal const val TRACE_FACTORY_FUNCTION = "atomicfu\$Trace"
internal const val TRACE_BASE_CONSTRUCTOR = "atomicfu\$TraceBase"
internal const val TRACE_NAMED = "atomicfu\$Trace\$named"
internal const val TRACE_FORMAT_CLASS = "atomicfu\$TraceFormat"
internal const val TRACE_FORMAT_FORMAT_FUNCTION = "atomicfu\$TraceFormat\$format"

// [1234] used as a suffix is the number of arguments in the append overload
internal const val TRACE_APPEND_1 = "atomicfu\$Trace\$append\$1"
internal const val TRACE_APPEND_2 = "atomicfu\$Trace\$append\$2"
internal const val TRACE_APPEND_3 = "atomicfu\$Trace\$append\$3"
internal const val TRACE_APPEND_4 = "atomicfu\$Trace\$append\$4"
