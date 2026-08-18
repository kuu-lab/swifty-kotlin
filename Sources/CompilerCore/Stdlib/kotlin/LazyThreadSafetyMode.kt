package kotlin

// KSP-744: kotlin.LazyThreadSafetyMode bundled enum.
public enum class LazyThreadSafetyMode {
    SYNCHRONIZED,
    PUBLICATION,
    NONE
}
