#if canImport(Testing)
@testable import Runtime
import Testing

// STDLIB-TEXT-FN-044: String.random() / String.random(Random)
@Suite
struct RuntimeStringRandomTests {

    // MARK: - kk_string_random (default random)

    @Test
    func testRandomReturnsCharFromSingleCharString() {
        let str = runtimeMakeStringRaw("A")
        var thrown = 0
        let result = __kk_string_random(str, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_char(result) == Int(("A" as Unicode.Scalar).value))
    }

    @Test
    func testRandomReturnsCharWithinString() {
        let str = runtimeMakeStringRaw("abcde")
        for _ in 0..<20 {
            var thrown = 0
            let result = __kk_string_random(str, &thrown)
            #expect(thrown == 0)
            let ch = kk_unbox_char(result)
            #expect(ch >= Int(("a" as Unicode.Scalar).value) && ch <= Int(("e" as Unicode.Scalar).value))
        }
    }

    @Test
    func testRandomThrowsOnEmptyString() {
        let str = runtimeMakeStringRaw("")
        var thrown = 0
        _ = __kk_string_random(str, &thrown)
        #expect(thrown != 0, "random() on empty string should throw")
    }

    @Test
    func testRandomNilOutThrownDoesNotCrashOnEmpty() {
        let str = runtimeMakeStringRaw("")
        _ = __kk_string_random(str, nil)
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

    @Test
    func testRandomWithDefaultReceiverUsesSystemRandom() {
        let str = runtimeMakeStringRaw("abcdef")
        var thrown = 0
        let result = __kk_string_random_random(str, 0, &thrown)
        #expect(thrown == 0)
        let ch = kk_unbox_char(result)
        let validChars = "abcdef".unicodeScalars.map { Int($0.value) }
        #expect(validChars.contains(ch))
    }
}
#endif
