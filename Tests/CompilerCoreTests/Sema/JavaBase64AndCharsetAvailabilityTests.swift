@testable import CompilerCore
import Foundation
import Testing

@Suite
struct JavaBase64AndCharsetAvailabilityTests {
    @Test
    func jdkBase64AndCharsetSurfaceResolves() throws {
        let source = """
        import java.nio.charset.Charset
        import java.nio.charset.StandardCharsets
        import java.util.Base64
        import java.util.SortedMap

        fun probe(): String {
            val encoder: Base64.Encoder = Base64.getEncoder()
            val decoder: Base64.Decoder = Base64.getDecoder()
            val encoded = encoder.encodeToString(byteArrayOf(1))
            val decoded: ByteArray = decoder.decode(encoded)
            val utf8: Charset = StandardCharsets.UTF_8
            val available: SortedMap<String, Charset> = Charset.availableCharsets()
            return "$encoded:${decoded.size}:${utf8.name()}:${available.containsKey(\"UTF-8\")}"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected Java Base64 and charset APIs to resolve: \(errors)")
        }
    }
}
