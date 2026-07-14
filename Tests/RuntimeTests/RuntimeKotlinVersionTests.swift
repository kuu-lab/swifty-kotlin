#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeKotlinVersionTests {
    @Test
    func testTwoArgumentConstructorDefaultsPatchToZero() {
        let version = kk_kotlin_version_new(2, 1)

        #expect(kk_kotlin_version_major(version) == 2)
        #expect(kk_kotlin_version_minor(version) == 1)
        #expect(kk_kotlin_version_patch(version) == 0)
    }

    @Test
    func testThreeArgumentConstructorStoresPatch() {
        let version = kk_kotlin_version_new_patch(2, 1, 20)

        #expect(kk_kotlin_version_major(version) == 2)
        #expect(kk_kotlin_version_minor(version) == 1)
        #expect(kk_kotlin_version_patch(version) == 20)
    }

    @Test
    func testCurrentReturnsStableKotlinVersion() {
        let version = kk_kotlin_version_current()

        #expect(kk_kotlin_version_major(version) == 2)
        #expect(kk_kotlin_version_minor(version) == 3)
        #expect(kk_kotlin_version_patch(version) == 20)
    }

    @Test
    func testCompareToUsesSemanticVersionOrdering() {
        let lower = kk_kotlin_version_new_patch(2, 1, 20)
        let same = kk_kotlin_version_new_patch(2, 1, 20)
        let higherPatch = kk_kotlin_version_new_patch(2, 1, 21)
        let higherMinor = kk_kotlin_version_new_patch(2, 2, 0)
        let higherMajor = kk_kotlin_version_new_patch(3, 0, 0)

        #expect(kk_kotlin_version_compareTo(lower, same) == 0)
        #expect(kk_kotlin_version_compareTo(lower, higherPatch) < 0)
        #expect(kk_kotlin_version_compareTo(lower, higherMinor) < 0)
        #expect(kk_kotlin_version_compareTo(lower, higherMajor) < 0)
        #expect(kk_kotlin_version_compareTo(higherPatch, lower) > 0)
    }

    @Test
    func testIsAtLeastChecksTwoAndThreePartMinimums() {
        let version = kk_kotlin_version_new_patch(2, 1, 20)

        #expect(kk_kotlin_version_isAtLeast(version, 2, 1) == 1)
        #expect(kk_kotlin_version_isAtLeast(version, 2, 2) == 0)
        #expect(kk_kotlin_version_isAtLeast_patch(version, 2, 1, 20) == 1)
        #expect(kk_kotlin_version_isAtLeast_patch(version, 2, 1, 21) == 0)
        #expect(kk_kotlin_version_isAtLeast_patch(version, 1, 9, 99) == 1)
    }
}
#endif
