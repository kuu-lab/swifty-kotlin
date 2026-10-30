#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericUnsignedUpperBoundLiteralInferenceTests {
    private func sourceFixture(_ relativePath: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    private func calls(named names: Set<String>, ast: ASTModule, ctx: CompilationContext) -> [(String, ExprID)] {
        ast.arena.exprs.enumerated().compactMap { index, expression in
            guard case let .call(callee, _, _, _) = expression,
                  case let .nameRef(name, _) = ast.arena.expr(callee)
            else { return nil }
            let resolvedName = ctx.interner.resolve(name)
            guard names.contains(resolvedName) else { return nil }
            return (resolvedName, ExprID(rawValue: Int32(index)))
        }
    }

    @Test
    func unsignedLiteralUsesTheOnlyUnsignedPrimitiveUpperBound() throws {
        let source = try sourceFixture("Scripts/diff_cases/kuu_2462_generic_unsigned_upper_bound.kt")
        try #require(FileFingerprint.sha256Hex(source)
                     == "91bd8253f13b8b93a4d5381922365f54896a17571566318075bd9dc72db412d0")
        try withTemporaryFile(contents: String(decoding: source, as: UTF8.self)) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let resolvedCalls = calls(named: ["asUByte", "asUShort"], ast: ast, ctx: ctx)
            #expect(resolvedCalls.map(\.0) == ["asUByte", "asUShort"])
            for ((name, call), expectedType) in zip(
                resolvedCalls,
                [sema.types.ubyteType, sema.types.ushortType]
            ) {
                let binding = try #require(sema.bindings.callBinding(for: call), "Missing binding for \(name)")
                #expect(binding.substitutedTypeArguments == [expectedType])
                guard case let .call(_, _, arguments, _) = ast.arena.expr(call),
                      let argument = arguments.first
                else {
                    Issue.record("Expected one literal argument for \(name)")
                    continue
                }
                #expect(sema.bindings.exprType(for: argument.expr) == expectedType)
            }
        }
    }

    @Test
    func existingUnsignedLiteralContextsRemainValid() throws {
        let source = try sourceFixture(
            "Scripts/diff_cases/kuu_2462_generic_unsigned_upper_bound_positive_controls.kt"
        )
        try #require(FileFingerprint.sha256Hex(source)
                     == "0870ba6d01a612bbc1e0d1006ff65199d4f55d8705b9feac5b825641b90700bd")
        try withTemporaryFile(contents: String(decoding: source, as: UTF8.self)) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let names = ["explicitUByte", "explicitUShort", "inferredUInt", "concreteUByte"]
            let resolvedCalls = calls(named: Set(names), ast: ast, ctx: ctx)
            #expect(resolvedCalls.map(\.0) == names)
            let expectedTypes: [TypeID?] = [
                sema.types.ubyteType, sema.types.ushortType, sema.types.uintType, nil
            ]
            for ((name, call), expectedType) in zip(resolvedCalls, expectedTypes) {
                let binding = try #require(sema.bindings.callBinding(for: call), "Missing binding for \(name)")
                if let expectedType {
                    #expect(binding.substitutedTypeArguments == [expectedType])
                } else {
                    #expect(binding.substitutedTypeArguments.isEmpty)
                }
                guard case let .call(_, _, arguments, _) = ast.arena.expr(call),
                      let argument = arguments.first
                else {
                    Issue.record("Expected one literal argument for \(name)")
                    continue
                }
                let expectedArgumentType: TypeID = switch name {
                case "explicitUByte", "concreteUByte": sema.types.ubyteType
                case "explicitUShort": sema.types.ushortType
                default: sema.types.uintType
                }
                #expect(sema.bindings.exprType(for: argument.expr) == expectedArgumentType)
            }
        }
    }

    @Test
    func typedUIntAndOutOfRangeLiteralsRemainRejected() throws {
        let source = """
        fun <T : UByte> asUByte(value: T): String = "OK"
        fun <T : UShort> asUShort(value: T): String = "OK"

        fun wrongTypedValue(): String {
            val raw: UInt = 1u
            return asUByte(raw)
        }

        fun wrongUByteRange(): String = asUByte(256u)
        fun wrongUShortRange(): String = asUShort(65536u)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 3, "\(errors)")
        }
    }
}
#endif
