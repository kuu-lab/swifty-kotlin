import Foundation

private struct RuntimeBigDecimalParts {
    var digits: String
    var negative: Bool
    var scale: Int
}

private enum RuntimeBigDecimalError: Error {
    case arithmetic(String)
}

private func runtimeBigDecimalParts(_ source: String) throws -> RuntimeBigDecimalParts {
    var index = source.startIndex
    var negative = false
    if index < source.endIndex, source[index] == "+" || source[index] == "-" {
        negative = source[index] == "-"
        index = source.index(after: index)
    }

    var digits = ""
    var fractionDigits = 0
    while index < source.endIndex, source[index] >= "0", source[index] <= "9" {
        digits.append(source[index])
        index = source.index(after: index)
    }
    if index < source.endIndex, source[index] == "." {
        index = source.index(after: index)
        while index < source.endIndex, source[index] >= "0", source[index] <= "9" {
            digits.append(source[index])
            fractionDigits += 1
            index = source.index(after: index)
        }
    }

    var exponent = 0
    if index < source.endIndex, source[index] == "e" || source[index] == "E" {
        index = source.index(after: index)
        let exponentStart = index
        if index < source.endIndex, source[index] == "+" || source[index] == "-" {
            index = source.index(after: index)
        }
        guard let parsedExponent = Int(source[exponentStart...]) else {
            throw RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range")
        }
        exponent = parsedExponent
    }

    let (scale, overflow) = fractionDigits.subtractingReportingOverflow(exponent)
    guard !overflow, (Int(Int32.min) ... Int(Int32.max)).contains(scale) else {
        throw RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range")
    }
    digits = runtimeNormalizeMagnitude(digits)
    if digits == "0" {
        negative = false
    }
    return RuntimeBigDecimalParts(digits: digits, negative: negative, scale: scale)
}

private func runtimeNormalizeMagnitude(_ digits: String) -> String {
    let trimmed = digits.drop(while: { $0 == "0" })
    return trimmed.isEmpty ? "0" : String(trimmed)
}

private func runtimeCompareMagnitudes(_ lhs: String, _ rhs: String) -> Int {
    let left = runtimeNormalizeMagnitude(lhs)
    let right = runtimeNormalizeMagnitude(rhs)
    if left.count != right.count {
        return left.count < right.count ? -1 : 1
    }
    if left == right { return 0 }
    return left < right ? -1 : 1
}

private func runtimeAddMagnitudes(_ lhs: String, _ rhs: String) -> String {
    let left = Array(lhs.utf8.reversed())
    let right = Array(rhs.utf8.reversed())
    var result: [UInt8] = []
    var carry = 0
    for index in 0 ..< max(left.count, right.count) {
        let a = index < left.count ? Int(left[index] - 48) : 0
        let b = index < right.count ? Int(right[index] - 48) : 0
        let sum = a + b + carry
        result.append(UInt8(sum % 10) + 48)
        carry = sum / 10
    }
    if carry > 0 { result.append(UInt8(carry) + 48) }
    return String(decoding: result.reversed(), as: UTF8.self)
}

/// Subtract rhs from lhs. The caller must ensure lhs >= rhs.
private func runtimeSubtractMagnitudes(_ lhs: String, _ rhs: String) -> String {
    let left = Array(lhs.utf8.reversed())
    let right = Array(rhs.utf8.reversed())
    var result: [UInt8] = []
    var borrow = 0
    for index in left.indices {
        var digit = Int(left[index] - 48) - borrow
        let subtrahend = index < right.count ? Int(right[index] - 48) : 0
        if digit < subtrahend {
            digit += 10
            borrow = 1
        } else {
            borrow = 0
        }
        result.append(UInt8(digit - subtrahend) + 48)
    }
    return runtimeNormalizeMagnitude(String(decoding: result.reversed(), as: UTF8.self))
}

private func runtimeMultiplyMagnitudes(_ lhs: String, _ rhs: String) -> String {
    if lhs == "0" || rhs == "0" { return "0" }
    let left = Array(lhs.utf8.reversed()).map { Int($0 - 48) }
    let right = Array(rhs.utf8.reversed()).map { Int($0 - 48) }
    var result = Array(repeating: 0, count: left.count + right.count)
    for leftIndex in left.indices {
        var carry = 0
        for rightIndex in right.indices {
            let position = leftIndex + rightIndex
            let product = result[position] + left[leftIndex] * right[rightIndex] + carry
            result[position] = product % 10
            carry = product / 10
        }
        var position = leftIndex + right.count
        while carry > 0 {
            let sum = result[position] + carry
            result[position] = sum % 10
            carry = sum / 10
            position += 1
            if position == result.count, carry > 0 { result.append(0) }
        }
    }
    while result.count > 1, result.last == 0 { result.removeLast() }
    return String(result.reversed().map { Character(String($0)) })
}

/// Returns quotient and remainder for nonnegative decimal magnitudes.
private func runtimeDivideMagnitudes(_ dividend: String, _ divisor: String) -> (String, String) {
    precondition(divisor != "0")
    var quotient = ""
    var remainder = "0"
    for digit in dividend {
        remainder = runtimeNormalizeMagnitude(remainder == "0" ? String(digit) : remainder + String(digit))
        var quotientDigit: UInt8 = 0
        while runtimeCompareMagnitudes(remainder, divisor) >= 0 {
            remainder = runtimeSubtractMagnitudes(remainder, divisor)
            quotientDigit += 1
        }
        quotient.append(Character(String(quotientDigit)))
    }
    return (runtimeNormalizeMagnitude(quotient), runtimeNormalizeMagnitude(remainder))
}

private func runtimeMultiplyMagnitudeBySmall(_ value: String, _ multiplier: Int) -> String {
    if value == "0" || multiplier == 0 { return "0" }
    var result: [UInt8] = []
    var carry = 0
    for byte in value.utf8.reversed() {
        let product = Int(byte - 48) * multiplier + carry
        result.append(UInt8(product % 10) + 48)
        carry = product / 10
    }
    while carry > 0 {
        result.append(UInt8(carry % 10) + 48)
        carry /= 10
    }
    return String(decoding: result.reversed(), as: UTF8.self)
}

private func runtimeGCD(_ lhs: String, _ rhs: String) -> String {
    var left = lhs
    var right = rhs
    while right != "0" {
        let remainder = runtimeDivideMagnitudes(left, right).1
        left = right
        right = remainder
    }
    return left
}

private func runtimePowerOfTen(_ exponent: Int) -> String {
    "1" + String(repeating: "0", count: exponent)
}

private func runtimeFormatBigDecimal(_ parts: RuntimeBigDecimalParts) throws -> String {
    let digits = runtimeNormalizeMagnitude(parts.digits)
    let precision = digits.count
    let (adjustedExponent, exponentOverflow) = precision.subtractingReportingOverflow(parts.scale + 1)
    guard !exponentOverflow else {
        throw RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range")
    }
    let sign = parts.negative && digits != "0" ? "-" : ""

    if parts.scale >= 0, adjustedExponent >= -6 {
        if parts.scale == 0 { return sign + digits }
        if precision > parts.scale {
            let split = digits.index(digits.endIndex, offsetBy: -parts.scale)
            return sign + String(digits[..<split]) + "." + String(digits[split...])
        }
        return sign + "0." + String(repeating: "0", count: parts.scale - precision) + digits
    }

    let mantissa = precision == 1 ? digits : String(digits.first!) + "." + digits.dropFirst()
    let exponentText = adjustedExponent >= 0 ? "+\(adjustedExponent)" : "\(adjustedExponent)"
    return sign + mantissa + "E" + exponentText
}

private func runtimeMakeBigDecimal(_ parts: RuntimeBigDecimalParts) throws -> Int {
    guard (Int(Int32.min) ... Int(Int32.max)).contains(parts.scale) else {
        throw RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range")
    }
    let value = try runtimeFormatBigDecimal(parts)
    return registerRuntimeObject(RuntimeBigNumberBox(value: value, kind: .decimal))
}

@_cdecl("__kk_double_toBigDecimal")
public func __kk_double_toBigDecimal(
    _ valueRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let bits = UInt64(bitPattern: Int64(valueRaw))
    let value = Double(bitPattern: bits)
    guard value.isFinite else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(message: "Infinite or NaN")
        return 0
    }

    let exponentBits = Int((bits >> 52) & 0x7FF)
    let fractionBits = bits & 0x000F_FFFF_FFFF_FFFF
    let significand = exponentBits == 0 ? fractionBits : fractionBits | (1 << 52)
    let negative = bits & (1 << 63) != 0
    var digits = String(significand)
    var scale = 0

    if significand != 0 {
        let binaryExponent = exponentBits == 0 ? -1074 : exponentBits - 1023 - 52
        if binaryExponent >= 0 {
            for _ in 0 ..< binaryExponent {
                digits = runtimeMultiplyMagnitudeBySmall(digits, 2)
            }
        } else {
            scale = -binaryExponent
            for _ in 0 ..< scale {
                digits = runtimeMultiplyMagnitudeBySmall(digits, 5)
            }
            while scale > 0, digits.last == "0" {
                digits.removeLast()
                scale -= 1
            }
        }
    }

    let parts = RuntimeBigDecimalParts(
        digits: digits,
        negative: negative,
        scale: scale
    )
    do {
        return try runtimeMakeBigDecimal(parts)
    } catch {
        return runtimeArithmeticException(error, outThrown: outThrown)
    }
}

private func runtimeArithmeticException(_ error: Error, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let message: String
    if case let RuntimeBigDecimalError.arithmetic(reason) = error {
        message = reason
    } else {
        message = "BigDecimal arithmetic error"
    }
    outThrown?.pointee = runtimeAllocateArithmeticException(message: message)
    return 0
}

private func runtimeAddBigDecimals(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    subtract: Bool = false
) throws -> Int {
    var lhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(lhsRaw, caller: #function))
    var rhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(rhsRaw, caller: #function))
    if subtract, rhs.digits != "0" { rhs.negative.toggle() }
    let resultScale = max(lhs.scale, rhs.scale)
    lhs.digits += String(repeating: "0", count: resultScale - lhs.scale)
    rhs.digits += String(repeating: "0", count: resultScale - rhs.scale)

    let resultDigits: String
    let resultNegative: Bool
    if lhs.negative == rhs.negative {
        resultDigits = runtimeAddMagnitudes(lhs.digits, rhs.digits)
        resultNegative = lhs.negative
    } else {
        let order = runtimeCompareMagnitudes(lhs.digits, rhs.digits)
        if order == 0 {
            resultDigits = "0"
            resultNegative = false
        } else if order > 0 {
            resultDigits = runtimeSubtractMagnitudes(lhs.digits, rhs.digits)
            resultNegative = lhs.negative
        } else {
            resultDigits = runtimeSubtractMagnitudes(rhs.digits, lhs.digits)
            resultNegative = rhs.negative
        }
    }
    return try runtimeMakeBigDecimal(
        RuntimeBigDecimalParts(digits: resultDigits, negative: resultNegative, scale: resultScale)
    )
}

@_cdecl("__kk_bignum_add")
public func __kk_bignum_add(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    do { return try runtimeAddBigDecimals(lhsRaw, rhsRaw) }
    catch { return runtimeArithmeticException(error, outThrown: outThrown) }
}

@_cdecl("__kk_bignum_subtract")
public func __kk_bignum_subtract(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    do { return try runtimeAddBigDecimals(lhsRaw, rhsRaw, subtract: true) }
    catch { return runtimeArithmeticException(error, outThrown: outThrown) }
}

@_cdecl("__kk_bignum_multiply")
public func __kk_bignum_multiply(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    do {
        let lhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(lhsRaw, caller: #function))
        let rhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(rhsRaw, caller: #function))
        let (scale, overflow) = lhs.scale.addingReportingOverflow(rhs.scale)
        guard !overflow else { throw RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range") }
        return try runtimeMakeBigDecimal(RuntimeBigDecimalParts(
            digits: runtimeMultiplyMagnitudes(lhs.digits, rhs.digits),
            negative: lhs.negative != rhs.negative,
            scale: scale
        ))
    } catch {
        return runtimeArithmeticException(error, outThrown: outThrown)
    }
}

private func runtimeExactDivide(
    _ lhs: RuntimeBigDecimalParts,
    _ rhs: RuntimeBigDecimalParts
) throws -> RuntimeBigDecimalParts {
    guard rhs.digits != "0" else {
        throw RuntimeBigDecimalError.arithmetic("Division by zero")
    }
    let (preferredScale, scaleOverflow) = lhs.scale.subtractingReportingOverflow(rhs.scale)
    guard !scaleOverflow else { throw RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range") }
    if lhs.digits == "0" {
        return RuntimeBigDecimalParts(digits: "0", negative: false, scale: preferredScale)
    }

    var numerator = lhs.digits
    var denominator = rhs.digits
    let scaleDelta = rhs.scale - lhs.scale
    if scaleDelta >= 0 {
        numerator += String(repeating: "0", count: scaleDelta)
    } else {
        denominator += String(repeating: "0", count: -scaleDelta)
    }

    let gcd = runtimeGCD(numerator, denominator)
    numerator = runtimeDivideMagnitudes(numerator, gcd).0
    denominator = runtimeDivideMagnitudes(denominator, gcd).0

    var twos = 0
    var fives = 0
    while denominator != "1" {
        let byTwo = runtimeDivideMagnitudes(denominator, "2")
        if byTwo.1 == "0" {
            denominator = byTwo.0
            twos += 1
            continue
        }
        let byFive = runtimeDivideMagnitudes(denominator, "5")
        if byFive.1 == "0" {
            denominator = byFive.0
            fives += 1
            continue
        }
        throw RuntimeBigDecimalError.arithmetic(
            "Non-terminating decimal expansion; no exact representable decimal result"
        )
    }

    var scale = max(twos, fives)
    for _ in twos ..< scale { numerator = runtimeMultiplyMagnitudeBySmall(numerator, 2) }
    for _ in fives ..< scale { numerator = runtimeMultiplyMagnitudeBySmall(numerator, 5) }
    while numerator.count > 1, numerator.last == "0" {
        numerator.removeLast()
        scale -= 1
    }
    let resultScale = max(preferredScale, scale)
    if resultScale > scale {
        numerator += String(repeating: "0", count: resultScale - scale)
    }
    return RuntimeBigDecimalParts(
        digits: numerator,
        negative: lhs.negative != rhs.negative && numerator != "0",
        scale: resultScale
    )
}

@_cdecl("__kk_bignum_divide")
public func __kk_bignum_divide(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    do {
        let lhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(lhsRaw, caller: #function))
        let rhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(rhsRaw, caller: #function))
        return try runtimeMakeBigDecimal(runtimeExactDivide(lhs, rhs))
    } catch {
        return runtimeArithmeticException(error, outThrown: outThrown)
    }
}

private func runtimeRoundedQuotient(
    _ numerator: String,
    _ denominator: String,
    negative: Bool,
    roundingMode: Int
) throws -> String {
    let (quotient, remainder) = runtimeDivideMagnitudes(numerator, denominator)
    guard remainder != "0" else { return quotient }
    let shouldIncrement: Bool
    switch roundingMode {
    case 0: shouldIncrement = true
    case 1: shouldIncrement = false
    case 2: shouldIncrement = !negative
    case 3: shouldIncrement = negative
    case 4, 5, 6:
        let halfComparison = runtimeCompareMagnitudes(
            runtimeAddMagnitudes(remainder, remainder),
            denominator
        )
        if halfComparison > 0 {
            shouldIncrement = true
        } else if halfComparison < 0 {
            shouldIncrement = false
        } else if roundingMode == 4 {
            shouldIncrement = true
        } else if roundingMode == 5 {
            shouldIncrement = false
        } else {
            let lastDigit = quotient.utf8.last! - 48
            shouldIncrement = lastDigit % 2 != 0
        }
    case 7:
        throw RuntimeBigDecimalError.arithmetic("Rounding necessary")
    default:
        throw RuntimeBigDecimalError.arithmetic("Invalid rounding mode")
    }
    return shouldIncrement ? runtimeAddMagnitudes(quotient, "1") : quotient
}

private func runtimeScaledDivision(
    _ lhs: RuntimeBigDecimalParts,
    _ rhs: RuntimeBigDecimalParts,
    scale: Int,
    roundingMode: Int
) throws -> RuntimeBigDecimalParts {
    guard rhs.digits != "0" else {
        throw RuntimeBigDecimalError.arithmetic("Division by zero")
    }
    let (power, overflow) = scale.addingReportingOverflow(rhs.scale - lhs.scale)
    guard !overflow else { throw RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range") }
    var numerator = lhs.digits
    var denominator = rhs.digits
    if power >= 0 {
        numerator += String(repeating: "0", count: power)
    } else {
        denominator += String(repeating: "0", count: -power)
    }
    return RuntimeBigDecimalParts(
        digits: try runtimeRoundedQuotient(
            numerator,
            denominator,
            negative: lhs.negative != rhs.negative,
            roundingMode: roundingMode
        ),
        negative: lhs.negative != rhs.negative,
        scale: scale
    )
}

@_cdecl("__kk_bignum_divideAtScale")
public func __kk_bignum_divideAtScale(
    _ lhsRaw: Int,
    _ rhsRaw: Int,
    _ scale: Int,
    _ roundingMode: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard (Int(Int32.min) ... Int(Int32.max)).contains(scale) else {
        return runtimeArithmeticException(
            RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range"),
            outThrown: outThrown
        )
    }
    do {
        let lhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(lhsRaw, caller: #function))
        let rhs = try runtimeBigDecimalParts(runtimeBigDecimalValue(rhsRaw, caller: #function))
        return try runtimeMakeBigDecimal(runtimeScaledDivision(lhs, rhs, scale: scale, roundingMode: roundingMode))
    } catch {
        return runtimeArithmeticException(error, outThrown: outThrown)
    }
}

private func runtimeSetBigDecimalScale(
    _ value: RuntimeBigDecimalParts,
    scale: Int,
    roundingMode: Int
) throws -> RuntimeBigDecimalParts {
    if scale >= value.scale {
        return RuntimeBigDecimalParts(
            digits: value.digits + String(repeating: "0", count: scale - value.scale),
            negative: value.negative,
            scale: scale
        )
    }

    let removedDigits = value.scale - scale
    let split = max(0, value.digits.count - removedDigits)
    let kept = split == 0 ? "0" : String(value.digits.prefix(split))
    let firstDiscarded: UInt8 = removedDigits > value.digits.count
        ? 48
        : value.digits.utf8[value.digits.utf8.index(value.digits.utf8.startIndex, offsetBy: split)]
    let dropped = String(value.digits.dropFirst(split))
    let hasDiscardedNonzero = dropped.contains(where: { $0 != "0" })
    guard hasDiscardedNonzero else {
        return RuntimeBigDecimalParts(digits: kept, negative: value.negative, scale: scale)
    }

    let discardedIsHalfOrMore = firstDiscarded >= 53
    let exactlyHalf = firstDiscarded == 53 && !value.digits.utf8.suffix(from: value.digits.utf8.index(
        value.digits.utf8.startIndex,
        offsetBy: min(split + 1, value.digits.utf8.count)
    )).contains(where: { $0 != 48 })

    let shouldIncrement: Bool
    switch roundingMode {
    case 0: shouldIncrement = true
    case 1: shouldIncrement = false
    case 2: shouldIncrement = !value.negative
    case 3: shouldIncrement = value.negative
    case 4: shouldIncrement = discardedIsHalfOrMore
    case 5: shouldIncrement = discardedIsHalfOrMore && !exactlyHalf
    case 6: shouldIncrement = discardedIsHalfOrMore && (!exactlyHalf || (kept.utf8.last! - 48) % 2 != 0)
    case 7: throw RuntimeBigDecimalError.arithmetic("Rounding necessary")
    default: throw RuntimeBigDecimalError.arithmetic("Invalid rounding mode")
    }
    return RuntimeBigDecimalParts(
        digits: shouldIncrement ? runtimeAddMagnitudes(kept, "1") : kept,
        negative: value.negative,
        scale: scale
    )
}

@_cdecl("__kk_bignum_setScale")
public func __kk_bignum_setScale(
    _ valueRaw: Int,
    _ scale: Int,
    _ roundingMode: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard (Int(Int32.min) ... Int(Int32.max)).contains(scale) else {
        return runtimeArithmeticException(
            RuntimeBigDecimalError.arithmetic("BigDecimal scale out of range"),
            outThrown: outThrown
        )
    }
    do {
        let value = try runtimeBigDecimalParts(runtimeBigDecimalValue(valueRaw, caller: #function))
        return try runtimeMakeBigDecimal(runtimeSetBigDecimalScale(value, scale: scale, roundingMode: roundingMode))
    } catch {
        return runtimeArithmeticException(error, outThrown: outThrown)
    }
}

@_cdecl("__kk_bignum_scale")
public func __kk_bignum_scale(_ valueRaw: Int) -> Int {
    do { return try runtimeBigDecimalParts(runtimeBigDecimalValue(valueRaw, caller: #function)).scale }
    catch { fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(error)") }
}
