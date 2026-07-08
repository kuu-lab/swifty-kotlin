package golden.diagnostics

import kotlin.properties.Delegates
import kotlin.reflect.KProperty

class NoOperators

class GetValueOnly {
    operator fun getValue(thisRef: Any?, property: Any?): Int = 0
}

class NoGetValueDelegate

class ProviderWithoutGetValue {
    operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): NoGetValueDelegate = NoGetValueDelegate()
}

// Missing 'getValue' entirely (val delegate).
val missingGetValue: Int by NoOperators()

// Has 'getValue' but missing 'setValue' required for a mutable property.
var missingSetValue: Int by GetValueOnly()

// Missing both operators on a mutable property.
var missingBoth: Int by NoOperators()

// 'provideDelegate' resolves, but the delegate it returns still lacks 'getValue'.
val viaProvideDelegateMissingGetValue: Int by ProviderWithoutGetValue()

// Recognized stdlib delegate factories must stay silent (KSP-491/492 tracks
// wiring these to the operator convention; this is not this diagnostic's job).
val lazyIsFine: String by lazy { "ok" }

var observableIsFine: Int by Delegates.observable(0) { _, _, _ -> }
