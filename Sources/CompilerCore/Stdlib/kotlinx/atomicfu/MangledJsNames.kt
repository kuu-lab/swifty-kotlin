package kotlinx.atomicfu

/**
 * All atomicfu declarations are annotated with [@OptionalJsName][kotlin.js.JsName] to have specific names in JS output.
 * JS output transformer relies on these mangled names to erase all atomicfu references.
 */

internal const val ATOMIC_ARRAY_OF_NULLS = "atomicfu\$AtomicRefArray\$ofNulls"
internal const val ATOMIC_INT_ARRAY = "atomicfu\$AtomicIntArray\$int"
internal const val ATOMIC_LONG_ARRAY = "atomicfu\$AtomicLongArray\$long"
internal const val ATOMIC_BOOLEAN_ARRAY = "atomicfu\$AtomicBooleanArray\$boolean"
internal const val ATOMIC_REF_ARRAY = "atomicfu\$AtomicRefArray\$ref"

internal const val ARRAY_SIZE = "atomicfu\$size"
internal const val ARRAY_ELEMENT_GET = "atomicfu\$get"

internal const val TRACE_BASE_CONSTRUCTOR = "atomicfu\$TraceBase"
internal const val TRACE_FORMAT_CLASS = "atomicfu\$TraceFormat"
internal const val TRACE_FORMAT_FORMAT_FUNCTION = "atomicfu\$TraceFormat\$format"

// [1234] used as a suffix is the number of arguments in the append overload
internal const val TRACE_APPEND_1 = "atomicfu\$Trace\$append\$1"
internal const val TRACE_APPEND_2 = "atomicfu\$Trace\$append\$2"
internal const val TRACE_APPEND_3 = "atomicfu\$Trace\$append\$3"
internal const val TRACE_APPEND_4 = "atomicfu\$Trace\$append\$4"
