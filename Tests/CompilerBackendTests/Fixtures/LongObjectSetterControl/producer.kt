package longobjsetter

object HeapBox {
    // Deliberate no-op Long setters declared before the live ones: an
    // imported `set` call that bound to the wrong same-typed accessor
    // would land here and silently drop the write.
    var silentA: Long
        get() = 0L
        set(value) {}

    var silentB: Long
        get() = 0L
        set(value) {}

    var minBytes: Long
        get() = __minBytes
        set(value) { __minBytes = value }

    private var __minBytes: Long = 5000L

    var maxBytes: Long
        get() = __maxBytes
        set(value) { __maxBytes = value }

    private var __maxBytes: Long = 6000L

    var doubled: Long
        get() = __doubled
        set(value) { __doubled = value * 2 }

    private var __doubled: Long = 7L

    var flag: Boolean
        get() = __flag
        set(value) { __flag = value }

    private var __flag: Boolean = true

    var ratio: Double
        get() = __ratio
        set(value) { __ratio = value }

    private var __ratio: Double = 0.9

    var plainLong: Long = 42L
}
