@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct SealedResultWhenJoinTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        // The executable fixtures cover the bundled stdlib separately.
        let input = "fun println(value: Any?) {}\n" + source
        _ = ctx.sourceManager.addFile(path: path, contents: Data(input.utf8))
        return ctx
    }

    @Test(arguments: ["sealed_result_nothing_when_map.kt", "sealed_result_nothing_when_map_branches.kt"])
    func whenJoinPreservesGenericResultArgument(fixture: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Scripts/diff_cases/\(fixture)"), encoding: .utf8)
        let ctx = context(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        let result = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Result")]))
        let expressions = allExprIDs(in: ast, path: path, ctx: ctx) { _, expression in
            if case .whenExpr = expression { return true }
            return false
        }
        #expect(!expressions.isEmpty)
        for expression in expressions {
            let type = try #require(sema.bindings.exprType(for: expression))
            guard case let .classType(classType) = sema.types.kind(of: type),
                  classType.classSymbol == result,
                  classType.args.count == 1,
                  case let .invariant(argument) = classType.args[0],
                  case let .typeParam(parameter) = sema.types.kind(of: argument)
            else {
                Issue.record("Expected Result<R>, got \(sema.types.renderType(type))")
                continue
            }
            let symbol = try #require(sema.symbols.symbol(parameter.symbol))
            #expect(ctx.interner.resolve(symbol.name) == "R")
        }
    }

    @Test(arguments: ["invariant", "nullableNothing", "incompatibleSuccess"])
    func incompatibleResultBranchesRemainRejected(boundary: String) throws {
        let source: String
        switch boundary {
        case "invariant":
            source = """
            sealed interface Result<T> {
                data class Success<T>(val value: T) : Result<T>
                object Failure : Result<Nothing>
            }
            fun <T, R> Result<T>.map(f: (T) -> R): Result<R> = when (this) {
                Result.Failure -> Result.Failure
                is Result.Success -> Result.Success(f(value))
            }
            """
        case "nullableNothing":
            source = """
            sealed interface Result<out T> {
                data class Success<out T>(val value: T) : Result<T>
                object Failure : Result<Nothing?>
            }
            fun <T, R> Result<T>.map(f: (T) -> R): Result<R> = when (this) {
                Result.Failure -> Result.Failure
                is Result.Success -> Result.Success(f(value))
            }
            """
        default:
            source = """
            sealed interface Result<out T> {
                data class Success<out T>(val value: T) : Result<T>
                object Failure : Result<Nothing>
            }
            fun wrong(flag: Boolean): Result<Int> = when (flag) {
                true -> Result.Failure
                false -> Result.Success("wrong")
            }
            """
        }
        let ctx = context(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }
}
