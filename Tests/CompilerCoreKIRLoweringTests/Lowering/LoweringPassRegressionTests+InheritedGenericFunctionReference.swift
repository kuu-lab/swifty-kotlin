#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    @Test
    func testInheritedGenericFunctionReferenceTagsSubstitutedReturnType() throws {
        let source = """
        interface H<T> { fun foo(x: T, y: Int): T? }
        interface A : H<A>
        interface B<U> : H<U>

        fun main() {
            println(A::foo.returnType.toString())
            println(H<A>::foo.returnType.toString())
            println(B<Int>::foo.returnType.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InheritedGenericFuncRef",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "inherited generic function reference should lower: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let taggedReturnTypes = findAllKIRFunctions(in: module).flatMap { function in
                function.body.flatMap { instruction -> [String] in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction",
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
            #expect(taggedReturnTypes.contains("A?"), "A::foo must tag the substituted return type")
            #expect(taggedReturnTypes.contains("T?"), "H<A>::foo must keep the declared return type")
            #expect(taggedReturnTypes.contains("U?"), "B<Int>::foo must keep the declared return type")
        }
    }

    @Test
    func testInheritedGenericFunctionReferenceParameterMetadataUsesMemberScope() throws {
        let source = """
        interface H<T> { fun foo(x: T, y: Int): T? }
        interface A : H<A>
        interface B<U> : H<U>

        fun main() {
            println(A::foo.parameters[0].type.toString())
            println(A::foo.parameters[2].type.toString())
            println(H<A>::foo.parameters[0].type.toString())
            println(H<A>::foo.parameters[1].type.toString())
            println(B<Int>::foo.parameters[0].type.toString())
            println(B<Int>::foo.parameters[1].type.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InheritedGenericFuncRefParams",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "inherited generic function reference should lower: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let parameterTypeNames = findAllKIRFunctions(in: module).flatMap { function in
                function.body.flatMap { instruction -> [String] in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "__kk_kparameter_create_typed",
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
            #expect(parameterTypeNames.contains("A"), "A::foo instance parameter must be A")
            #expect(parameterTypeNames.contains("H<T>"), "H<A>::foo instance parameter must be H<T>")
            #expect(parameterTypeNames.contains("B<U>"), "B<Int>::foo instance parameter must be B<U>")
            #expect(parameterTypeNames.contains("T"), "H<A>::foo value parameter must keep T")
            #expect(parameterTypeNames.contains("U"), "B<Int>::foo value parameter must keep U")
            #expect(
                parameterTypeNames.contains("kotlin.Int"),
                "declared Int value parameter renders the qualified JVM name"
            )
        }
    }
}
#endif
