@testable import Runtime
import Testing

/// KUU-952 regression coverage: range values and range iterators are
/// runtime-internal boxes allocated by the `__kk_*_rangeTo`/`downTo`/`until`
/// and `kk_range_iterator`/`kk_iterable_iterator` factories, so they carry no
/// `objectTypeByPointer` metadata. `kk_op_is` recovers their nominal identity
/// structurally -- `RuntimeRangeBox` by its kind tag and
/// `RuntimeRangeIteratorBox` as `kotlin.collections.Iterator`.
///
/// `RuntimeRangeIteratorBox` intentionally answers `is Iterator` only: the
/// element-specialized `XIterator` classes (`IntIterator`/`CharIterator`/...)
/// can't be honored because member calls on an `XIterator` receiver lower to
/// vtable/itable dispatch that an unregistered box cannot answer, so claiming
/// them would turn `is IntIterator` into a reachable dispatch trap.
@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeIsCheckRangeBoxTests {
    private var intRangeToken: Int { nominalTypeToken(for: "kotlin.ranges.IntRange") }
    private var intProgressionToken: Int { nominalTypeToken(for: "kotlin.ranges.IntProgression") }
    private var longRangeToken: Int { nominalTypeToken(for: "kotlin.ranges.LongRange") }
    private var longProgressionToken: Int { nominalTypeToken(for: "kotlin.ranges.LongProgression") }
    private var charRangeToken: Int { nominalTypeToken(for: "kotlin.ranges.CharRange") }
    private var charProgressionToken: Int { nominalTypeToken(for: "kotlin.ranges.CharProgression") }
    private var uintRangeToken: Int { nominalTypeToken(for: "kotlin.ranges.UIntRange") }
    private var uintProgressionToken: Int { nominalTypeToken(for: "kotlin.ranges.UIntProgression") }
    private var ulongRangeToken: Int { nominalTypeToken(for: "kotlin.ranges.ULongRange") }
    private var ulongProgressionToken: Int { nominalTypeToken(for: "kotlin.ranges.ULongProgression") }
    private var closedRangeToken: Int { nominalTypeToken(for: "kotlin.ranges.ClosedRange") }
    private var openEndRangeToken: Int { nominalTypeToken(for: "kotlin.ranges.OpenEndRange") }
    private var closedFloatingPointRangeToken: Int {
        nominalTypeToken(for: "kotlin.ranges.ClosedFloatingPointRange")
    }
    private var iterableToken: Int { nominalTypeToken(for: "kotlin.collections.Iterable") }
    private var iteratorToken: Int { nominalTypeToken(for: "kotlin.collections.Iterator") }
    private var mutableIteratorToken: Int { nominalTypeToken(for: "kotlin.collections.MutableIterator") }
    private var listIteratorToken: Int { nominalTypeToken(for: "kotlin.collections.ListIterator") }
    private var intIteratorToken: Int { nominalTypeToken(for: "kotlin.collections.IntIterator") }
    private var listToken: Int { nominalTypeToken(for: "kotlin.collections.List") }
    private var stringToken: Int { nominalTypeToken(for: "kotlin.String") }

    private func rangeBox(_ kind: RuntimeRangeKind, step: Int = 1) -> Int {
        registerRuntimeObject(RuntimeRangeBox(first: 1, last: 5, step: step, kind: kind))
    }

    @Test
    func rangeBoxesAnswerTheirOwnNominal() {
        let cases: [(kind: RuntimeRangeKind, range: Int, progression: Int)] = [
            (.intRange, intRangeToken, intProgressionToken),
            (.intProgression, intRangeToken, intProgressionToken),
            (.longRange, longRangeToken, longProgressionToken),
            (.longProgression, longRangeToken, longProgressionToken),
            (.charRange, charRangeToken, charProgressionToken),
            (.charProgression, charRangeToken, charProgressionToken),
            (.uintRange, uintRangeToken, uintProgressionToken),
            (.uintProgression, uintRangeToken, uintProgressionToken),
            (.ulongRange, ulongRangeToken, ulongProgressionToken),
            (.ulongProgression, ulongRangeToken, ulongProgressionToken),
        ]
        for (kind, rangeToken, progressionToken) in cases {
            let value = rangeBox(kind)
            if kind.isProgression {
                // A bare progression is not a ClosedRange (kotlinc: `5 downTo 1`
                // `is IntRange` is false).
                #expect(kk_op_is(value, rangeToken) == 0)
                #expect(kk_op_is(value, progressionToken) == 1)
                #expect(kk_op_is(value, closedRangeToken) == 0)
                #expect(kk_op_is(value, openEndRangeToken) == 0)
            } else {
                // A range is also its own progression (kotlinc: `1..5`
                // `is IntProgression` is true).
                #expect(kk_op_is(value, rangeToken) == 1)
                #expect(kk_op_is(value, progressionToken) == 1)
                #expect(kk_op_is(value, closedRangeToken) == 1)
                #expect(kk_op_is(value, openEndRangeToken) == 1)
            }
            #expect(kk_op_is(value, iterableToken) == 1)
        }
    }

    @Test
    func rangeBoxesRejectUnrelatedNominals() {
        let intRange = rangeBox(.intRange)
        #expect(kk_op_is(intRange, uintRangeToken) == 0)
        #expect(kk_op_is(intRange, longRangeToken) == 0)
        #expect(kk_op_is(intRange, ulongProgressionToken) == 0)
        #expect(kk_op_is(intRange, closedFloatingPointRangeToken) == 0)
        #expect(kk_op_is(intRange, listToken) == 0)
        #expect(kk_op_is(intRange, stringToken) == 0)
        #expect(kk_op_is(intRange, iteratorToken) == 0)

        let uintRange = rangeBox(.uintRange)
        #expect(kk_op_is(uintRange, intRangeToken) == 0)
        #expect(kk_op_is(uintRange, ulongRangeToken) == 0)
    }

    @Test
    func floatingPointRangeBoxesAnswerClosedFloatingPointRange() {
        let doubleRange = registerRuntimeObject(
            RuntimeDoubleRangeBox(first: 1.0, last: 5.0)
        )
        #expect(kk_op_is(doubleRange, closedFloatingPointRangeToken) == 1)
        #expect(kk_op_is(doubleRange, closedRangeToken) == 1)
        #expect(kk_op_is(doubleRange, openEndRangeToken) == 0)
        #expect(kk_op_is(doubleRange, iterableToken) == 0)
    }

    @Test
    func rangeIteratorsAnswerIteratorInterface() {
        for kind in [
            RuntimeRangeKind.intRange, .longRange, .charRange, .uintRange,
            .ulongRange, .intProgression,
        ] {
            let iterator = registerRuntimeObject(
                RuntimeRangeIteratorBox(current: 1, last: 5, step: 1, kind: kind)
            )
            #expect(kk_op_is(iterator, iteratorToken) == 1)
            #expect(kk_op_is(iterator, mutableIteratorToken) == 0)
            #expect(kk_op_is(iterator, listIteratorToken) == 0)
            #expect(kk_op_is(iterator, iterableToken) == 0)
            #expect(kk_op_is(iterator, stringToken) == 0)
        }
    }

    @Test
    func rangeIteratorsRejectSpecializedIteratorClasses() {
        // `is IntIterator` stays false deliberately: member calls on an
        // `IntIterator` receiver lower to vtable/itable dispatch the box can't
        // answer, so a true answer would open a reachable dispatch trap.
        let iterator = registerRuntimeObject(
            RuntimeRangeIteratorBox(current: 1, last: 5, step: 1, kind: .intRange)
        )
        #expect(kk_op_is(iterator, intIteratorToken) == 0)
    }

    @Test
    func iteratorFactoryProducesCheckableBox() {
        // End-to-end through the real factory: `kk_range_iterator` must hand
        // back the box the nominalBase recovery recognizes.
        let range = kk_op_rangeTo(1, 5)
        let iterator = kk_range_iterator(range)
        #expect(kk_op_is(iterator, iteratorToken) == 1)
        #expect(kk_op_is(iterator, intRangeToken) == 0)
    }

    @Test
    func safeCastsUseTheSameRecovery() {
        let range = rangeBox(.intRange)
        #expect(kk_op_safe_cast(range, intRangeToken) == range)
        #expect(kk_op_safe_cast(range, closedRangeToken) == range)
        #expect(kk_op_safe_cast(range, uintRangeToken) == runtimeNullSentinelInt)

        let iterator = registerRuntimeObject(
            RuntimeRangeIteratorBox(current: 1, last: 5, step: 1, kind: .intRange)
        )
        #expect(kk_op_safe_cast(iterator, iteratorToken) == iterator)
        #expect(kk_op_safe_cast(iterator, intIteratorToken) == runtimeNullSentinelInt)
    }
}
