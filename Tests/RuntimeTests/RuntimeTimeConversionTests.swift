@testable import Runtime
import XCTest

final class RuntimeTimeConversionTests: XCTestCase {
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
