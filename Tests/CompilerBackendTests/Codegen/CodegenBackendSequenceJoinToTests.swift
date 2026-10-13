#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceJoinToTests {

    @Test
    func testCodegenSequenceJoinToAppendsToStringBuilder() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun main() {
            val first = StringBuilder("seed:")
            sequenceOf(1, 2, 3).joinTo(first, "|", "<", ">")
            println(first.toString())

            val second = StringBuilder()
            sequenceOf("a", "b", "c").joinTo(second)
            println(second.toString())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceJoinToRuntime",
            expected:
                """
                seed:<1|2|3>
                a, b, c
                """ + "\n"
        )
    }

    @Test
    func testCodegenSequenceJoinToDoesNotUseRuntimeHelper() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun render(builder: StringBuilder): String {
            sequenceOf(1, 2, 3).joinTo(builder, "|", "<", ">", -1, "...")
            return builder.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "SequenceJoinToKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            try expectDeclaredRuntimeCalls(in: body, ctx: ctx)
            try expectSourceBackedCall("joinTo", in: ctx)
            #expect(containsKotlinCallee("joinTo", in: callees))
        }
    }
}
#endif
