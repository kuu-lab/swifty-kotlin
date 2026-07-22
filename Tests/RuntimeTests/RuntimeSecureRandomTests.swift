#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeSecureRandomTests {
    private func runtimeArrayInts(_ raw: Int) -> [Int] {
        runtimeArrayBox(from: raw)?.elements ?? []
    }

    @Test
    func testSecureRandomGenerateSeedProducesRequestedLength() {
        let secure = __kk_secure_random_get_instance()
        let bytes = runtimeArrayInts(__kk_secure_random_generate_seed(secure, 8))

        #expect(bytes.count == 8)
    }

    @Test
    func testSecureRandomSetSeedMakesOutputDeterministic() {
        let a = __kk_secure_random_get_instance()
        let b = __kk_secure_random_get_instance()
        _ = __kk_secure_random_set_seed(a, 12345)
        _ = __kk_secure_random_set_seed(b, 12345)

        let first = runtimeArrayInts(__kk_secure_random_generate_seed(a, 6))
        let second = runtimeArrayInts(__kk_secure_random_generate_seed(b, 6))

        #expect(first == second)
    }

    @Test
    func testSecureRandomNextBytesUsesInputLength() {
        let secure = __kk_secure_random_get_instance()
        let input = registerRuntimeObject(RuntimeArrayBox(length: 5))
        let output = runtimeArrayInts(__kk_secure_random_next_bytes(secure, input))

        #expect(output.count == 5)
    }
}
#endif
