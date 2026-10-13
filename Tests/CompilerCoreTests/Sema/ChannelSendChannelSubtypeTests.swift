@testable import CompilerCore
import Testing

@Suite
struct ChannelSendChannelSubtypeTests {
    @Test(arguments: [true, false])
    func assignmentPreservesElementTypeAndVariance(valid: Bool) throws {
        let pairs = valid ? [
            ("Channel<Int>", "SendChannel<Int>"),
            ("Channel<Any>", "SendChannel<String>"),
            ("Channel<Int>", "SendChannel<*>"),
            ("Channel<Int>", "SendChannel<Int>?"),
            ("Channel<Int>?", "SendChannel<Int>?"),
        ] : [
            ("Channel<String>", "SendChannel<Any>"),
            ("Channel<Int>", "SendChannel<String>"),
            ("Channel<Int>?", "SendChannel<Int>"),
            ("SendChannel<Int>", "Channel<Int>"),
            ("Channel<String>", "Channel<Any>"),
        ]
        let source = "import kotlinx.coroutines.channels.*\n" + pairs.enumerated().map { index, pair in
            "fun convert\(index)(channel: \(pair.0)): \(pair.1) = channel"
        }.joined(separator: "\n")
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            if valid {
                #expect(errors.isEmpty, "\(errors)")
            } else {
                #expect(errors.count == pairs.count, "\(errors)")
                #expect(errors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" }, "\(errors)")
            }
        }
    }
}
