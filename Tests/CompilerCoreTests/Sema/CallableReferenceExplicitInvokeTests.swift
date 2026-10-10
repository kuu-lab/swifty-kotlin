import Foundation
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct CallableReferenceExplicitInvokeTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test(arguments: [false, true])
    func referencesKeepCallableSignaturesAndReflectionMembers(fromSource: Bool) throws {
        let source = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/callable_reference_explicit_invoke.kt"), encoding: .utf8)
        let context = try frontend([source], fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let invoke = context.interner.intern("invoke")
        let calls = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: context) else { return nil }
            let callee: InternedString
            switch expr {
            case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _):
                callee = name
            default:
                return nil
            }
            guard callee == invoke else { return nil }
            return id
        }
        // Includes nominal Operator.invoke, which must keep ordinary dispatch.
        let bound = calls.compactMap { sema.bindings.callableValueCalls[$0] }
        #expect(calls.count == 25)
        #expect(bound.count == 24)
        #expect(bound.allSatisfy { binding in
            if case .functionType = sema.types.kind(of: binding.functionType) { return true }
            return false
        })
    }

    @Test(arguments: [false, true])
    func invalidCallsReportTheirOwnArgumentsAndNullableReceiver(fromSource: Bool) throws {
        let bodies: [(String, String)] = [
            ("val r = ::add; r.invoke(1)", "KSWIFTK-SEMA-0002"),
            ("val r = ::add; r.invoke(1, 2, 3)", "KSWIFTK-SEMA-0002"),
            ("val r = ::add; r.invoke(\"bad\", 2)", "KSWIFTK-TYPE-0001"),
            ("val r = ::add; val result: String = r.invoke(1, 2)", "KSWIFTK-TYPE-0001"),
            ("val r = ::add; r.invoke(a = 1, b = 2)", "KSWIFTK-SEMA-0002"),
            ("val r = ::add; r.invoke(*intArrayOf(1, 2))", "KSWIFTK-SEMA-0002"),
            ("val r: ((Int, Int) -> Int)? = null; r.invoke(1, 2)", "KSWIFTK-SEMA-0024"),
            ("val r = if (true) ::add else null; r.invoke(1, 2)", "KSWIFTK-SEMA-0024"),
            ("val r = Int::bump; r.invoke(1)", "KSWIFTK-SEMA-0002"),
            ("val r = ::asByte; r.invoke(128)", "KSWIFTK-TYPE-0001"),
        ]
        let context = try frontend(bodies.enumerated().map { index, body in
            """
            package probe\(index)
            fun add(a: Int, b: Int): Int = a + b
            fun Int.bump(value: Int): Int = this + value
            fun asByte(value: Byte): Int = value.toInt()
            fun bad() { \(body.0) }
            """
        }, fromSource: fromSource)
        for (index, body) in bodies.enumerated() {
            let file = try #require(context.sourceManager.fileID(forPath: "/tmp/callable-reference-invoke-\(index).kt"))
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == body.1 && $0.primaryRange?.start.file == file
            }, "\(body.0): \(context.diagnostics.diagnostics)")
        }
    }

    private func frontend(_ sources: [String], fromSource: Bool) throws -> CompilationContext {
        let paths = sources.indices.map { "/tmp/callable-reference-invoke-\($0).kt" }
        let stdlib: String?
        if fromSource {
            stdlib = nil
        } else {
            TestStdlibCache.shared.prepare()
            stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        return CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "CallableReferenceInvoke", inputs: paths, outputPath: "/tmp/callable-reference-invoke", emit: .kirDump,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: Dictionary(uniqueKeysWithValues: zip(paths, sources.map { Data($0.utf8) }))).context
    }
}
