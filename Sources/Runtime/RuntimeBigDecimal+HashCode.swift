/// JDK-compatible `BigDecimal.hashCode()` for a canonical decimal string:
/// `31 * unscaledValue.hashCode() + scale`, where `BigInteger.hashCode()` folds
/// the big-endian 32-bit magnitude words as `31 * h + word` and applies the sign.
/// The JDK's compact-long path computes the same value (KUU-4630).
func runtimeBigDecimalJvmHashCode(_ canonical: String) -> Int32 {
    guard let parts = try? runtimeBigDecimalParts(canonical) else { return 0 }
    // Little-endian base-2^32 magnitude via digit-wise multiply-accumulate.
    var words: [UInt32] = []
    for scalar in parts.digits.unicodeScalars {
        var carry = UInt64(scalar.value - 48)
        for index in words.indices {
            let product = UInt64(words[index]) * 10 + carry
            words[index] = UInt32(truncatingIfNeeded: product)
            carry = product >> 32
        }
        if carry != 0 { words.append(UInt32(carry)) }
    }
    var magnitudeHash: Int32 = 0
    for word in words.reversed() {
        magnitudeHash = 31 &* magnitudeHash &+ Int32(bitPattern: word)
    }
    let signedHash: Int32 = words.isEmpty ? 0 : (parts.negative ? 0 &- magnitudeHash : magnitudeHash)
    return 31 &* signedHash &+ Int32(truncatingIfNeeded: parts.scale)
}
