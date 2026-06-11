@testable import Runtime
import XCTest

final class RuntimeTimeConversionTests: XCTestCase {
    func testInstantJavaInstantRoundTripPreservesComponents() {
        let instant = kk_instant_from_epoch_millis(1_234)
        let javaInstant = kk_instant_to_java_instant(instant)
        let roundTrip = kk_java_instant_to_kotlin_instant(javaInstant)

        XCTAssertEqual(kk_instant_epoch_seconds(roundTrip), 1)
        XCTAssertEqual(kk_instant_nano_of_second(roundTrip), 234_000_000)
    }

    func testInstantJSDateRoundTripPreservesFractionalMilliseconds() {
        let instant = registerRuntimeObject(RuntimeInstantBox(epochSeconds: 12, nanoOfSecond: 345_678_900))
        let jsDate = kk_instant_to_js_date(instant)
        let roundTrip = kk_js_date_to_kotlin_instant(jsDate)

        XCTAssertEqual(kk_instant_epoch_seconds(roundTrip), 12)
        XCTAssertEqual(kk_instant_nano_of_second(roundTrip), 345_678_900)
    }

    func testTimeUnitToDurationUnitMapsEachOrdinalToItself() {
        // TimeUnit and DurationUnit share entry ordering, so the conversion is identity.
        // 0=NANOSECONDS, 1=MICROSECONDS, 2=MILLISECONDS, 3=SECONDS, 4=MINUTES, 5=HOURS, 6=DAYS.
        for ordinal in 0...6 {
            XCTAssertEqual(kk_time_unit_to_duration_unit(ordinal), ordinal)
        }
    }

    func testDurationUnitToTimeUnitIsOrdinalIdentity() {
        // DurationUnit and java.util.concurrent.TimeUnit share entry order:
        // NANOSECONDS=0, MICROSECONDS=1, MILLISECONDS=2, SECONDS=3,
        // MINUTES=4, HOURS=5, DAYS=6.
        for ordinal in 0...6 {
            XCTAssertEqual(
                kk_duration_unit_to_time_unit(ordinal),
                ordinal,
                "DurationUnit ordinal \(ordinal) must map to the matching TimeUnit ordinal"
            )
        }
    }
}
