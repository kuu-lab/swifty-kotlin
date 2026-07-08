@testable import Runtime
import XCTest

final class RuntimeSecureRandomTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func runtimeArrayInts(_ raw: Int) -> [Int] {
        runtimeArrayBox(from: raw)?.elements ?? []
    }

    func testSecureRandomGenerateSeedProducesRequestedLength() {
        let secure = __kk_secure_random_get_instance()
        let bytes = runtimeArrayInts(__kk_secure_random_generate_seed(secure, 8))

        XCTAssertEqual(bytes.count, 8)
    }

    func testSecureRandomSetSeedMakesOutputDeterministic() {
        let a = __kk_secure_random_get_instance()
        let b = __kk_secure_random_get_instance()
        _ = __kk_secure_random_set_seed(a, 12345)
        _ = __kk_secure_random_set_seed(b, 12345)

        let first = runtimeArrayInts(__kk_secure_random_generate_seed(a, 6))
        let second = runtimeArrayInts(__kk_secure_random_generate_seed(b, 6))

        XCTAssertEqual(first, second)
    }

    func testSecureRandomNextBytesUsesInputLength() {
        let secure = __kk_secure_random_get_instance()
        let input = registerRuntimeObject(RuntimeArrayBox(length: 5))
        let output = runtimeArrayInts(__kk_secure_random_next_bytes(secure, input))

        XCTAssertEqual(output.count, 5)
    }
}
