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

// Has a valid getValue directly, but provideDelegate hands off to a type that
// doesn't: the effective (post-provideDelegate) delegate must still be
// validated, not the provider's own getValue.
class ProvidedWithoutGetValue

class ProviderWhoseOwnGetValueIsIgnored {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = 1
    operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): ProvidedWithoutGetValue =
        ProvidedWithoutGetValue()
}

// A user-defined member function that merely happens to be named "lazy" —
// must not be confused with the stdlib `lazy { }` factory.
class FakeLazyHolder {
    fun lazy(): FakeLazyHolder = this
}

// Missing 'getValue' entirely (val delegate).
val missingGetValue: Int by NoOperators()

// Has 'getValue' but missing 'setValue' required for a mutable property.
var missingSetValue: Int by GetValueOnly()

// Missing both operators on a mutable property.
var missingBoth: Int by NoOperators()

// 'provideDelegate' resolves, but the delegate it returns still lacks 'getValue'.
val viaProvideDelegateMissingGetValue: Int by ProviderWithoutGetValue()

// The provider's own getValue must not mask the missing getValue on the type
// provideDelegate actually returns.
val viaProvideDelegateOverridingValidGetValue: Int by ProviderWhoseOwnGetValueIsIgnored()

// A same-named custom member call, not the stdlib factory: must still be validated.
val viaCustomMemberNamedLazy: Int by FakeLazyHolder().lazy()

// Recognized stdlib delegate factories must stay silent (KSP-491/492 tracks
// wiring these to the operator convention; this is not this diagnostic's job).
val lazyIsFine: String by lazy { "ok" }

var observableIsFine: Int by Delegates.observable(0) { _, _, _ -> }
