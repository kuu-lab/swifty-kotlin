#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceJoinToStringTests {
    @Test func testCodegenSequenceJoinToStringDoesNotUseRuntimeHelper() throws {
        let source = """
        fun render(): String {
            return sequenceOf(1, 2, 3).joinToString(separator = ":", prefix = "[", postfix = "]")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "SequenceJoinToStringKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            try expectDeclaredRuntimeCalls(in: body, ctx: ctx)
            try expectSourceBackedCall("joinToString", in: ctx)
            // Calls that omit defaulted parameters dispatch through the
            // bundled `joinToString$default` stub, which itself calls `joinToString`.
            #expect(containsKotlinCallee("joinToString", in: callees) || containsKotlinCallee("joinToString$default", in: callees))
        }
    }
}
#endif
