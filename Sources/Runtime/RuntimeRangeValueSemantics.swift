/// The nominal Kotlin range type represented by a RuntimeRangeBox.
///
/// Range expressions are intentionally represented as their scalar element type
/// in the compiler's type checker, so the runtime must retain this distinction
/// for Any.equals/hashCode and collection keys.
enum RuntimeRangeKind: Int32 {
    case intRange = 1
    case intProgression = 2
    case longRange = 3
    case longProgression = 4
    case charRange = 5
    case charProgression = 6
    case uintRange = 7
    case uintProgression = 8
    case ulongRange = 9
    case ulongProgression = 10

    var isProgression: Bool {
        switch self {
        case .intProgression, .longProgression, .charProgression,
             .uintProgression, .ulongProgression:
            true
        case .intRange, .longRange, .charRange, .uintRange, .ulongRange:
            false
        }
    }

    var progressionKind: RuntimeRangeKind {
        switch self {
        case .intRange, .intProgression:
            .intProgression
        case .longRange, .longProgression:
            .longProgression
        case .charRange, .charProgression:
            .charProgression
        case .uintRange, .uintProgression:
            .uintProgression
        case .ulongRange, .ulongProgression:
            .ulongProgression
        }
    }

    var usesUnsignedValues: Bool {
        switch self {
        case .uintRange, .uintProgression, .ulongRange, .ulongProgression:
            true
        case .intRange, .intProgression, .longRange, .longProgression,
             .charRange, .charProgression:
            false
        }
    }
}

func runtimeRangeIsEmpty(_ range: RuntimeRangeBox) -> Bool {
    if range.kind.usesUnsignedValues {
        let first = UInt(bitPattern: range.first)
        let last = UInt(bitPattern: range.last)
        if range.step > 0 {
            return first > last
        }
        if range.step < 0 {
            return first < last
        }
        return true
    }

    if range.step > 0 {
        return range.first > range.last
    }
    if range.step < 0 {
        return range.first < range.last
    }
    return true
}

private func runtimeRangeIntHash(_ value: Int) -> Int32 {
    Int32(truncatingIfNeeded: value)
}

private func runtimeRangeLongHash(_ value: Int) -> Int32 {
    let bits = UInt64(bitPattern: Int64(value))
    return Int32(truncatingIfNeeded: bits ^ (bits >> 32))
}

func runtimeRangeHashCode(_ range: RuntimeRangeBox) -> Int {
    guard !runtimeRangeIsEmpty(range) else {
        return -1
    }

    let hash: Int32
    switch range.kind {
    case .intRange, .charRange, .uintRange:
        hash = 31 &* runtimeRangeIntHash(range.first)
            &+ runtimeRangeIntHash(range.last)
    case .longRange, .ulongRange:
        hash = 31 &* runtimeRangeLongHash(range.first)
            &+ runtimeRangeLongHash(range.last)
    case .intProgression, .charProgression, .uintProgression:
        hash = 31 &* (31 &* runtimeRangeIntHash(range.first)
            &+ runtimeRangeIntHash(range.last))
            &+ runtimeRangeIntHash(range.step)
    case .longProgression, .ulongProgression:
        hash = 31 &* (31 &* runtimeRangeLongHash(range.first)
            &+ runtimeRangeLongHash(range.last))
            &+ runtimeRangeLongHash(range.step)
    }
    return Int(hash)
}

func runtimeRangesEqual(_ lhs: RuntimeRangeBox, _ rhs: RuntimeRangeBox) -> Bool {
    guard lhs.kind == rhs.kind else {
        return false
    }
    if runtimeRangeIsEmpty(lhs), runtimeRangeIsEmpty(rhs) {
        return true
    }
    guard lhs.first == rhs.first, lhs.last == rhs.last else {
        return false
    }
    return !lhs.kind.isProgression || lhs.step == rhs.step
}

/// Nominal type ID a `RuntimeRangeBox` kind stands in for during `is`/`as`
/// checks. Range handles are allocated by the `__kk_*_rangeTo`/`downTo`/`until`
/// factories and never carry `objectTypeByPointer` metadata, so `kk_op_is`
/// recovers the nominal identity from the kind tag — mirroring
/// `runtimePrimitiveBoxNominalTypeID` for primitive boxes.
func runtimeRangeBoxNominalTypeID(_ kind: RuntimeRangeKind) -> Int64 {
    switch kind {
    case .intRange: runtimeStableNominalTypeID(fqName: "kotlin.ranges.IntRange")
    case .intProgression: runtimeStableNominalTypeID(fqName: "kotlin.ranges.IntProgression")
    case .longRange: runtimeStableNominalTypeID(fqName: "kotlin.ranges.LongRange")
    case .longProgression: runtimeStableNominalTypeID(fqName: "kotlin.ranges.LongProgression")
    case .charRange: runtimeStableNominalTypeID(fqName: "kotlin.ranges.CharRange")
    case .charProgression: runtimeStableNominalTypeID(fqName: "kotlin.ranges.CharProgression")
    case .uintRange: runtimeStableNominalTypeID(fqName: "kotlin.ranges.UIntRange")
    case .uintProgression: runtimeStableNominalTypeID(fqName: "kotlin.ranges.UIntProgression")
    case .ulongRange: runtimeStableNominalTypeID(fqName: "kotlin.ranges.ULongRange")
    case .ulongProgression: runtimeStableNominalTypeID(fqName: "kotlin.ranges.ULongProgression")
    }
}

/// Installs the nominal supertype edges range classes have in Kotlin:
/// `XRange : XProgression, ClosedRange<X>, OpenEndRange<X>`,
/// `XProgression : Iterable<X>`, and `ClosedFloatingPointRange : ClosedRange`.
/// Mirrors `RuntimePrimitiveNominalTypeIDs.registerEdgesOnce`, including its
/// resettability: `kk_runtime_reset_metadata` clears `typeParents` and
/// `rangeTypeEdgesRegistered` together so the edges re-register on the next
/// `is` check after a metadata reset.
func registerRangeTypeEdgesOnce() {
    runtimeStorage.withMetadataLock { state in
        if state.rangeTypeEdgesRegistered {
            return
        }
        let closedRange = runtimeStableNominalTypeID(fqName: "kotlin.ranges.ClosedRange")
        let openEndRange = runtimeStableNominalTypeID(fqName: "kotlin.ranges.OpenEndRange")
        let iterable = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")
        for (range, progression) in [
            (RuntimeRangeKind.intRange, RuntimeRangeKind.intProgression),
            (RuntimeRangeKind.longRange, RuntimeRangeKind.longProgression),
            (RuntimeRangeKind.charRange, RuntimeRangeKind.charProgression),
            (RuntimeRangeKind.uintRange, RuntimeRangeKind.uintProgression),
            (RuntimeRangeKind.ulongRange, RuntimeRangeKind.ulongProgression),
        ] {
            let rangeID = runtimeRangeBoxNominalTypeID(range)
            let progressionID = runtimeRangeBoxNominalTypeID(progression)
            state.typeParents[rangeID, default: []].insert(progressionID)
            state.typeParents[rangeID, default: []].insert(closedRange)
            state.typeParents[rangeID, default: []].insert(openEndRange)
            state.typeParents[progressionID, default: []].insert(iterable)
        }
        let closedFloatingPointRange = runtimeStableNominalTypeID(
            fqName: "kotlin.ranges.ClosedFloatingPointRange"
        )
        state.typeParents[closedFloatingPointRange, default: []].insert(closedRange)
        state.rangeTypeEdgesRegistered = true
    }
}
