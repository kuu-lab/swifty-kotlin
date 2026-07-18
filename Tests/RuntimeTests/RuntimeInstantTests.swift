#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeInstantTests {
    @Test
    func testInstantFromEpochMillisecondsUsesValueEquality() {
        let first = kk_instant_from_epoch_millis(0)
        let second = kk_instant_from_epoch_millis(0)

        #expect(kk_instant_compare(first, second) == 0)
        #expect(kk_structural_eq(first, second) == 1)
        #expect(kk_structural_ne(first, second) == 0)
        #expect(kk_any_hashCode(first, 0) == kk_any_hashCode(second, 0))
    }

    @Test
    func testInstantFromEpochSecondsPreservesAndNormalizesNanoseconds() {
        let instant = kk_instant_from_epoch_seconds(1_700_000_000, 123_456_789)

        #expect(kk_instant_epoch_seconds(instant) == 1_700_000_000)
        #expect(kk_instant_nano_of_second(instant) == 123_456_789)
        #expect(kk_instant_to_epoch_millis(instant) == 1_700_000_000_123)

        let adjusted = kk_instant_from_epoch_seconds(1, 1_500_000_000)
        #expect(kk_instant_epoch_seconds(adjusted) == 2)
        #expect(kk_instant_nano_of_second(adjusted) == 500_000_000)
        #expect(kk_instant_to_epoch_millis(adjusted) == 2_500)
    }

    @Test
    func testInstantEpochMillisecondsForBeforeEpochValues() {
        let beforeEpoch = kk_instant_from_epoch_seconds(-2, 500_000_000)

        #expect(kk_instant_epoch_seconds(beforeEpoch) == -2)
        #expect(kk_instant_nano_of_second(beforeEpoch) == 500_000_000)
        #expect(kk_instant_to_epoch_millis(beforeEpoch) == -1_500)
    }

    @Test
    func testInstantFoundationDateBridgeRoundTripsEpochMilliseconds() {
        let instant = kk_instant_from_epoch_seconds(-1, 250_000_000)
        let foundationDate = kk_instant_to_foundation_date(instant)

        let roundTripped = kk_foundation_date_to_kotlin_instant(foundationDate)
        #expect(kk_instant_compare(roundTripped, instant) == 0)
        #expect(kk_instant_to_epoch_millis(roundTripped) == -750)
    }

    @Test
    func testInstantUntilMatchesExpectedDuration() {
        let start = kk_instant_from_epoch_millis(1_000)
        let end = kk_instant_from_epoch_millis(3_000)

        let duration = kk_instant_until(start, end)

        #expect(durationInWholeSeconds(duration) == 2)
        #expect(durationInWholeMilliseconds(duration) == 2_000)
    }

    @Test
    func testInstantDistantPropertiesUseKotlinThresholds() {
        let ordinary = kk_instant_from_epoch_millis(0)
        #expect(kk_instant_is_distant_past(ordinary) == 0)
        #expect(kk_instant_is_distant_future(ordinary) == 0)

        let distantPast = kk_instant_from_epoch_millis(-3_217_862_419_200_001)
        let justAfterDistantPast = kk_instant_from_epoch_millis(-3_217_862_419_200_000)
        #expect(kk_instant_is_distant_past(distantPast) == 1)
        #expect(kk_instant_is_distant_past(justAfterDistantPast) == 0)

        let distantFuture = kk_instant_from_epoch_millis(3_093_527_980_800_000)
        let justBeforeDistantFuture = kk_instant_from_epoch_millis(3_093_527_980_799_999)
        #expect(kk_instant_is_distant_future(distantFuture) == 1)
        #expect(kk_instant_is_distant_future(justBeforeDistantFuture) == 0)
    }
}
#endif
