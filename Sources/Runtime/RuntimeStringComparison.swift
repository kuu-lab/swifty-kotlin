// Generic value comparison (kk_compare_any) and its helpers.
// Split out from `RuntimeStringStdlib.swift`.

@_cdecl("kk_compare_any")
public func kk_compare_any(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
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

    if let lhsValue = runtimeComparableScalar(from: lhsRaw),
       let rhsValue = runtimeComparableScalar(from: rhsRaw)
    {
        switch (lhsValue, rhsValue) {
        case let (.floating(lhs), .floating(rhs)):
            return runtimeCompareFloatingValues(lhs, rhs)
        case let (.floating(lhs), .integer(rhs)):
            return runtimeCompareFloatingValues(lhs, Double(rhs))
        case let (.floating(lhs), .unsignedInteger(rhs)):
            return runtimeCompareFloatingValues(lhs, Double(rhs))
        case let (.integer(lhs), .floating(rhs)):
            return runtimeCompareFloatingValues(Double(lhs), rhs)
        case let (.unsignedInteger(lhs), .floating(rhs)):
            return runtimeCompareFloatingValues(Double(lhs), rhs)
        case let (.integer(lhs), .integer(rhs)):
            if lhs == rhs {
                return 0
            }
            return lhs < rhs ? -1 : 1
        case let (.unsignedInteger(lhs), .unsignedInteger(rhs)):
            if lhs == rhs {
                return 0
            }
            return lhs < rhs ? -1 : 1
        // Mixed signed/unsigned only arises comparing statically-incompatible
        // Kotlin types (e.g. Long vs ULong); fall back to a Double approximation.
        case let (.integer(lhs), .unsignedInteger(rhs)):
            return runtimeCompareFloatingValues(Double(lhs), Double(rhs))
        case let (.unsignedInteger(lhs), .integer(rhs)):
            return runtimeCompareFloatingValues(Double(lhs), Double(rhs))
        }
    }

    if let comparableResult = runtimeCompareComparableValues(lhs: lhsRaw, rhs: rhsRaw) {
        return comparableResult
    }

    return lhsRaw < rhsRaw ? -1 : 1
}

private enum RuntimeComparableScalar {
    case integer(Int)
    case unsignedInteger(UInt)
    case floating(Double)
}

private func runtimeComparableScalar(from raw: Int) -> RuntimeComparableScalar? {
    guard raw != runtimeNullSentinelInt else {
        return nil
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
        return .integer(raw)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return .integer(raw)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return .floating(Double(floatBox.value))
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return .floating(doubleBox.value)
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return .integer(intBox.value)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return .integer(boolBox.value ? 1 : 0)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return .integer(longBox.value)
    }
    if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
        return .unsignedInteger(UInt(bitPattern: ulongBox.value))
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return .integer(charBox.value)
    }
    return nil
}

func runtimeCompareStrings(_ lhs: String, _ rhs: String) -> Int {
    var lhsIterator = lhs.utf16.makeIterator()
    var rhsIterator = rhs.utf16.makeIterator()
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

private func countRemaining(_ iterator: String.UTF16View.Iterator) -> Int {
    var iterator = iterator
    var count = 0
    while iterator.next() != nil {
        count += 1
    }
    return count
}
