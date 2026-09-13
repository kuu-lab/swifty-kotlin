#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimePlatformInfoTests {

    // MARK: - OsFamily

    @Test
    func testOsFamilyOnMacOSReturnsMACOSX() {
        let ordinal = kk_platform_osFamily(0)
        let unboxed = kk_unbox_int(ordinal)
#if os(macOS)
        #expect(unboxed == 1, "Expected OsFamily.MACOSX (1) on macOS, got \(unboxed)")
#else
        #expect(unboxed >= 0, "OsFamily ordinal must be non-negative")
        #expect(unboxed <= 8, "OsFamily ordinal must be within the defined range [0,8]")
#endif
    }

    @Test
    func testOsFamilyOrdinalIsWithinKnownRange() {
        let ordinal = kk_unbox_int(kk_platform_osFamily(0))
        #expect(ordinal >= 0)
        #expect(ordinal <= 8, "OsFamily ordinal \(ordinal) is outside the defined range [0,8]")
    }

    @Test
    func testOsFamilyIsStableAcrossRepeatedCalls() {
        let first  = kk_platform_osFamily(0)
        let second = kk_platform_osFamily(0)
        #expect(first == second, "kk_platform_osFamily should return a stable cached value")
    }

    @Test
    func testOsFamilyIgnoresPlatformArgument() {
        let a = kk_unbox_int(kk_platform_osFamily(0))
        let b = kk_unbox_int(kk_platform_osFamily(42))
        let c = kk_unbox_int(kk_platform_osFamily(-1))
        #expect(a == b)
        #expect(b == c)
    }

    // MARK: - CpuArchitecture

    /// On Apple Silicon the architecture ordinal must equal 2 (ARM64);
    /// on Intel it must equal 4 (X64), matching Kotlin 2.3.10 declaration order.
    @Test
    func testCpuArchitectureIsARM64orX64() {
        let ordinal = kk_unbox_int(kk_platform_cpuArchitecture(0))
#if arch(arm64)
        #expect(ordinal == 2, "Expected CpuArchitecture.ARM64 (2) on Apple Silicon, got \(ordinal)")
#elseif arch(x86_64)
        #expect(ordinal == 4, "Expected CpuArchitecture.X64 (4) on Intel, got \(ordinal)")
#else
        #expect(ordinal >= 0)
#endif
    }

    @Test
    func testCpuArchitectureOrdinalIsWithinKnownRange() {
        let ordinal = kk_unbox_int(kk_platform_cpuArchitecture(0))
        #expect(ordinal >= 0)
        #expect(ordinal <= 7, "CpuArchitecture ordinal \(ordinal) is outside the defined range [0,7]")
    }

    @Test
    func testCpuArchitectureIsStableAcrossRepeatedCalls() {
        let first  = kk_platform_cpuArchitecture(0)
        let second = kk_platform_cpuArchitecture(0)
        #expect(first == second)
    }

    @Test
    func testCpuArchitectureIgnoresPlatformArgument() {
        let a = kk_unbox_int(kk_platform_cpuArchitecture(0))
        let b = kk_unbox_int(kk_platform_cpuArchitecture(99))
        #expect(a == b)
    }

    // MARK: - isLittleEndian

    @Test
    func testIsLittleEndianIsTrueOnApplePlatforms() {
        let result = kk_platform_isLittleEndian(0)
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || (os(Linux) && (arch(x86_64) || arch(arm64)))
        #expect(result == 1, "Expected isLittleEndian == true on this platform, got \(result)")
#else
        #expect(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
#endif
    }

    @Test
    func testIsLittleEndianReturnsBooleanInt() {
        let result = kk_platform_isLittleEndian(0)
        #expect(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
    }

    @Test
    func testIsLittleEndianIsIdempotent() {
        let first  = kk_platform_isLittleEndian(0)
        let second = kk_platform_isLittleEndian(0)
        #expect(first == second)
    }

    @Test
    func testIsLittleEndianIgnoresPlatformArgument() {
        let a = kk_platform_isLittleEndian(0)
        let b = kk_platform_isLittleEndian(999)
        #expect(a == b)
    }

    // MARK: - canAccessUnaligned

    @Test
    func testCanAccessUnalignedIsTrueOnCommonArchitectures() {
        let result = kk_platform_canAccessUnaligned(0)
#if arch(x86_64) || arch(arm64) || arch(i386)
        #expect(result == 1, "Expected canAccessUnaligned == true on x86_64/arm64, got \(result)")
#else
        #expect(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
#endif
    }

    @Test
    func testCanAccessUnalignedReturnsBooleanInt() {
        let result = kk_platform_canAccessUnaligned(0)
        #expect(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
    }

    @Test
    func testCanAccessUnalignedIsIdempotent() {
        let first  = kk_platform_canAccessUnaligned(0)
        let second = kk_platform_canAccessUnaligned(0)
        #expect(first == second)
    }

    @Test
    func testCanAccessUnalignedIgnoresPlatformArgument() {
        let a = kk_platform_canAccessUnaligned(0)
        let b = kk_platform_canAccessUnaligned(-42)
        #expect(a == b)
    }

    // MARK: - isLittleEndian / canAccessUnaligned consistency

    @Test
    func testIsLittleEndianAndCanAccessUnalignedAreConsistentOnApplePlatforms() {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let le  = kk_platform_isLittleEndian(0)
        let cau = kk_platform_canAccessUnaligned(0)
        #expect(le == 1, "Apple platforms are little-endian")
        #expect(cau == 1, "Apple arm64/x86_64 support unaligned access")
#endif
    }

    // MARK: - getAvailableProcessors

    @Test
    func testGetAvailableProcessorsReturnsAtLeastOne() {
        let count = kk_platform_getAvailableProcessors(0)
        #expect(count >= 1)
    }

    @Test
    func testGetAvailableProcessorsIsPlausible() {
        let count = kk_platform_getAvailableProcessors(0)
        #expect(count <= 1024, "Unexpectedly large processor count: \(count)")
    }

    @Test
    func testGetAvailableProcessorsIsStable() {
        let first  = kk_platform_getAvailableProcessors(0)
        let second = kk_platform_getAvailableProcessors(0)
        #expect(first == second)
    }
}

#endif
