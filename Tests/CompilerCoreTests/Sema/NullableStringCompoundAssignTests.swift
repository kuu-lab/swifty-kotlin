#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

struct NullableStringCompoundAssignTests {
    @Test(arguments: ["local", "member", "indexed"], ["String?", "Any?"])
    func onlyNullableStringAcceptsArbitraryConcatenation(context: String, elementType: String) throws {
        let operation = switch context {
        case "member": "holder.value += 42"
        case "indexed": "slots[0] += 42"
        default: "var value: \(elementType) = null; value += 42; val normalized: String = value"
        }
        try withTemporaryFile(contents: """
        class Holder(var value: \(elementType))
        class Slots {
            operator fun get(index: Int): \(elementType) = null
            operator fun set(index: Int, value: \(elementType)) {}
        }
        fun test(holder: Holder, slots: Slots) { \(operation) }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == (elementType != "String?"), "\(ctx.diagnostics.diagnostics)")
            if elementType != "String?" {
                #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
            }
        }
    }

    @Test(arguments: ["String", "String?"])
    func resolvedConcatenationUsesItsDeclaredResultType(resultType: String) throws {
        let result = resultType == "String" ? "\"joined\"" : "null"
        try withTemporaryFile(contents: """
        operator fun String?.plus(other: Int): \(resultType) = \(result)
        fun test() {
            var value: String? = null
            value += 42
            val normalized: String = value
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == (resultType == "String?"), "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
