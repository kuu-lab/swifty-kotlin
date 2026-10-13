@testable import CompilerCore
import Foundation
import Testing

extension LoweringPassRegressionTests {
    @Test
    func testStringEncodingRangeDefaultKeepsSelectedOverload() throws {
        let source = """
        fun byIndex(text: String): ByteArray = text.encodeToByteArray(1)
        fun byCharset(text: String, charset: Charset): ByteArray = text.encodeToByteArray(charset)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let indexed = try findKIRFunction(named: "byIndex", in: module, interner: ctx.interner)
            let charset = try findKIRFunction(named: "byCharset", in: module, interner: ctx.interner)
            let indexCallees = extractCallees(from: indexed.body, interner: ctx.interner)
            let charsetCallees = extractCallees(from: charset.body, interner: ctx.interner)
            #expect(indexCallees.contains { $0.contains("encodeToByteArray") && $0.contains("$default") })
            #expect(!indexCallees.contains("__kk_string_encodeToByteArray_charset_flat"))
            #expect(charsetCallees.contains("__kk_string_encodeToByteArray_charset_flat"))
        }
    }
}
