#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ImplicitIntegerCoercionTests {
    private func calls(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.enumerated().compactMap { index, expression in
            guard case let .call(callee, _, _, _) = expression,
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee),
                  interner.resolve(calleeName) == name
            else {
                return nil
            }
            return ExprID(rawValue: Int32(index))
        }
    }

    @Test
    func annotatedIntegerConstantsAndLiteralsCoerceToUnsignedParameters() throws {
        let sources = [
            """
            package kotlin.internal
            annotation class ImplicitIntegerCoercion
            """,
            """
            import kotlin.internal.ImplicitIntegerCoercion

            @ImplicitIntegerCoercion const val IMPLICIT_INT = 255
            @ImplicitIntegerCoercion const val EXPLICIT_INT: Int = 255
            @ImplicitIntegerCoercion const val IMPLICIT_LONG = 255L
            @ImplicitIntegerCoercion const val IMPLICIT_UINT = 42u
            @ImplicitIntegerCoercion const val BIGGER_THAN_UBYTE = 256

            fun takeUByte(@ImplicitIntegerCoercion value: UByte) {}
            fun takeUShort(@ImplicitIntegerCoercion value: UShort) {}
            fun takeUInt(@ImplicitIntegerCoercion value: UInt) {}
            fun takeULong(@ImplicitIntegerCoercion value: ULong) {}
            fun takeUBytes(@ImplicitIntegerCoercion vararg values: UByte) {}

            fun main() {
                takeUByte(IMPLICIT_INT)
                takeUByte(EXPLICIT_INT)
                takeUByte(255)
                takeUShort(BIGGER_THAN_UBYTE)
                takeUInt(IMPLICIT_INT)
                takeULong(IMPLICIT_INT)
                takeULong(IMPLICIT_LONG)
                takeUBytes(IMPLICIT_INT, EXPLICIT_INT, 42u)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                frontendFlags: ["+ImplicitSignedToUnsignedIntegerConversion"],
                includeStdlib: false
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected annotated integer coercions to resolve: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let expectedTypes: [(name: String, type: TypeID, count: Int)] = [
                ("takeUByte", sema.types.ubyteType, 3),
                ("takeUShort", sema.types.ushortType, 1),
                ("takeUInt", sema.types.uintType, 1),
                ("takeULong", sema.types.ulongType, 2),
                ("takeUBytes", sema.types.ubyteType, 1),
            ]
            for expected in expectedTypes {
                let callIDs = calls(named: expected.name, in: ast, interner: ctx.interner)
                #expect(callIDs.count == expected.count)
                for callID in callIDs {
                    guard case let .call(_, _, arguments, _) = ast.arena.expr(callID),
                          let chosen = sema.bindings.callBinding(for: callID)?.chosenCallee,
                          let signature = sema.symbols.functionSignature(for: chosen)
                    else {
                        Issue.record("Expected \(expected.name) to bind to its annotated function")
                        continue
                    }
                    #expect(signature.parameterTypes.first == expected.type)
                    for argument in arguments {
                        #expect(sema.bindings.exprType(for: argument.expr) == expected.type)
                    }
                    if expected.name == "takeUInt", let argument = arguments.first {
                        guard case .uintLiteral(255)? = sema.bindings.constExprValue(for: argument.expr) else {
                            Issue.record("Expected an unsigned KIR literal for the coerced UInt constant")
                            continue
                        }
                    }
                    if expected.name == "takeULong", let argument = arguments.first,
                       case .ulongLiteral(255)? = sema.bindings.constExprValue(for: argument.expr)
                    {
                        continue
                    } else if expected.name == "takeULong", arguments.first != nil {
                        Issue.record("Expected an unsigned KIR literal for the coerced ULong constant")
                    }
                }
            }

            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            for (name, expectedValue, expectedType) in [
                ("takeUInt", KIRExprKind.uintLiteral(255), sema.types.uintType),
                ("takeULong", KIRExprKind.ulongLiteral(255), sema.types.ulongType),
            ] {
                guard let callID = calls(named: name, in: ast, interner: ctx.interner).first,
                      let callee = sema.bindings.callBinding(for: callID)?.chosenCallee,
                      let argument = mainBody.compactMap({ instruction -> KIRExprID? in
                          guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                                symbol == callee
                          else {
                              return nil
                          }
                          return arguments.first
                      }).first
                else {
                    Issue.record("Expected lowered call to \(name)")
                    continue
                }
                #expect(module.arena.expr(argument) == expectedValue)
                #expect(module.arena.exprType(argument) == expectedType)
            }
        }
    }

    @Test
    func coercionRejectsNonConstOutOfRangeAndUnannotatedArguments() throws {
        let sources = [
            """
            package kotlin.internal
            annotation class ImplicitIntegerCoercion
            """,
            """
            import kotlin.internal.ImplicitIntegerCoercion

            @ImplicitIntegerCoercion const val TOO_LARGE = 256
            @ImplicitIntegerCoercion val NOT_CONST = 7
            @ImplicitIntegerCoercion const val UNSIGNED_CONST = 42u

            fun annotated(@ImplicitIntegerCoercion value: UByte) {}
            fun unannotated(value: UByte) {}

            fun main() {
                annotated(TOO_LARGE)
                annotated(NOT_CONST)
                annotated(UNSIGNED_CONST)
                annotated(-1)
                unannotated(1)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                frontendFlags: ["+ImplicitSignedToUnsignedIntegerConversion"],
                includeStdlib: false
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 5, "Expected five rejected coercions, got: \(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0002" }, "Unexpected diagnostics: \(errors)")
        }
    }

    @Test
    func coercionRequiresLanguageFeatureOptIn() throws {
        let sources = [
            """
            package kotlin.internal
            annotation class ImplicitIntegerCoercion
            """,
            """
            import kotlin.internal.ImplicitIntegerCoercion

            @ImplicitIntegerCoercion const val VALUE = 1
            fun annotated(@ImplicitIntegerCoercion value: UByte) {}
            fun main() { annotated(VALUE) }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "Expected conversion to require its language feature: \(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0002" }, "Unexpected diagnostics: \(errors)")
        }
    }
}
#endif
