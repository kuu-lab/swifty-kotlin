@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ParserStarConsumeInferenceTests {
    private func fixture() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Scripts/diff_cases/parser_star_consume_two_stage_map.kt"),
            encoding: .utf8
        )
    }

    private func context(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(("fun println(value: Any?) {}\n" + source).utf8))
        try runSema(ctx)
        return ctx
    }

    @Test
    func twoStageMapAcceptsStarProjectedParser() throws {
        let ctx = try context(fixture())
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        let emptyLambdas = allExprIDs(in: ast, path: path, ctx: ctx) { _, expression in
            if case let .lambdaLiteral(_, body, _, _) = expression,
               case let .blockExpr(statements, trailing, _) = ast.arena.expr(body) {
                return statements.isEmpty && trailing == nil
            }
            return false
        }
        #expect(emptyLambdas.count == 1)
        for expression in emptyLambdas {
            let type = try #require(sema.bindings.exprType(for: expression))
            guard case let .functionType(function) = sema.types.kind(of: type) else {
                Issue.record("Expected a function type for the consume lambda")
                continue
            }
            #expect(function.params == [sema.types.nullableAnyType])
            #expect(function.returnType == sema.types.unitType)
        }
    }

    @Test(arguments: ["{ _: Any? -> }", "{ it -> val ignored: Any? = it }"])
    func nullableStarInputIsAccepted(lambda: String) throws {
        let source = try fixture().replacingOccurrences(of: "map { }", with: "map \(lambda)")
        let ctx = try context(source)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nonNullableStarInputIsRejected() throws {
        let source = try fixture().replacingOccurrences(of: "map { }", with: "map { _: Any -> }")
        let ctx = try context(source)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }
}
