@testable import Runtime
import Testing

private let isLetterB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? 1 : 0
}

private let isLetterZ: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("z").value) ? 1 : 0
}

private func withFlatStringForIndexOfLast<T>(
    _ value: String,
    _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
) -> T {
    var length = 0
    var byteCount = 0
    var hash = 0
    let data = runtimeRegisterFlatString(
        value,
        outLength: &length,
        outByteCount: &byteCount,
        outHash: &hash
    )
    let constData = data.map { UnsafePointer($0) }
    return body(constData, length, byteCount, hash)
}

@Suite(.runtimeIsolation(.all))
struct RuntimeStringIndexOfLastTests {
    @Test
    func indexOfLastReturnsLastMatchingIndex() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)

        withFlatStringForIndexOfLast("abcabc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            #expect(thrown == 0)
            #expect(result == 4)
        }
    }

    @Test
    func indexOfLastReturnsNegativeOneWhenNoMatch() {
        let predicate = unsafeBitCast(isLetterZ, to: Int.self)

        withFlatStringForIndexOfLast("abcabc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            #expect(thrown == 0)
            #expect(result == -1)
        }
    }

    @Test
    func indexOfLastReturnsNegativeOneForEmptyString() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)

        withFlatStringForIndexOfLast("") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            #expect(thrown == 0)
            #expect(result == -1)
        }
    }

    @Test
    func indexOfLastReturnsSingleCharIndexWhenOnlyOneMatch() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)

        withFlatStringForIndexOfLast("abc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            #expect(thrown == 0)
            #expect(result == 1)
        }
    }
}
