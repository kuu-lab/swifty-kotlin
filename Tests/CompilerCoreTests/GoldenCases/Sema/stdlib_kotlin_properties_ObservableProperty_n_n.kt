package golden.sema

import kotlin.properties.ObservableProperty
import kotlin.reflect.KProperty

class Named(initial: String) : ObservableProperty<String>(initial)

fun makeAnon(value: Int): ObservableProperty<Int> {
    return object : ObservableProperty<Int>(value) {
        override fun afterChange(property: KProperty<*>, oldValue: Int, newValue: Int) {}
    }
}

fun readName(named: Named): String {
    return named.toString()
}
