#if canImport(Testing)
import Foundation
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
    func testSecureRandomSetSeedKeepsOutputNonDeterministic() {
        // setSeed must only supplement entropy (java.security semantics): two
        // instances seeded identically still draw from the CSPRNG, so equal
        // output would mean a deterministic stream replaced it (KUU-790).
        let a = __kk_secure_random_get_instance()
        let b = __kk_secure_random_get_instance()
        _ = __kk_secure_random_set_seed(a, 12345)
        _ = __kk_secure_random_set_seed(b, 12345)

        let first = runtimeArrayInts(__kk_secure_random_generate_seed(a, 32))
        let second = runtimeArrayInts(__kk_secure_random_generate_seed(b, 32))

        #expect(first != second)
    }

    @Test
    func testSecureRandomBoxDoesNotWireUpDeterministicPRNG() throws {
        // Structural lint: the SecureRandomBox class body in
        // Sources/Runtime/RuntimeRandom.swift must not store or invoke the
        // deterministic xorshift64* SeededRandomBox. Reintroducing it would
        // let setSeed swap the CSPRNG for a reproducible stream (KUU-790).
        let thisFile = URL(fileURLWithPath: #filePath)
        let runtimeRandomURL = thisFile
            .deletingLastPathComponent()  // RuntimeTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/Runtime/RuntimeRandom.swift")
        let source = try String(contentsOf: runtimeRandomURL, encoding: .utf8)

        let classDecl = try #require(
            source.range(of: "final class SecureRandomBox"),
            "SecureRandomBox declaration not found — the runtime layout changed and this lint needs updating"
        )
        let rest = source[classDecl.lowerBound...]
        // The class is declared at top level, so its body ends at the first
        // closing brace at the start of a line.
        let bodyEnd = rest.range(of: "\n}")?.lowerBound ?? rest.endIndex
        let classBody = rest[..<bodyEnd]

        #expect(
            !classBody.contains("Seeded" + "RandomBox"),
            "SecureRandomBox must not reference the deterministic SeededRandomBox"
        )
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
