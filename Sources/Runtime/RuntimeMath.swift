
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public func kk_double_positive_infinity() -> Int {
    kk_double_to_bits(Double.infinity)
}

public func kk_double_negative_infinity() -> Int {
    kk_double_to_bits(-Double.infinity)
}

public func kk_double_nan() -> Int {
    kk_double_to_bits(Double.nan)
}

public func kk_double_max_value() -> Int {
    kk_double_to_bits(Double.greatestFiniteMagnitude)
}

/// Kotlin: Double.MIN_VALUE  (note: Kotlin MIN_VALUE = leastNonzeroMagnitude, not -MAX_VALUE)
public func kk_double_min_value() -> Int {
    kk_double_to_bits(Double.leastNonzeroMagnitude)
}
