import RuntimeABI

@_cdecl("kk_compare_any")
public func kk_compare_any(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    // KUU-3621: prefer the operand's own registered Comparable.compareTo
    // (e.g. an interface-implementing value class boxed for polymorphic
    // dispatch) over the identity/scalar shortcuts, mirroring JVM virtual
    // dispatch; operands without a Comparable itable entry fall through.
    if let comparableResult = runtimeCompareComparableValues(lhs: lhsRaw, rhs: rhsRaw) {
        return comparableResult
    }
    if lhsRaw == rhsRaw {
        return 0
    }
    if lhsRaw == runtimeNullSentinelInt {
        return -1
    }
    if rhsRaw == runtimeNullSentinelInt {
        return 1
    }
    if let lhsString = runtimeStringFromRaw(lhsRaw),
       let rhsString = runtimeStringFromRaw(rhsRaw)
    {
        return runtimeCompareStrings(lhsString, rhsString)
    }

    if let scalarResult = runtimeCompareScalarValues(lhsRaw, rhsRaw) {
        return scalarResult
    }

    return lhsRaw < rhsRaw ? -1 : 1
}

func runtimeCompareStrings(_ lhs: String, _ rhs: String) -> Int {
    var lhsIterator = KotlinStringSurrogateEncoding.UTF16CodeUnits(lhs).makeIterator()
    var rhsIterator = KotlinStringSurrogateEncoding.UTF16CodeUnits(rhs).makeIterator()
    while true {
        switch (lhsIterator.next(), rhsIterator.next()) {
        case let (lhsUnit?, rhsUnit?):
            let difference = Int(lhsUnit) - Int(rhsUnit)
            if difference != 0 {
                return difference
            }
        case (nil, nil):
            return 0
        case (.some, nil):
            return 1 + countRemaining(lhsIterator)
        case (nil, .some):
            return -(1 + countRemaining(rhsIterator))
        }
    }
}

private func countRemaining(_ iterator: KotlinStringSurrogateEncoding.UTF16CodeUnits.Iterator) -> Int {
    var iterator = iterator
    var count = 0
    while iterator.next() != nil {
        count += 1
    }
    return count
}
