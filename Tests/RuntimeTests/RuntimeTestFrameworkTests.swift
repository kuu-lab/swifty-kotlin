#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeTestFrameworkTests {
    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func assertThrownMessage(
        _ thrown: Int,
        contains fragment: String
    ) {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) else {
            Issue.record("Expected a RuntimeThrowableBox")
            return
        }
        #expect(throwable.renderedMessage.hasPrefix("AssertionError:"))
        #expect(throwable.message.contains(fragment))
    }

    @Test
    func testAssertEqualsPassesAndFails() {
        var thrown = 0
        _ = kk_test_assertEquals(kk_box_int(1), kk_box_int(1), &thrown)
        #expect(thrown == 0)

        _ = kk_test_assertEquals(kk_box_int(1), kk_box_int(2), &thrown)
        #expect(thrown != 0)
        assertThrownMessage(thrown, contains: "Expected <1> but was <2>.")
    }

    @Test
    func testAssertEqualsHandlesStrings() {
        var thrown = 0
        let first = makeRuntimeString("hello")
        let second = makeRuntimeString("he" + "llo")
        _ = kk_test_assertEquals(first, second, &thrown)
        #expect(thrown == 0)
    }

    @Test
    func testAssertTruePassesAndFails() {
        var thrown = 0
        _ = kk_test_assertTrue(kk_box_bool(1), &thrown)
        #expect(thrown == 0)

        _ = kk_test_assertTrue(0, &thrown)
        #expect(thrown != 0)
        assertThrownMessage(thrown, contains: "Expected value to be true.")
    }

    @Test
    func testAssertTrueMessageUsesCustomText() {
        var thrown = 0
        _ = kk_test_assertTrue_message(0, makeRuntimeString("custom truth message"), &thrown)
        #expect(thrown != 0)
        assertThrownMessage(thrown, contains: "custom truth message")
    }

    @Test
    func testAssertNullPassesAndFails() {
        var thrown = 0
        _ = kk_test_assertNull(runtimeNullSentinelInt, &thrown)
        #expect(thrown == 0)

        _ = kk_test_assertNull(kk_box_int(1), &thrown)
        #expect(thrown != 0)
        assertThrownMessage(thrown, contains: "Expected value to be null")
    }

    @Test
    func testAssertNullMessageUsesCustomText() {
        var thrown = 0
        _ = kk_test_assertNull_message(kk_box_int(1), makeRuntimeString("custom null message"), &thrown)
        #expect(thrown != 0)
        assertThrownMessage(thrown, contains: "custom null message")
    }

    @Test
    func testAssertEqualsMessageUsesCustomText() {
        var thrown = 0
        _ = kk_test_assertEquals_message(
            kk_box_int(1),
            kk_box_int(2),
            makeRuntimeString("custom equality message"),
            &thrown
        )
        #expect(thrown != 0)
        assertThrownMessage(thrown, contains: "custom equality message")
    }
}
#endif
