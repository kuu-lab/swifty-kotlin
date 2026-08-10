#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// REFL-003: Tests for KFunction / KProperty type identity on callable references.
@Suite
struct CallableRefTypeIdentityTests {
    @Test func testCallableRefTypeIdentity() throws {
        let sources: [String] = [
            // 0: Sema: function reference
            """
            package sample0
            fun inc(x: Int): Int = x + 1
            fun host0() {
                val f = ::inc
            }
            """,

            // 1: Sema: property reference
            """
            package sample1
            val answer: Int = 42
            fun host1() {
                val ref = ::answer
            }
            """,

            // 2: Sema: bound callable reference
            """
            package sample2
            class Box {
                fun value(): Int = 42
            }
            fun host2(box: Box) {
                val f = box::value
            }
            """,

            // 3: Sema: overloaded callable reference
            """
            package sample3
            fun target(x: Int): Int = x + 1
            fun target(x: String): String = x
            fun host3() {
                val ref: (Int) -> Int = ::target
            }
            """,

            // 4: KIR: KFunction tag for function callable ref
            """
            package sample4
            fun inc1(x: Int): Int = x + 1
            fun main1(): Int {
                val f = ::inc1
                return f(2)
            }
            """,

            // 5: KIR: KProperty tag for property callable ref
            """
            package sample5
            val answerProp: Int = 42
            fun main2(): Int {
                val ref = ::answerProp
                return answerProp
            }
            """,

            // 6: KIR: KFunction tag name and arity
            """
            package sample6
            fun add(a: Int, b: Int): Int = a + b
            fun main3(): Int {
                val f = ::add
                return f(1, 2)
            }
            """,

            // 7: KIR: bound callable ref
            """
            package sample7
            class Box {
                fun plus(x: Int): Int = x
            }
            fun main4(box: Box): Int {
                val f = box::plus
                return f(7)
            }
            """,

            // 8: KIR: non-throwing tag call
            """
            package sample8
            fun inc5(x: Int): Int = x + 1
            fun main5(): Int {
                val f = ::inc5
                return f(2)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let interner = ctx.interner

            let sourceFileIDs = try paths.map { path in
                try #require(ctx.sourceManager.fileID(forPath: path))
            }

            // 0: function reference
            do {
                let sourceFileID = sourceFileIDs[0]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true }
                    return false
                })
                let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
                #expect(refKind == .functionRef, "::inc should be marked as a function reference.")
            }

            // 1: property reference
            do {
                let sourceFileID = sourceFileIDs[1]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true }
                    return false
                })
                let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
                #expect(refKind == .propertyRef, "::answer should be marked as a property reference.")
            }

            // 2: bound callable reference
            do {
                let sourceFileID = sourceFileIDs[2]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true }
                    return false
                })
                let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
                #expect(refKind == .functionRef, "box::value should be marked as a function reference.")
            }

            // 3: overloaded callable reference
            do {
                let sourceFileID = sourceFileIDs[3]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true }
                    return false
                })
                let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
                #expect(refKind == .functionRef, "Overloaded ::target should be marked as a function reference.")
            }

            // 4: KFunction tag
            do {
                let mainBody = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let callees = extractCallees(from: mainBody, interner: interner)
                #expect(
                    callees.contains("kk_callable_ref_tag_kfunction"),
                    "KIR main1 body should contain kk_callable_ref_tag_kfunction call. Callees: \(callees)"
                )
            }

            // 5: KProperty tag
            do {
                let mainBody = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let callees = extractCallees(from: mainBody, interner: interner)
                #expect(
                    callees.contains("kk_callable_ref_tag_kproperty"),
                    "Property callable ref should be tagged as KProperty. Callees: \(callees)"
                )
                #expect(
                    !callees.contains("kk_callable_ref_tag_kfunction"),
                    "Property callable ref should NOT be tagged as KFunction."
                )
            }

            // 6: name and arity
            do {
                let mainBody = try findKIRFunctionBody(named: "main3", in: module, interner: interner)
                let tagCall = mainBody.first { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
                }
                guard case let .call(_, _, arguments, _, _, _, _, _) = tagCall else {
                    Issue.record("Expected kk_callable_ref_tag_kfunction call in main3 body.")
                    return
                }

                #expect(arguments.count == 4)

                if let nameExpr = module.arena.expr(arguments[1]),
                   case let .stringLiteral(nameInterned) = nameExpr
                {
                    #expect(ctx.interner.resolve(nameInterned) == "add")
                } else {
                    Issue.record("Second argument to tag call should be string literal 'add'.")
                }

                if let arityExpr = module.arena.expr(arguments[2]),
                   case let .intLiteral(arityValue) = arityExpr
                {
                    #expect(arityValue == 2, "::add has arity 2 (a, b).")
                } else {
                    Issue.record("Third argument to tag call should be int literal for arity.")
                }

                if let suspendExpr = module.arena.expr(arguments[3]),
                   case let .intLiteral(isSuspendValue) = suspendExpr
                {
                    #expect(isSuspendValue == 0, "::add is not a suspend function.")
                } else {
                    Issue.record("Fourth argument to tag call should be int literal for isSuspend.")
                }
            }

            // 7: bound callable ref
            do {
                let mainBody = try findKIRFunctionBody(named: "main4", in: module, interner: interner)
                let callees = extractCallees(from: mainBody, interner: interner)
                #expect(
                    callees.contains("kk_callable_ref_tag_kfunction"),
                    "Bound callable ref box::plus should emit KFunction tag. Callees: \(callees)"
                )
            }

            // 8: non-throwing tag call
            do {
                let mainBody = try findKIRFunctionBody(named: "main5", in: module, interner: interner)
                let tagCall = mainBody.first { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
                }
                guard case let .call(_, _, _, _, canThrow, _, _, _) = tagCall else {
                    Issue.record("Expected kk_callable_ref_tag_kfunction call in main5 body.")
                    return
                }
                #expect(!canThrow, "Callable ref tagging call should be non-throwing.")
            }
        }
    }
}
#endif
