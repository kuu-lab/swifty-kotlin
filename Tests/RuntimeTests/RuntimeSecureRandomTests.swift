#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeSecureRandomTests {
    init() {
        kk_runtime_force_reset()
    }

    private func runtimeListInts(_ raw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            return []
        }
        return box.elements
    }

    @Test
    func testSecureRandomGenerateSeedProducesRequestedLength() {
        defer {
            kk_runtime_force_reset()
        }

        let secure = __kk_secure_random_get_instance()
        let bytes = runtimeListInts(__kk_secure_random_generate_seed(secure, 8))

        #expect(bytes.count == 8)
    }

    @Test
    func testSecureRandomSetSeedMakesOutputDeterministic() {
        defer {
            kk_runtime_force_reset()
        }

        let a = __kk_secure_random_get_instance()
        let b = __kk_secure_random_get_instance()
        _ = __kk_secure_random_set_seed(a, 12345)
        _ = __kk_secure_random_set_seed(b, 12345)

        let first = runtimeListInts(__kk_secure_random_generate_seed(a, 6))
        let second = runtimeListInts(__kk_secure_random_generate_seed(b, 6))

        #expect(first == second)
    }

    @Test
    func testSecureRandomNextBytesUsesInputLength() {
        defer {
            kk_runtime_force_reset()
        }

        let secure = __kk_secure_random_get_instance()
        let input = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: 5)))
        let output = runtimeListInts(__kk_secure_random_next_bytes(secure, input))

        #expect(output.count == 5)
    }
}
#endif
