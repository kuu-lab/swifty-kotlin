@testable import Runtime
import XCTest

final class RuntimePlatformInfoTests: XCTestCase {

    // MARK: - OsFamily

    func testOsFamilyOnMacOSReturnsMACOSX() {
        let ordinal = kk_platform_osFamily(0)
        let unboxed = kk_unbox_int(ordinal)
#if os(macOS)
        XCTAssertEqual(unboxed, 1, "Expected OsFamily.MACOSX (1) on macOS, got \(unboxed)")
#else
        XCTAssertGreaterThanOrEqual(unboxed, 0, "OsFamily ordinal must be non-negative")
        XCTAssertLessThanOrEqual(unboxed, 8, "OsFamily ordinal must be within the defined range [0,8]")
#endif
    }

    func testOsFamilyOrdinalIsWithinKnownRange() {
        let ordinal = kk_unbox_int(kk_platform_osFamily(0))
        XCTAssertGreaterThanOrEqual(ordinal, 0)
        XCTAssertLessThanOrEqual(ordinal, 8, "OsFamily ordinal \(ordinal) is outside the defined range [0,8]")
    }

    func testOsFamilyIsStableAcrossRepeatedCalls() {
        let first  = kk_platform_osFamily(0)
        let second = kk_platform_osFamily(0)
        XCTAssertEqual(first, second, "kk_platform_osFamily should return a stable cached value")
    }

    func testOsFamilyIgnoresPlatformArgument() {
        let a = kk_unbox_int(kk_platform_osFamily(0))
        let b = kk_unbox_int(kk_platform_osFamily(42))
        let c = kk_unbox_int(kk_platform_osFamily(-1))
        XCTAssertEqual(a, b)
        XCTAssertEqual(b, c)
    }

    // MARK: - CpuArchitecture

    func testCpuArchitectureIsARM64orX64() {
        let ordinal = kk_unbox_int(kk_platform_cpuArchitecture(0))
#if arch(arm64)
        XCTAssertEqual(ordinal, 4, "Expected CpuArchitecture.ARM64 (4) on Apple Silicon, got \(ordinal)")
#elseif arch(x86_64)
        XCTAssertEqual(ordinal, 2, "Expected CpuArchitecture.X64 (2) on Intel, got \(ordinal)")
#else
        XCTAssertGreaterThanOrEqual(ordinal, 0)
#endif
    }

    func testCpuArchitectureOrdinalIsWithinKnownRange() {
        let ordinal = kk_unbox_int(kk_platform_cpuArchitecture(0))
        XCTAssertGreaterThanOrEqual(ordinal, 0)
        XCTAssertLessThanOrEqual(ordinal, 7, "CpuArchitecture ordinal \(ordinal) is outside the defined range [0,7]")
    }

    func testCpuArchitectureIsStableAcrossRepeatedCalls() {
        let first  = kk_platform_cpuArchitecture(0)
        let second = kk_platform_cpuArchitecture(0)
        XCTAssertEqual(first, second)
    }

    func testCpuArchitectureIgnoresPlatformArgument() {
        let a = kk_unbox_int(kk_platform_cpuArchitecture(0))
        let b = kk_unbox_int(kk_platform_cpuArchitecture(99))
        XCTAssertEqual(a, b)
    }

    // MARK: - isLittleEndian

    func testIsLittleEndianIsTrueOnApplePlatforms() {
        let result = kk_platform_isLittleEndian(0)
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || (os(Linux) && (arch(x86_64) || arch(arm64)))
        XCTAssertEqual(result, 1, "Expected isLittleEndian == true on this platform, got \(result)")
#else
        XCTAssertTrue(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
#endif
    }

    func testIsLittleEndianReturnsBooleanInt() {
        let result = kk_platform_isLittleEndian(0)
        XCTAssertTrue(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
    }

    func testIsLittleEndianIsIdempotent() {
        let first  = kk_platform_isLittleEndian(0)
        let second = kk_platform_isLittleEndian(0)
        XCTAssertEqual(first, second)
    }

    func testIsLittleEndianIgnoresPlatformArgument() {
        let a = kk_platform_isLittleEndian(0)
        let b = kk_platform_isLittleEndian(999)
        XCTAssertEqual(a, b)
    }

    // MARK: - canAccessUnaligned

    func testCanAccessUnalignedIsTrueOnCommonArchitectures() {
        let result = kk_platform_canAccessUnaligned(0)
#if arch(x86_64) || arch(arm64) || arch(i386)
        XCTAssertEqual(result, 1, "Expected canAccessUnaligned == true on x86_64/arm64, got \(result)")
#else
        XCTAssertTrue(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
#endif
    }

    func testCanAccessUnalignedReturnsBooleanInt() {
        let result = kk_platform_canAccessUnaligned(0)
        XCTAssertTrue(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
    }

    func testCanAccessUnalignedIsIdempotent() {
        let first  = kk_platform_canAccessUnaligned(0)
        let second = kk_platform_canAccessUnaligned(0)
        XCTAssertEqual(first, second)
    }

    func testCanAccessUnalignedIgnoresPlatformArgument() {
        let a = kk_platform_canAccessUnaligned(0)
        let b = kk_platform_canAccessUnaligned(-42)
        XCTAssertEqual(a, b)
    }

    // MARK: - isLittleEndian / canAccessUnaligned consistency

    func testIsLittleEndianAndCanAccessUnalignedAreConsistentOnApplePlatforms() {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let le  = kk_platform_isLittleEndian(0)
        let cau = kk_platform_canAccessUnaligned(0)
        XCTAssertEqual(le, 1, "Apple platforms are little-endian")
        XCTAssertEqual(cau, 1, "Apple arm64/x86_64 support unaligned access")
#endif
    }

    // MARK: - getAvailableProcessors

    func testGetAvailableProcessorsReturnsAtLeastOne() {
        let count = kk_platform_getAvailableProcessors(0)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testGetAvailableProcessorsIsPlausible() {
        let count = kk_platform_getAvailableProcessors(0)
        XCTAssertLessThanOrEqual(count, 1024, "Unexpectedly large processor count: \(count)")
    }

    func testGetAvailableProcessorsIsStable() {
        let first  = kk_platform_getAvailableProcessors(0)
        let second = kk_platform_getAvailableProcessors(0)
        XCTAssertEqual(first, second)
    }
}
