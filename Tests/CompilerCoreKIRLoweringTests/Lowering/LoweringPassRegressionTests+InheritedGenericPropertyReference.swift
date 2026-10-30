#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// KUU-3813: `Type::member` reflects the member in the erased receiver class
// parameterized by its own type parameters. The callable-reference tag must
// carry the return type substituted through the supertype instantiation
// (`A : H<A>` → `A?`), while written LHS type arguments are ignored
// (`H<A>::parent` stays `T?`).
extension LoweringPassRegressionTests {
    @Test
    func testInheritedGenericPropertyReferenceTagsSubstitutedReturnType() throws {
        let source = """
        interface H<T> { val parent: T? }
        interface A : H<A>

        fun main() {
            println(A::parent.returnType.toString())
            println(H<A>::parent.returnType.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InheritedGenericPropRef",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "inherited generic property reference should lower: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let taggedReturnTypes = findAllKIRFunctions(in: module).flatMap { function in
                function.body.flatMap { instruction -> [String] in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_callable_ref_tag_kproperty",
                          arguments.count >= 3
                    else { return [] }
                    return function.body.compactMap { def in
                        guard case let .constValue(result, value) = def,
                              result == arguments[2],
                              case let .stringLiteral(name) = value
                        else { return nil }
                        return ctx.interner.resolve(name)
                    }
                }
            }
            #expect(taggedReturnTypes.contains("A?"), "A::parent must tag the substituted return type")
            #expect(taggedReturnTypes.contains("T?"), "H<A>::parent must keep the declared return type")
        }
    }
}
#endif
