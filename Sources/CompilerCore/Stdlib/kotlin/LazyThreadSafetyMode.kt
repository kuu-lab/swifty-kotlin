package kotlin

// KSP-744: kotlin.LazyThreadSafetyMode bundled enum.
public enum class LazyThreadSafetyMode {
    SYNCHRONIZED,
    PUBLICATION,
    NONE
}

// Enum entries, valueOf, and values are provided by the generic enum synthesis
// pipeline; no target-specific stdlib bridge is required for this enum.
