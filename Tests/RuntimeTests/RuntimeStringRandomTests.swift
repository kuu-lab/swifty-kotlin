@testable import Runtime
import XCTest

// STDLIB-TEXT-FN-044: String.random() / String.random(Random)
final class RuntimeStringRandomTests: XCTestCase {

    // MARK: - kk_string_random (default random)

    func testRandomReturnsCharFromSingleCharString() {
        let str = runtimeMakeStringRaw("A")
        var thrown = 0
        let result = __kk_string_random(str, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_char(result), Int(("A" as Unicode.Scalar).value))
    }

    func testRandomReturnsCharWithinString() {
        let str = runtimeMakeStringRaw("abcde")
        for _ in 0..<20 {
            var thrown = 0
            let result = __kk_string_random(str, &thrown)
            XCTAssertEqual(thrown, 0)
            let ch = kk_unbox_char(result)
            XCTAssertTrue(ch >= Int(("a" as Unicode.Scalar).value) && ch <= Int(("e" as Unicode.Scalar).value))
        }
    }

    func testRandomThrowsOnEmptyString() {
        let str = runtimeMakeStringRaw("")
        var thrown = 0
        _ = __kk_string_random(str, &thrown)
        XCTAssertNotEqual(thrown, 0, "random() on empty string should throw")
    }

    func testRandomNilOutThrownDoesNotCrashOnEmpty() {
        let str = runtimeMakeStringRaw("")
        _ = __kk_string_random(str, nil)
    }

    // MARK: - kk_string_random_random (seeded random)

    func testRandomWithSeededRandomIsReproducible() {
        let str = runtimeMakeStringRaw("xyz")
        let seed = kk_random_create_seeded(42)

        var thrown1 = 0
        let result1 = __kk_string_random_random(str, seed, &thrown1)
        XCTAssertEqual(thrown1, 0)

        let seed2 = kk_random_create_seeded(42)
        var thrown2 = 0
        let result2 = __kk_string_random_random(str, seed2, &thrown2)
        XCTAssertEqual(thrown2, 0)

        XCTAssertEqual(kk_unbox_char(result1), kk_unbox_char(result2),
                       "Same seed should produce same random character")
    }

    func testRandomWithSeededRandomReturnsCharFromString() {
        let str = runtimeMakeStringRaw("hello")
        let seed = kk_random_create_seeded(99)
        for _ in 0..<10 {
            var thrown = 0
            let result = __kk_string_random_random(str, seed, &thrown)
            XCTAssertEqual(thrown, 0)
            let ch = kk_unbox_char(result)
            let validChars = "hello".unicodeScalars.map { Int($0.value) }
            XCTAssertTrue(validChars.contains(ch), "Result \(ch) not in 'hello'")
        }
    }

    func testRandomWithSeededRandomThrowsOnEmptyString() {
        let str = runtimeMakeStringRaw("")
        let seed = kk_random_create_seeded(1)
        var thrown = 0
        _ = __kk_string_random_random(str, seed, &thrown)
        XCTAssertNotEqual(thrown, 0, "random(Random) on empty string should throw")
    }

    func testRandomWithDefaultReceiverUsesSystemRandom() {
        let str = runtimeMakeStringRaw("abcdef")
        var thrown = 0
        let result = __kk_string_random_random(str, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        let ch = kk_unbox_char(result)
        let validChars = "abcdef".unicodeScalars.map { Int($0.value) }
        XCTAssertTrue(validChars.contains(ch))
    }
}
