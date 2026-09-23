
final class RuntimeRangeBox {
    let first: Int
    let last: Int
    let step: Int
    let kind: RuntimeRangeKind

    // Range handles share one representation, so preserve Char identity for
    // erased Iterable/Iterator calls that must return a boxed element.
    var yieldsChars: Bool {
        kind == .charRange || kind == .charProgression
    }

    init(first: Int, last: Int, step: Int, kind: RuntimeRangeKind = .intRange) {
        self.first = first
        self.last = last
        self.step = step
        self.kind = kind
    }
}

final class RuntimeRangeIteratorBox {
    var current: Int
    let last: Int
    var step: Int
    let kind: RuntimeRangeKind
    var hasNextValue: Bool

    // Range handles share one representation, so preserve Char identity for
    // erased Iterable/Iterator calls that must return a boxed element.
    var yieldsChars: Bool {
        kind == .charRange || kind == .charProgression
    }

    init(current: Int, last: Int, step: Int, kind: RuntimeRangeKind = .intRange) {
        self.current = current
        self.last = last
        self.step = step
        self.kind = kind
        hasNextValue = RuntimeRangeIteratorBox.computeHasNext(
            current: current, last: last, step: step, kind: kind
        )
    }

    static func computeHasNext(current: Int, last: Int, step: Int, kind: RuntimeRangeKind) -> Bool {
        switch kind {
        case .uintRange, .uintProgression, .ulongRange, .ulongProgression:
            let uCurrent = UInt(bitPattern: current)
            let uLast = UInt(bitPattern: last)
            if step > 0 { return uCurrent <= uLast }
            if step < 0 { return uCurrent >= uLast }
            return false
        default:
            if step > 0 { return current <= last }
            if step < 0 { return current >= last }
            return false
        }
    }

    /// Advances one step, updating `hasNextValue`, and returns the element at
    /// the position held on entry. Checked arithmetic stops at the type
    /// boundary (Long.MIN_VALUE / ULong.max): wrapping `current &+ step` would
    /// land back inside the range and iterate forever.
    func advance() -> Int {
        let current = self.current
        guard hasNextValue else { return current }
        let candidate: Int
        switch kind {
        case .uintRange, .uintProgression, .ulongRange, .ulongProgression:
            if step > 0 {
                let (next, overflow) = UInt(bitPattern: current)
                    .addingReportingOverflow(UInt(bitPattern: step))
                if overflow { hasNextValue = false; step = 0; return current }
                candidate = Int(bitPattern: next)
            } else {
                let (next, overflow) = UInt(bitPattern: current)
                    .subtractingReportingOverflow(UInt(step.magnitude))
                if overflow { hasNextValue = false; step = 0; return current }
                candidate = Int(bitPattern: next)
            }
        default:
            let (next, overflow) = current.addingReportingOverflow(step)
            if overflow { hasNextValue = false; step = 0; return current }
            candidate = next
        }
        hasNextValue = RuntimeRangeIteratorBox.computeHasNext(
            current: candidate, last: last, step: step, kind: kind
        )
        self.current = candidate
        return current
    }
}

/// BUG-198: Iterator state for compiler-lowered signed range `for-in` loops.
/// This intentionally has no Iterator itable: the lowering calls the three
/// dedicated entry points directly, while explicit `range.iterator()` keeps the
/// KSP-452 source-backed iterator implementation.
final class RuntimeSignedRangeForInIteratorBox {
    var current: Int
    let last: Int
    let step: Int
    var hasNextValue: Bool

    init(current: Int, last: Int, step: Int) {
        self.current = current
        self.last = last
        self.step = step
        if step > 0 {
            self.hasNextValue = current <= last
        } else if step < 0 {
            self.hasNextValue = current >= last
        } else {
            self.hasNextValue = false
        }
    }
}

func runtimeUnsignedRangeIsEmpty(_ range: RuntimeRangeBox) -> Bool {
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        return first > last
    } else if range.step < 0 {
        return first < last
    }
    return true
}

func runtimeUnsignedRangeTraverse(
    _ range: RuntimeRangeBox,
    _ body: (_ current: UInt, _ index: Int) -> Bool
) -> Bool {
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    var index = 0
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        var current = first
        while current <= last {
            if !body(current, index) {
                return false
            }
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
            index &+= 1
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        var current = first
        while current >= last {
            if !body(current, index) {
                return false
            }
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
            index &+= 1
        }
    }
    return true
}

func runtimeUnsignedRangeTraverseReversed(
    _ range: RuntimeRangeBox,
    _ body: (_ current: UInt) -> Bool
) -> Bool {
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let uStep = UInt(bitPattern: range.step)
        var current = last
        while current >= first {
            if !body(current) {
                return false
            }
            let (next, overflow) = current.subtractingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let uStep = UInt(range.step.magnitude)
        var current = last
        while current <= first {
            if !body(current) {
                return false
            }
            let (next, overflow) = current.addingReportingOverflow(uStep)
            if overflow { break }
            current = next
        }
    }
    return true
}

func runtimeUnsignedRangeFirstMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = runtimeNullSentinelInt
    var didThrow = false
    _ = runtimeUnsignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            didThrow = true
            return false
        }
        if result != 0 {
            found = true
            match = Int(bitPattern: current)
            return false
        }
        return true
    }
    if found {
        return orNull ? runtimeRangeErasedElement(match, kind: range.kind) : match
    }
    if didThrow {
        return orNull ? runtimeNullSentinelInt : 0
    }
    if orNull {
        return runtimeNullSentinelInt
    }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
    return 0
}

func runtimeUnsignedRangeLastMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = runtimeNullSentinelInt
    var didThrow = false
    _ = runtimeUnsignedRangeTraverseReversed(range) { current in
        var thrown = 0
        let result = lambda(closureRaw, Int(bitPattern: current), &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            didThrow = true
            return false
        }
        if result != 0 {
            found = true
            match = Int(bitPattern: current)
            return false
        }
        return true
    }
    if found {
        return orNull ? runtimeRangeErasedElement(match, kind: range.kind) : match
    }
    if didThrow {
        return orNull ? runtimeNullSentinelInt : 0
    }
    if orNull {
        return runtimeNullSentinelInt
    }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
    return 0
}

// MARK: - Signed range traverse helpers (parallel to unsigned variants above)

func runtimeSignedRangeIsEmpty(_ range: RuntimeRangeBox) -> Bool {
    if range.step > 0 { return range.first > range.last }
    if range.step < 0 { return range.first < range.last }
    return true
}

/// Signed membership test for `element in range`: 1 when the element is a
/// member of the stepped range, 0 otherwise. Shared by `kk_op_contains` and
/// `kk_collection_containsAll`.
func runtimeRangeContains(_ range: RuntimeRangeBox, _ element: Int) -> Int {
    if range.step > 0 {
        guard element >= range.first, element <= range.last else { return 0 }
        // The signed distance can exceed Int64 range on full-span ranges
        // (e.g. element=Int.max, first=Int.min); the wrapping subtraction's
        // bit pattern is the true unsigned distance.
        let distance = UInt(bitPattern: element &- range.first)
        return distance % UInt(range.step) == 0 ? 1 : 0
    } else if range.step < 0 {
        guard element <= range.first, element >= range.last else { return 0 }
        let distance = UInt(bitPattern: range.first &- element)
        return distance % UInt(bitPattern: 0 &- range.step) == 0 ? 1 : 0
    }
    return 0
}

func runtimeSignedRangeTraverse(
    _ range: RuntimeRangeBox,
    _ body: (_ current: Int, _ index: Int) -> Bool
) -> Bool {
    var current = range.first
    var index = 0
    // Checked arithmetic matches the unsigned traverse: stepping past a type
    // boundary (e.g. Long.MIN_VALUE) must stop the loop instead of wrapping.
    if range.step > 0 {
        while current <= range.last {
            if !body(current, index) { return false }
            // The stored last is already snapped to the progression's final
            // reachable element, so reaching it ends the walk without letting
            // the advance wrap around an Int/Long boundary (KUU-819).
            if current == range.last { break }
            let (next, overflow) = current.addingReportingOverflow(range.step)
            if overflow { break }
            current = next
            index &+= 1
        }
    } else if range.step < 0 {
        while current >= range.last {
            if !body(current, index) { return false }
            if current == range.last { break }
            let (next, overflow) = current.addingReportingOverflow(range.step)
            if overflow { break }
            current = next
            index &+= 1
        }
    }
    return true
}

func runtimeSignedRangeTraverseReversed(
    _ range: RuntimeRangeBox,
    _ body: (_ current: Int) -> Bool
) -> Bool {
    var current = range.last
    if range.step > 0 {
        while current >= range.first {
            if !body(current) { return false }
            if current == range.first { break }
            let (next, overflow) = current.subtractingReportingOverflow(range.step)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        while current <= range.first {
            if !body(current) { return false }
            if current == range.first { break }
            let (next, overflow) = current.subtractingReportingOverflow(range.step)
            if overflow { break }
            current = next
        }
    }
    return true
}

func runtimeSignedRangeFirstMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = 0
    var didThrow = false
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if result != 0 { found = true; match = current; return false }
        return true
    }
    if found { return orNull ? runtimeRangeErasedElement(match, kind: range.kind) : match }
    if didThrow { return orNull ? runtimeNullSentinelInt : 0 }
    if orNull { return runtimeNullSentinelInt }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
    return 0
}

func runtimeSignedRangeLastMatch(
    _ range: RuntimeRangeBox,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    orNull: Bool
) -> Int {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var found = false
    var match = 0
    var didThrow = false
    _ = runtimeSignedRangeTraverseReversed(range) { current in
        var thrown = 0
        let result = lambda(closureRaw, current, &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; didThrow = true; return false }
        if result != 0 { found = true; match = current; return false }
        return true
    }
    if found { return orNull ? runtimeRangeErasedElement(match, kind: range.kind) : match }
    if didThrow { return orNull ? runtimeNullSentinelInt : 0 }
    if orNull { return runtimeNullSentinelInt }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "No element matching the predicate was found.")
    return 0
}

// MARK: - Range randomOrNull helpers

func runtimeRandomIndex(count: Int, randomRaw: Int?) -> Int {
    if let randomRaw {
        return runtimeRandomNextIntBelow(randomRaw, count)
    }
    return Int.random(in: 0 ..< count)
}

func runtimeSignedRangeCount(_ range: RuntimeRangeBox) -> Int {
    if range.step > 0 {
        guard range.first <= range.last else { return 0 }
        return (range.last &- range.first) / range.step &+ 1
    } else if range.step < 0 {
        guard range.first >= range.last else { return 0 }
        return (range.first &- range.last) / (0 &- range.step) &+ 1
    }
    return 0
}

func runtimeCharRangeCount(_ range: RuntimeRangeBox) -> Int {
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    if range.step > 0 {
        guard first <= last else { return 0 }
        return (last &- first) / range.step &+ 1
    } else if range.step < 0 {
        guard first >= last else { return 0 }
        return (first &- last) / (0 &- range.step) &+ 1
    }
    return 0
}

func runtimeSignedRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    guard range.step != 0 else { return runtimeNullSentinelInt }
    let ascending = range.step > 0
    guard ascending ? range.first <= range.last : range.first >= range.last else {
        return runtimeNullSentinelInt
    }
    let absStep = UInt64(range.step.magnitude)
    let signMask = UInt64(1) << 63
    let firstOrdered = UInt64(bitPattern: Int64(range.first)) ^ signMask
    let lastOrdered = UInt64(bitPattern: Int64(range.last)) ^ signMask
    let distance = ascending ? lastOrdered &- firstOrdered : firstOrdered &- lastOrdered
    if absStep == 1 && distance == UInt64.max {
        let bits: UInt64
        if let randomRaw {
            bits = runtimeRandomBits(from: randomRaw)
        } else {
            var rng = SystemRandomNumberGenerator()
            bits = rng.next()
        }
        return runtimeRangeErasedElement(Int(bitPattern: UInt(truncatingIfNeeded: bits)), kind: range.kind)
    }
    let count = distance / absStep + 1
    let index: UInt64
    if let randomRaw {
        index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    } else if count == UInt64.max {
        var rng = SystemRandomNumberGenerator()
        index = rng.next() % count
    } else {
        index = UInt64.random(in: 0 ..< count)
    }
    let offset = index &* absStep
    let chosenOrdered = ascending ? firstOrdered &+ offset : firstOrdered &- offset
    return runtimeRangeErasedElement(Int(bitPattern: UInt(truncatingIfNeeded: chosenOrdered ^ signMask)), kind: range.kind)
}

func runtimeUnsignedRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    guard range.step != 0 else { return runtimeNullSentinelInt }
    let first = UInt64(UInt(bitPattern: range.first))
    let last = UInt64(UInt(bitPattern: range.last))
    let ascending = range.step > 0
    guard ascending ? first <= last : first >= last else {
        return runtimeNullSentinelInt
    }
    let absStep = UInt64(range.step.magnitude)
    let distance = ascending ? last &- first : first &- last
    if absStep == 1 && distance == UInt64.max {
        let bits: UInt64
        if let randomRaw {
            bits = runtimeRandomBits(from: randomRaw)
        } else {
            var rng = SystemRandomNumberGenerator()
            bits = rng.next()
        }
        return runtimeRangeErasedElement(Int(bitPattern: UInt(truncatingIfNeeded: bits)), kind: range.kind)
    }
    let count = distance / absStep + 1
    let index: UInt64
    if let randomRaw {
        index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    } else if count == UInt64.max {
        var rng = SystemRandomNumberGenerator()
        index = rng.next() % count
    } else {
        index = UInt64.random(in: 0 ..< count)
    }
    let offset = index &* absStep
    let chosen = ascending ? first &+ offset : first &- offset
    return runtimeRangeErasedElement(Int(bitPattern: UInt(truncatingIfNeeded: chosen)), kind: range.kind)
}

func runtimeCharRangeRandomOrNull(_ range: RuntimeRangeBox, randomRaw: Int?) -> Int {
    let count = runtimeCharRangeCount(range)
    guard count > 0 else { return runtimeNullSentinelInt }
    let index = runtimeRandomIndex(count: count, randomRaw: randomRaw)
    let first = kk_unbox_char(range.first)
    let value = first &+ (range.step &* index)
    return kk_box_char(value)
}

func runtimeCharRangeRandom(
    _ range: RuntimeRangeBox,
    randomRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let count = runtimeCharRangeCount(range)
    guard count > 0 else { return runtimeRangeRandomError(outThrown) }
    let index = runtimeRandomIndex(upperBound: UInt64(count), randomRaw: randomRaw)
    let first = kk_unbox_char(range.first)
    let value = first &+ (range.step &* Int(truncatingIfNeeded: index))
    return kk_box_char(value)
}

// MARK: - Range.random(Random) helpers (rejection sampling; STDLIB-RANGE-RANDOM-002)

func runtimeRandomBits(from randomRaw: Int) -> UInt64 {
    runtimeRandomNextBits64(randomRaw)
}

func runtimeRandomIndex(upperBound: UInt64, randomRaw: Int) -> UInt64 {
    precondition(upperBound > 0)
    if upperBound == 1 {
        return 0
    }
    // Rejection sampling keeps the index uniform without modulo bias.
    let rejectionLimit = UInt64.max - (UInt64.max % upperBound)
    var candidate = runtimeRandomBits(from: randomRaw)
    while candidate >= rejectionLimit {
        candidate = runtimeRandomBits(from: randomRaw)
    }
    return candidate % upperBound
}

func runtimeRangeRandomError(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "Range is empty.")
    return 0
}

func runtimeSignedRangeRandom(
    first: Int,
    last: Int,
    step: Int,
    randomRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard step != 0 else {
        return runtimeRangeRandomError(outThrown)
    }
    let ascending = step > 0
    guard ascending ? first <= last : first >= last else {
        return runtimeRangeRandomError(outThrown)
    }
    let absStep = UInt64(step.magnitude)
    let signMask = UInt64(1) << 63
    let firstOrdered = UInt64(bitPattern: Int64(first)) ^ signMask
    let lastOrdered = UInt64(bitPattern: Int64(last)) ^ signMask
    if absStep == 1 {
        // A full-width range can use the raw 64-bit random value directly.
        if ascending && firstOrdered == 0 && lastOrdered == UInt64.max {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
        if !ascending && firstOrdered == UInt64.max && lastOrdered == 0 {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
    }
    let distance = ascending ? lastOrdered &- firstOrdered : firstOrdered &- lastOrdered
    let count = distance / absStep + 1
    let index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    let offset = index &* absStep
    let chosenOrdered = ascending ? firstOrdered &+ offset : firstOrdered &- offset
    return Int(bitPattern: UInt(truncatingIfNeeded: chosenOrdered ^ signMask))
}

func runtimeUnsignedRangeRandom(
    first: UInt,
    last: UInt,
    step: Int,
    randomRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard step != 0 else {
        return runtimeRangeRandomError(outThrown)
    }
    let ascending = step > 0
    guard ascending ? first <= last : first >= last else {
        return runtimeRangeRandomError(outThrown)
    }
    let absStep = UInt64(step.magnitude)
    let first64 = UInt64(first)
    let last64 = UInt64(last)
    if absStep == 1 {
        // A full-width unsigned range can use the raw 64-bit random value directly.
        if ascending && first64 == 0 && last64 == UInt64.max {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
        if !ascending && first64 == UInt64.max && last64 == 0 {
            return Int(bitPattern: UInt(truncatingIfNeeded: runtimeRandomBits(from: randomRaw)))
        }
    }
    let distance = ascending ? last64 &- first64 : first64 &- last64
    let count = distance / absStep + 1
    let index = runtimeRandomIndex(upperBound: count, randomRaw: randomRaw)
    let offset = index &* absStep
    let chosen = ascending ? first64 &+ offset : first64 &- offset
    return Int(bitPattern: UInt(truncatingIfNeeded: chosen))
}

@_cdecl("kk_op_notnull")
public func kk_op_notnull(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if value == runtimeNullSentinelInt {
        outThrown?.pointee = runtimeAllocateNullPointerException(message: nil)
        return 0
    }
    return value
}

@_cdecl("kk_op_elvis")
public func kk_op_elvis(_ lhs: Int, _ rhs: Int) -> Int {
    lhs == runtimeNullSentinelInt ? rhs : lhs
}

@_cdecl("kk_op_rangeTo")
public func kk_op_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1, kind: .intRange))
}

@_cdecl("__kk_op_rangeUntil")
public func __kk_op_rangeUntil(_ lhs: Int, _ rhs: Int) -> Int {
    if rhs <= lhs {
        return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 0, kind: .intRange))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 1, kind: .intRange))
}

@_cdecl("__kk_op_ulong_rangeUntil")
public func __kk_op_ulong_rangeUntil(_ lhs: Int, _ rhs: Int) -> Int {
    let lhsUnsigned = UInt(bitPattern: lhs)
    let rhsUnsigned = UInt(bitPattern: rhs)
    if rhsUnsigned <= lhsUnsigned {
        return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 0, kind: .ulongRange))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs &- 1, step: 1, kind: .ulongRange))
}

@_cdecl("__kk_op_downTo")
public func __kk_op_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1, kind: .intProgression))
}

@_cdecl("__kk_op_step")
public func __kk_op_step(_ rangeRaw: Int, _ stepValue: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    // Kotlin spec: step() requires a strictly positive argument (STDLIB-022).
    guard stepValue > 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard stepValue != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }

    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return rangeRaw
    }
    if range.step == 0 {
        return registerRuntimeObject(RuntimeRangeBox(
            first: range.first,
            last: range.last,
            step: range.step,
            kind: range.kind.progressionKind
        ))
    }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    // Align 'last' to the step like Kotlin's getProgressionLastElement:
    // last is the final value in the progression that stays within the range.
    // Guard empty ranges first — Kotlin returns 'last' unchanged for empty
    // progressions (positive step: first > last; negative step: first < last).
    // Use wrapping arithmetic (&-/&+) to avoid trapping on extreme Int ranges.
    let alignedLast: Int
    if nextStep > 0 {
        guard range.first <= range.last else {
            return registerRuntimeObject(RuntimeRangeBox(
                first: range.first,
                last: range.last,
                step: nextStep,
                kind: range.kind.progressionKind
            ))
        }
        // Unsigned distance stays exact even when the span exceeds Int64
        // range (e.g. Int.min..Int.max): a plain subtraction would wrap and
        // misalign `last` away from the boundary.
        let distance = UInt(bitPattern: range.last &- range.first)
        let remainder = Int(bitPattern: distance % UInt(nextStep))
        alignedLast = range.last &- remainder
    } else {
        guard range.first >= range.last else {
            return registerRuntimeObject(RuntimeRangeBox(
                first: range.first,
                last: range.last,
                step: nextStep,
                kind: range.kind.progressionKind
            ))
        }
        let distance = UInt(bitPattern: range.first &- range.last)
        let remainder = Int(bitPattern: distance % UInt(bitPattern: 0 &- nextStep))
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(
        first: range.first,
        last: alignedLast,
        step: nextStep,
        kind: range.kind.progressionKind
    ))
}

private let runtimeIterableInterfaceTypeID: Int64 = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Iterable"
)
private let runtimeIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.Iterator"
)

/// BUG-167: Calls `iterator()` on a source-implemented `Iterable` object through
/// the `kotlin.collections.Iterable` itable (method slot 0). Returns nil when
/// the value does not implement `Iterable` in source, so callers can fall back
/// to the runtime box representations.
func runtimeSourceIterableIterator(
    _ iterableRaw: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int? {
    outThrown?.pointee = 0
    let fnPtr = kk_itable_lookup_dynamic(iterableRaw, Int(runtimeIterableInterfaceTypeID), 0)
    guard fnPtr != 0 else {
        return nil
    }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let iterRaw = fn(iterableRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "Iterable.iterator() dispatch"
        )
        return nil
    }
    return iterRaw
}

/// KSP-998: Explicit `Iterable.iterator()` calls use a throwing bridge so a
/// source iterator is acquired lazily and its exception reaches Kotlin catch.
@_cdecl("kk_iterable_iterator")
public func kk_iterable_iterator(_ iterableRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if runtimeIteratorBuilderBox(from: iterableRaw) != nil {
        return iterableRaw
    }
    if runtimeSequenceBox(from: iterableRaw) != nil {
        let elements = runtimeSequenceSourceElementsOrPanic(from: iterableRaw, caller: #function)
        return registerRuntimeObject(RuntimeListIteratorBox(elements: elements))
    }
    if runtimeListBox(from: iterableRaw) != nil || runtimeSetBox(from: iterableRaw) != nil {
        return kk_list_iterator(iterableRaw)
    }
    if let arrayBox = runtimeArrayBox(from: iterableRaw), type(of: arrayBox) == RuntimeArrayBox.self {
        return kk_list_iterator(iterableRaw)
    }
    // Preserve the legacy compiler bridge for the old runtime-backed
    // IndexingIterable representation while source-backed withIndex() uses the
    // Kotlin IndexingIterable class above.
    if runtimeIndexingIterableBox(from: iterableRaw) != nil {
        return kk_indexing_iterable_iterator(iterableRaw)
    }
    if let sourceIterator = runtimeSourceIterableIterator(iterableRaw, outThrown: outThrown) {
        return sourceIterator
    }
    guard let range = runtimeRangeBox(from: iterableRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(
            current: range.first,
            last: range.last,
            step: range.step,
            kind: range.kind
        )
    )
}

@_cdecl("kk_range_iterator")
public func kk_range_iterator(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    if runtimeIteratorBuilderBox(from: rangeRaw) != nil {
        return rangeRaw
    }
    if runtimeSequenceBox(from: rangeRaw) != nil {
        let elements = runtimeSequenceSourceElementsOrPanic(from: rangeRaw, caller: #function)
        return registerRuntimeObject(RuntimeListIteratorBox(elements: elements))
    }
    if runtimeListBox(from: rangeRaw) != nil {
        return kk_list_iterator(rangeRaw)
    }
    if runtimeSetBox(from: rangeRaw) != nil {
        return kk_list_iterator(rangeRaw)
    }
    // `for (x in arrayOf(...))` (and other raw arrays: IntArray, ByteArray, ...)
    // reaches this generic for-loop entry point same as List, when the iterable
    // has no compile-time-resolved iterator (e.g. a generic Iterable<T>
    // parameter); without this branch an array falls through to the range-box
    // guard below, gets treated as an invalid range, and the loop silently
    // iterates zero times (kk_range_hasNext sees no RuntimeRangeIteratorBox).
    // The exact-type check excludes RuntimeObjectBox, a RuntimeArrayBox subclass
    // used for ordinary class instances.
    if let arrayBox = runtimeArrayBox(from: rangeRaw), type(of: arrayBox) == RuntimeArrayBox.self {
        return kk_list_iterator(rangeRaw)
    }
    // BUG-167: A source-implemented `Iterable` (e.g. `class C : Iterable<Int>`)
    // reaches this entry point too, since its `iterator()` is only known
    // dynamically. Dispatch it through the `kotlin.collections.Iterable` itable
    // — the same shape `runtimeTraverseSourceSequenceObject` uses for
    // `Sequence` — instead of treating the object as an invalid range.
    if let sourceIterator = runtimeSourceIterableIterator(rangeRaw, outThrown: outThrown) {
        return sourceIterator
    }
    if let outThrown, outThrown.pointee != 0 {
        return 0
    }
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(
            current: range.first,
            last: range.last,
            step: range.step,
            kind: range.kind
        )
    )
}

@_cdecl("kk_range_hasNext")
public func kk_range_hasNext(_ iterRaw: Int) -> Int {
    let object = resolveRuntimeObjectHandle(iterRaw)
    if object is RuntimeIteratorBuilderBox {
        return __kk_iterator_builder_hasNext(iterRaw)
    }
    if object is RuntimeListIteratorBox {
        return kk_list_iterator_hasNext(iterRaw)
    }
    if let result = runtimeBufferedLineIteratorHasNext(iterRaw) {
        return result
    }
    guard let iterator = object as? RuntimeRangeIteratorBox else {
        return 0
    }
    return iterator.hasNextValue ? 1 : 0
}

@_cdecl("kk_range_next")
public func kk_range_next(_ iterRaw: Int) -> Int {
    let object = resolveRuntimeObjectHandle(iterRaw)
    if object is RuntimeIteratorBuilderBox {
        return __kk_iterator_builder_next(iterRaw)
    }
    if object is RuntimeListIteratorBox {
        return kk_list_iterator_next(iterRaw)
    }
    if let result = runtimeBufferedLineIteratorNext(iterRaw, outThrown: nil) {
        return result
    }
    guard let iterator = object as? RuntimeRangeIteratorBox else {
        return 0
    }
    return iterator.advance()
}

/// BUG-198: Fast path used only after lowering proves a signed built-in range.
@_cdecl("kk_range_for_in_iterator")
public func kk_range_for_in_iterator(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return 0
    }
    return registerRuntimeObject(
        RuntimeSignedRangeForInIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("kk_range_for_in_hasNext")
public func kk_range_for_in_hasNext(_ iterRaw: Int) -> Int {
    guard let iterator = runtimeSignedRangeForInIteratorBox(from: iterRaw) else {
        return 0
    }
    return iterator.hasNextValue ? 1 : 0
}

@_cdecl("kk_range_for_in_next")
public func kk_range_for_in_next(_ iterRaw: Int) -> Int {
    guard let iterator = runtimeSignedRangeForInIteratorBox(from: iterRaw) else {
        return 0
    }
    let current = iterator.current
    guard iterator.hasNextValue else {
        return current
    }

    let (candidate, overflow) = current.addingReportingOverflow(iterator.step)
    if overflow {
        iterator.hasNextValue = false
        return current
    }
    if iterator.step > 0 {
        iterator.hasNextValue = candidate > current && candidate <= iterator.last
    } else if iterator.step < 0 {
        iterator.hasNextValue = candidate < current && candidate >= iterator.last
    } else {
        iterator.hasNextValue = false
    }
    iterator.current = candidate
    return current
}

@_cdecl("kk_iterator_hasNext")
public func kk_iterator_hasNext(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    let object = resolveRuntimeObjectHandle(iterRaw)
    if object is RuntimeIteratorBuilderBox {
        return __kk_iterator_builder_hasNext(iterRaw)
    }
    if let rangeIterator = object as? RuntimeRangeIteratorBox {
        return runtimeRangeIteratorHasNext(rangeIterator)
    }
    if object is RuntimeListIteratorBox {
        return kk_list_iterator_hasNext(iterRaw)
    }
    if object is RuntimeMapIteratorBox {
        return kk_map_iterator_hasNext(iterRaw)
    }
    if object is RuntimeIndexingIteratorBox {
        return kk_indexing_iterable_hasNext(iterRaw)
    }
    if let result = runtimeBufferedLineIteratorHasNext(iterRaw) {
        return result
    }
    if let objectResult = runtimeObjectIteratorMethodCall(iterRaw, methodSlot: 0, outThrown: outThrown) {
        return objectResult
    }
    return 0
}

/// Converts a raw range element into the representation an erased `T`/`T?`/
/// `List<T>` slot requires: element kinds whose scalar collides with the null
/// sentinel (Long.MIN_VALUE, ULong 2^63) or loses type identity (Char) must
/// become real boxes so generic consumers recover the primitive.
func runtimeRangeErasedElement(_ value: Int, kind: RuntimeRangeKind) -> Int {
    switch kind {
    case .charRange, .charProgression:
        return kk_box_char(value)
    case .longRange, .longProgression:
        return kk_box_long_nonnull(value)
    case .ulongRange, .ulongProgression:
        return kk_box_ulong_nonnull(value)
    default:
        return value
    }
}

@_cdecl("kk_iterator_next")
public func kk_iterator_next(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    let object = resolveRuntimeObjectHandle(iterRaw)
    if object is RuntimeIteratorBuilderBox {
        if __kk_iterator_builder_hasNext(iterRaw) == 0 {
            return runtimeThrowIteratorExhausted(outThrown)
        }
        return __kk_iterator_builder_next(iterRaw)
    }
    if let rangeIterator = object as? RuntimeRangeIteratorBox {
        if runtimeRangeIteratorHasNext(rangeIterator) == 0 {
            return runtimeThrowIteratorExhausted(outThrown)
        }
        let value = rangeIterator.advance()
        // `Iterator<T>.next()` is an erased boundary.
        return runtimeRangeErasedElement(value, kind: rangeIterator.kind)
    }
    if object is RuntimeListIteratorBox {
        return kk_list_iterator_next(iterRaw, outThrown)
    }
    if object is RuntimeMapIteratorBox {
        return kk_map_iterator_next(iterRaw, outThrown)
    }
    if object is RuntimeMutableMapIteratorBox {
        return kk_mutable_map_iterator_next(iterRaw, outThrown)
    }
    if object is RuntimeIndexingIteratorBox {
        return kk_indexing_iterable_next(iterRaw, outThrown)
    }
    if let result = runtimeBufferedLineIteratorNext(iterRaw, outThrown: outThrown) {
        return result
    }
    if let objectResult = runtimeObjectIteratorMethodCall(iterRaw, methodSlot: 1, outThrown: outThrown) {
        if let outThrown, outThrown.pointee != 0 {
            return objectResult
        }
        // Iterator<T>.next() crosses an erased generic boundary. Source-backed
        // CharIterator implementations return the raw Char scalar from their
        // concrete method, so box it before generic consumers store the value.
        if runtimeSourceIteratorValue(objectResult, iteratorRaw: iterRaw).tag == RuntimeValue.charTag {
            return kk_box_char(objectResult)
        }
        return objectResult
    }
    return runtimeThrowIteratorExhausted(outThrown)
}

private func runtimeObjectIteratorMethodCall(
    _ iterRaw: Int,
    methodSlot: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    // KUU-477: an Iterator object may implement another interface before
    // Iterator, so its physical itable slot is not necessarily zero. Resolve
    // the slot from the interface registration attached to this object.
    let functionRaw = kk_itable_lookup_dynamic(iterRaw, Int(runtimeIteratorInterfaceTypeID), methodSlot)
    guard functionRaw != 0 else {
        return nil
    }

    let method = unsafeBitCast(
        functionRaw,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = method(iterRaw, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown,
            outThrown: outThrown,
            context: "Iterator object dispatch"
        )
        return 0
    }
    return result
}

// MARK: - IntRange properties (STDLIB-092)

@_cdecl("__kk_range_first")
public func kk_range_first(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_first")
    }
    return range.first
}

@_cdecl("__kk_range_last")
public func kk_range_last(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_last")
    }
    return range.last
}

/// `IntProgression`/`LongProgression`/`CharProgression.first()` — throws on empty.
@_cdecl("__kk_range_first_orThrow")
public func kk_range_first_orThrow(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeFirstOrLastOrThrow(
        RuntimeSignedRangeHOFKind.self,
        rangeRaw,
        wantLast: false,
        outThrown,
        functionName: "__kk_range_first_orThrow"
    )
}

/// `IntProgression`/`LongProgression`/`CharProgression.last()` — throws on empty.
@_cdecl("__kk_range_last_orThrow")
public func kk_range_last_orThrow(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeFirstOrLastOrThrow(
        RuntimeSignedRangeHOFKind.self,
        rangeRaw,
        wantLast: true,
        outThrown,
        functionName: "__kk_range_last_orThrow"
    )
}


@_cdecl("__kk_range_count")
public func kk_range_count(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_count")
    }
    if range.step > 0 {
        guard range.first <= range.last else { return 0 }
        // Use wrapping arithmetic to avoid trapping on extreme ranges
        // (e.g., first == Int.min, last == Int.max).
        return (range.last &- range.first) / range.step &+ 1
    } else if range.step < 0 {
        guard range.first >= range.last else { return 0 }
        return (range.first &- range.last) / (0 &- range.step) &+ 1
    }
    return 0
}

@_cdecl("__kk_range_isEmpty")
public func kk_range_isEmpty(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_isEmpty")
    }
    if range.step > 0 {
        return range.first > range.last ? 1 : 0
    } else if range.step < 0 {
        return range.first < range.last ? 1 : 0
    }
    return 1
}

@_cdecl("__kk_range_sum")
public func kk_range_sum(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_sum")
    }
    var sum = 0
    _ = runtimeSignedRangeTraverse(range) { current, _ in
        sum &+= current
        return true
    }
    return sum
}

@_cdecl("__kk_range_contains")
public func kk_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_contains")
    }
    return runtimeRangeContains(range, value)
}

@_cdecl("__kk_range_endExclusive")
public func kk_range_endExclusive(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_range_endExclusive")
    }
    return range.last &+ 1
}

// MARK: - IntRange take/drop/average/sorted (STDLIB-RANGE-TDS)

@_cdecl("kk_range_take")
public func kk_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_take")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return RuntimeSignedRangeHOFKind.take(range, n)
}

@_cdecl("kk_range_drop")
public func kk_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_drop")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return RuntimeSignedRangeHOFKind.drop(range, n)
}

@_cdecl("kk_range_average")
public func kk_range_average(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_average")
    }
    return RuntimeSignedRangeHOFKind.average(range)
}

@_cdecl("kk_range_sorted")
public func kk_range_sorted(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_range_sorted")
    }
    return RuntimeSignedRangeHOFKind.sorted(range)
}

// MARK: - CharRange HOFs (STDLIB-290)

@_cdecl("__kk_char_range_step")
public func __kk_char_range_step(_ rangeRaw: Int, _ stepValue: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard stepValue > 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard stepValue != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Step must be positive, was: \(stepValue)."
        )
        return rangeRaw
    }
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return rangeRaw
    }
    if range.step == 0 {
        return registerRuntimeObject(RuntimeRangeBox(
            first: range.first,
            last: range.last,
            step: range.step,
            kind: .charProgression
        ))
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    let alignedLast = runtimeSignedProgressionLast(start: first, end: last, step: nextStep)
    return registerRuntimeObject(RuntimeRangeBox(
        first: first,
        last: alignedLast,
        step: nextStep,
        kind: .charProgression
    ))
}

@_cdecl("__kk_char_range_toList")
public func kk_char_range_toList(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    if range.step > 0 {
        var current = first
        while current <= last {
            elements.append(kk_box_char(current))
            if current == last { break }
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            elements.append(kk_box_char(current))
            if current == last { break }
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("__kk_char_range_forEach")
public func kk_char_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    guard let range = runtimeRangeBox(from: rangeRaw) else { return 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    if range.step > 0 {
        var current = first
        while current <= last {
            var thrown = 0
            // Pass raw char value (Unicode scalar) — the lambda expects Char-typed values
            _ = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if current == last { break }
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            var thrown = 0
            _ = lambda(closureRaw, current, &thrown)
            if thrown != 0 { outThrown?.pointee = thrown; return 0 }
            if current == last { break }
            current &+= range.step
        }
    }
    return 0
}

@_cdecl("__kk_char_range_take")
public func kk_char_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_take")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    guard n > 0 else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    var taken = 0
    if range.step > 0 {
        var current = first
        while current <= last && taken < n {
            elements.append(kk_box_char(current))
            if current == last { break }
            current &+= range.step
            taken += 1
        }
    } else if range.step < 0 {
        var current = first
        while current >= last && taken < n {
            elements.append(kk_box_char(current))
            if current == last { break }
            current &+= range.step
            taken += 1
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("__kk_char_range_drop")
public func kk_char_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_drop")
    }
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    var skipped = 0
    if range.step > 0 {
        var current = first
        while current <= last {
            if skipped >= n { elements.append(kk_box_char(current)) } else { skipped += 1 }
            if current == last { break }
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            if skipped >= n { elements.append(kk_box_char(current)) } else { skipped += 1 }
            if current == last { break }
            current &+= range.step
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("__kk_char_range_sorted")
public func kk_char_range_sorted(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_char_range_sorted")
    }
    let first = kk_unbox_char(range.first)
    let last = kk_unbox_char(range.last)
    var elements: [Int] = []
    if range.step > 0 {
        var current = first
        while current <= last {
            elements.append(kk_box_char(current))
            if current == last { break }
            current &+= range.step
        }
    } else if range.step < 0 {
        var current = first
        while current >= last {
            elements.append(kk_box_char(current))
            if current == last { break }
            current &+= range.step
        }
    }
    elements.sort { kk_unbox_char($0) < kk_unbox_char($1) }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("__kk_char_range_randomOrNull")
public func __kk_char_range_randomOrNull(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_randomOrNull")
    }
    return runtimeCharRangeRandomOrNull(range, randomRaw: nil)
}

@_cdecl("__kk_char_range_randomOrNull_random")
public func __kk_char_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_randomOrNull_random")
    }
    return runtimeCharRangeRandomOrNull(range, randomRaw: randomRaw)
}

@_cdecl("__kk_char_range_random")
public func __kk_char_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_random")
    }
    return runtimeCharRangeRandom(range, randomRaw: 0, outThrown: outThrown)
}

@_cdecl("__kk_char_range_random_random")
public func __kk_char_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in __kk_char_range_random_random")
    }
    return runtimeCharRangeRandom(range, randomRaw: randomRaw, outThrown: outThrown)
}

// MARK: - Progression fromClosedRange (STDLIB-RANGE-039)

func runtimeSignedProgressionLast(start: Int, end: Int, step: Int) -> Int {
    if step > 0 {
        guard start <= end else { return end }
        let distance = UInt(bitPattern: end &- start)
        let remainder = Int(bitPattern: distance % UInt(step))
        return end &- remainder
    }
    guard start >= end else { return end }
    let distance = UInt(bitPattern: start &- end)
    let remainder = Int(bitPattern: distance % UInt(bitPattern: 0 &- step))
    return end &+ remainder
}

func runtimeUnsignedProgressionLast(start: Int, end: Int, step: Int) -> Int {
    let startUnsigned = UInt(bitPattern: start)
    let endUnsigned = UInt(bitPattern: end)
    if step > 0 {
        guard startUnsigned <= endUnsigned else { return end }
        let magnitude = UInt(bitPattern: step)
        let distance = endUnsigned &- startUnsigned
        return Int(bitPattern: endUnsigned &- (distance % magnitude))
    }
    guard startUnsigned >= endUnsigned else { return end }
    let magnitude = UInt(bitPattern: 0 &- step)
    let distance = startUnsigned &- endUnsigned
    return Int(bitPattern: endUnsigned &+ (distance % magnitude))
}

@_cdecl("__kk_int_progression_fromClosedRange")
public func __kk_int_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // Validate step constraints
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeSignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(
        first: rangeStart,
        last: alignedLast,
        step: step,
        kind: .intProgression
    ))
}

@_cdecl("__kk_long_progression_fromClosedRange")
public func __kk_long_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // For LongProgression, we use the same RuntimeRangeBox but treat values as Long
    // Validate step constraints
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeSignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(
        first: rangeStart,
        last: alignedLast,
        step: step,
        kind: .longProgression
    ))
}

@_cdecl("__kk_uint_progression_fromClosedRange")
public func __kk_uint_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // UIntProgression uses signed Int for step, UInt for range values
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeUnsignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(
        first: rangeStart,
        last: alignedLast,
        step: step,
        kind: .uintProgression
    ))
}

@_cdecl("__kk_ulong_progression_fromClosedRange")
public func __kk_ulong_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    // ULongProgression uses signed Int for step, ULong for range values
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let alignedLast = runtimeUnsignedProgressionLast(start: rangeStart, end: rangeEnd, step: step)
    return registerRuntimeObject(RuntimeRangeBox(
        first: rangeStart,
        last: alignedLast,
        step: step,
        kind: .ulongProgression
    ))
}

@_cdecl("__kk_char_progression_fromClosedRange")
public func __kk_char_progression_fromClosedRange(_ receiverRaw: Int, _ rangeStart: Int, _ rangeEnd: Int, _ step: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = receiverRaw
    guard step != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be non-zero.")
        return 0
    }
    guard step != Int.min else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        return 0
    }
    let startChar = kk_unbox_char(rangeStart)
    let endChar = kk_unbox_char(rangeEnd)
    let alignedLast = runtimeSignedProgressionLast(start: startChar, end: endChar, step: step)
    return registerRuntimeObject(RuntimeRangeBox(
        first: startChar,
        last: alignedLast,
        step: step,
        kind: .charProgression
    ))
}

// MARK: - ULongRange properties (STDLIB-RANGE-037)

@_cdecl("kk_ulong_range_first_orThrow")
public func kk_ulong_range_first_orThrow(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeFirstOrLastOrThrow(
        RuntimeUnsignedRangeHOFKind.self,
        rangeRaw,
        wantLast: false,
        outThrown,
        functionName: "kk_ulong_range_first_orThrow"
    )
}

@_cdecl("kk_ulong_range_last_orThrow")
public func kk_ulong_range_last_orThrow(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeFirstOrLastOrThrow(
        RuntimeUnsignedRangeHOFKind.self,
        rangeRaw,
        wantLast: true,
        outThrown,
        functionName: "kk_ulong_range_last_orThrow"
    )
}

@_cdecl("kk_ulong_range_step")
public func kk_ulong_range_step(_ rangeRaw: Int) -> Int {
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid range handle in kk_ulong_range_step")
    }
    return range.step
}

private func runtimeRangeIteratorHasNext(_ iterator: RuntimeRangeIteratorBox) -> Int {
    iterator.hasNextValue ? 1 : 0
}

private func runtimeRangeIteratorNext(_ iterator: RuntimeRangeIteratorBox) -> Int {
    iterator.advance()
}

private func runtimeSignedRangeForInIteratorBox(from rawValue: Int) -> RuntimeSignedRangeForInIteratorBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSignedRangeForInIteratorBox.self)
}

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeIteratorBuilderBox.self)
}
