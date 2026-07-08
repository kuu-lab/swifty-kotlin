@testable import Runtime
import XCTest

// STDLIB-TEXT-FN-044: String.random() / String.random(Random)
final class RuntimeStringRandomTests: XCTestCase {

    // MARK: - kk_string_random (default random)

    func testRandomReturnsCharFromSingleCharString() {
        let str = runtimeMakeStringRaw("A")
        var thrown = 0
        let result = kk_string_random(str, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_char(result), Int(("A" as Unicode.Scalar).value))
    }

    func testRandomReturnsCharWithinString() {
        let str = runtimeMakeStringRaw("abcde")
        for _ in 0..<20 {
            var thrown = 0
            let result = kk_string_random(str, &thrown)
            XCTAssertEqual(thrown, 0)
            let ch = kk_unbox_char(result)
            XCTAssertTrue(ch >= Int(("a" as Unicode.Scalar).value) && ch <= Int(("e" as Unicode.Scalar).value))
        }
    }

    func testRandomThrowsOnEmptyString() {
        let str = runtimeMakeStringRaw("")
        var thrown = 0
        _ = kk_string_random(str, &thrown)
        XCTAssertNotEqual(thrown, 0, "random() on empty string should throw")
    }

    func testRandomNilOutThrownDoesNotCrashOnEmpty() {
        let str = runtimeMakeStringRaw("")
        _ = kk_string_random(str, nil)
    }

    // MARK: - kk_string_random_random (seeded random)
    //
    // KSP-466: kk_random_create_seeded no longer exists — Random(seed) now
    // constructs a real compiled Kotlin object (Sources/CompilerCore/Stdlib/
    // kotlin/random/Random.kt), which Swift-level test code cannot fabricate
    // directly the way the old SeededRandomBox could. String.random(random)'s
    // own Kotlin migration is separate, later work (not KSP-466's scope); its
    // seeded-determinism behavior is covered end-to-end at the Codegen
    // integration layer (compiling and running real `"str".random(Random(seed))`
    // Kotlin, e.g. Tests/CompilerBackendTests/Codegen/
    // CodegenBackendIntegrationTests+RangeRandomEdgeCases.swift for the
    // analogous Range.random(random) case) rather than by poking at Swift
    // runtime internals here.

    func testRandomWithDefaultReceiverUsesSystemRandom() {
        let str = runtimeMakeStringRaw("abcdef")
        var thrown = 0
        let result = kk_string_random_random(str, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        let ch = kk_unbox_char(result)
        let validChars = "abcdef".unicodeScalars.map { Int($0.value) }
        XCTAssertTrue(validChars.contains(ch))
    }
}
