package kotlin

// KSP-744: kotlin.LazyThreadSafetyMode bundled enum.
public enum class LazyThreadSafetyMode {
    SYNCHRONIZED,
    PUBLICATION,
    NONE
}

public val LazyThreadSafetyMode.entries: kotlin.enums.EnumEntries<LazyThreadSafetyMode>
    get() = enumEntries<LazyThreadSafetyMode>()

// valueOf and values are provided by the generic enum synthesis pipeline;
// no target-specific stdlib bridge is required for this enum.
