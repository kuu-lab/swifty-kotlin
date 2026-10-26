#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testNullableIntIncDecExtensionsResolveForPrefixAndPostfix() throws {
        let source = """
        operator fun Int?.inc(): Int? = (this ?: 0) + 1
        operator fun Int?.dec(): Int? = (this ?: 0) - 1
        fun main() {
            var i: Int? = 10
            val postIncrement = i++
            val preIncrement = ++i
            val postDecrement = i--
            val preDecrement = --i
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let incrementExpressions = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let expression = ExprID(rawValue: Int32(index))
                return ast.arena.isIncrementDecrement(expression) ? expression : nil
            }
            #expect(incrementExpressions.count == 4)

            let bindings = incrementExpressions.compactMap { sema.bindings.callBindings[$0] }
            #expect(bindings.count == 4)
            let operatorNames = bindings.compactMap { binding in
                sema.symbols.symbol(binding.chosenCallee).map { ctx.interner.resolve($0.name) }
            }
            #expect(operatorNames.filter { $0 == "inc" }.count == 2)
            #expect(operatorNames.filter { $0 == "dec" }.count == 2)

            let receiverTypes = bindings.compactMap { binding in
                sema.symbols.functionSignature(for: binding.chosenCallee)?.receiverType
            }
            #expect(receiverTypes.count == 4)
            #expect(receiverTypes.allSatisfy { sema.types.nullability(of: $0) == .nullable })
        }
    }
}
#endif
