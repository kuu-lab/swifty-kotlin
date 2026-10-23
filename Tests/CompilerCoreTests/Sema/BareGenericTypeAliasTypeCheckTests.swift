@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct BareGenericTypeAliasTypeCheckTests {
    private func contextWithoutStdlib(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test
    func publicBareTypeAliasFixtureIsAccepted() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        typealias L<T> = List<T>

        fun box(): String {
            val test: Collection<Int> = listOf(1, 2, 3)
            if (test !is L) return "test !is L"
            val test2 = test as L
            if (test.toList() != test2) return "test.toList() != test2"
            return "OK"
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0062" })
    }

    @Test
    func bareTypeAliasTypeChecksUseStarProjection() throws {
        let ctx = try contextWithoutStdlib("""
        class Box<T>
        typealias BoxAlias<T> = Box<T>
        fun check(value: Any) = value is BoxAlias
        fun cast(value: Any) = value as BoxAlias
        fun direct(value: Any) = value is Box
        """)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let check = try #require(firstExprID(in: ast) { id, expr in
            isUserSourceExpr(id, in: ctx) && {
                if case .isCheck = expr { return true }
                return false
            }()
        })
        let checkTarget = try #require(sema.bindings.isCheckTargetType(for: check))
        guard case let .classType(checkClass) = sema.types.kind(of: checkTarget) else {
            Issue.record("Expected the alias to expand to a class type")
            return
        }
        #expect(checkClass.args == [.star])

        let cast = try #require(firstExprID(in: ast) { id, expr in
            isUserSourceExpr(id, in: ctx) && {
                if case .asCast = expr { return true }
                return false
            }()
        })
        let castTarget = try #require(sema.bindings.castTargetType(for: cast))
        guard case let .classType(castClass) = sema.types.kind(of: castTarget) else {
            Issue.record("Expected the alias cast to expand to a class type")
            return
        }
        #expect(castClass.args == [.star])

        let userChecks = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: ctx),
                  let expr = ast.arena.expr(id),
                  case .isCheck = expr
            else {
                return nil
            }
            return id
        }
        let directCheck = try #require(userChecks.last)
        let directTarget = try #require(sema.bindings.isCheckTargetType(for: directCheck))
        guard case let .classType(directClass) = sema.types.kind(of: directTarget) else {
            Issue.record("Expected the bare generic class to remain nominal")
            return
        }
        #expect(directClass.args.isEmpty)
    }

    @Test
    func explicitWrongAliasTypeArgumentCountStillDiagnoses() throws {
        let ctx = try contextWithoutStdlib("""
        class Box<T>
        typealias BoxAlias<T> = Box<T>
        fun invalid(value: Any) = value is BoxAlias<Int, String>
        """)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0062"
        })
    }

    @Test
    func parameterizedGenericChecksRejectErasedTypesAndAliases() throws {
        let ctx = try contextWithoutStdlib("""
        class List<T>
        typealias IntList = List<Int>
        fun invalid(value: Any) = value is List<Int>
        fun invalidAlias(value: Any) = value is IntList
        fun raw(value: Any) = value is List<*>
        fun alreadyKnown(value: List<Int>) = value is List<Int>
        """)

        let erasedTypeErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-ERASED-TYPE"
        }
        #expect(erasedTypeErrors.count == 2, "got: \(ctx.diagnostics.diagnostics)")
        #expect(erasedTypeErrors.allSatisfy { $0.message.contains("List<Int>") })
    }
}
