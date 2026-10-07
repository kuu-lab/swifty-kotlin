@testable import CompilerCore
import Foundation
import Testing

/// KUU-1396: JVM-parity surface for `kotlin.io.encoding.Base64`. The issue
/// reported `decodeIntoArray`/`encodeIntoByteArray`/`paddingOption` as missing
/// members. On JVM the destination-writing members are `encodeIntoByteArray`
/// and `decodeIntoByteArray` (there is no `decodeIntoArray`), and
/// `paddingOption` exists but is `internal`, so kotlinc rejects it with
/// "cannot access ... it is internal". KSwiftK must resolve the public members
/// and keep rejecting the non-public ones instead of drifting from the JVM
/// surface in either direction.
@Suite
struct Base64MemberAvailabilityTests {
    @Test
    func encodeAndDecodeIntoMembersResolve() throws {
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun probe() {
            val src = "hello".encodeToByteArray()
            val encDst = ByteArray(16)
            val encDefault: Int = Base64.encodeIntoByteArray(src, encDst)
            val encFull: Int = Base64.encodeIntoByteArray(src, encDst, 4, 0, src.size)
            val encNamed: Int = Base64.encodeIntoByteArray(src, encDst, destinationOffset = 0)
            val decDst = ByteArray(16)
            val decDefault: Int = Base64.decodeIntoByteArray(encDst, decDst)
            val decCharSeq: Int = Base64.decodeIntoByteArray("aGVsbG8=", decDst)
            val encUrlSafe: Int = Base64.UrlSafe.encodeIntoByteArray(src, encDst)
            val decMime: Int = Base64.Mime.decodeIntoByteArray(encDst, decDst, 0, 0, encDefault)
            val decPem: Int = Base64.Pem.decodeIntoByteArray("aGVsbG8=", decDst, 1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected Base64 members to resolve: \(errors)")
        }
    }

    @Test
    func nonExistentAndInternalMembersAreRejected() throws {
        // `decodeIntoArray` does not exist on JVM (unresolved reference), and
        // `paddingOption` is an internal member of `kotlin.io.encoding.Base64`
        // (kotlinc: "cannot access ... it is internal"). Both must stay
        // rejected: SEMA-0024 unresolved member or SEMA-0044 internal member.
        let expressions = [
            "Base64.decodeIntoArray(ByteArray(4), ByteArray(4))",
            "Base64.decodeIntoArray(\"aGVsbG8=\", ByteArray(4))",
            "Base64.paddingOption",
            "Base64.UrlSafe.paddingOption",
        ]
        let sources = expressions.enumerated().map { index, expression in
            """
            package rejected\(index)
            import kotlin.io.encoding.Base64
            import kotlin.io.encoding.ExperimentalEncodingApi

            @OptIn(ExperimentalEncodingApi::class)
            fun probe() {
                println(\(expression))
            }
            """
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(!errors.isEmpty, "Expected rejection of \(expressions[index])")
                #expect(
                    errors.contains { $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-0044" },
                    "Expected unresolved/internal member diagnostic for \(expressions[index]), got \(errors)"
                )
            }
        }
    }
}
