#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// REFL-003: Tests for KFunction / KProperty type identity on callable references.
@Suite
struct CallableRefTypeIdentityTests {
    // MARK: - Sema binding tests

    @Test func testSemaBindsFunctionRefKindForCallableReference() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main() {
            val f = ::inc
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "::inc should be marked as a function reference.")
    }

    @Test func testSemaBindsPropertyRefKindForPropertyCallableReference() throws {
        let source = """
        val answer: Int = 42
        fun main() {
            val ref = ::answer
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .propertyRef, "::answer should be marked as a property reference.")
    }

    @Test func testSemaBindsFunctionRefKindForBoundCallableReference() throws {
        let source = """
        class Box {
            fun value(): Int = 42
        }
        fun main(box: Box) {
            val f = box::value
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "box::value should be marked as a function reference.")
    }

    @Test func testSemaBindsFunctionRefKindForOverloadedCallableReference() throws {
        let source = """
        fun target(x: Int): Int = x + 1
        fun target(x: String): String = x
        fun main() {
            val ref: (Int) -> Int = ::target
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let refKind = sema.bindings.callableRefKind(for: callableRefExprID)
        #expect(refKind == .functionRef, "Overloaded ::target should be marked as a function reference.")
    }

    // MARK: - KIR lowering tests

    @Test func testCallableRefKIREmissions() throws {
        let sources: [String] = [
            // KFunction tag for function callable ref
            """
            fun inc1(x: Int): Int = x + 1
            fun main1(): Int {
                val f = ::inc1
                return f(2)
            }
            """,
            // KProperty tag for property callable ref
            """
            val answerProp: Int = 42
            fun main2(): Int {
                val ref = ::answerProp
                return answerProp
            }
            """,
            // KFunction tag name and arity
            """
            fun add(a: Int, b: Int): Int = a + b
            fun main3(): Int {
                val f = ::add
                return f(1, 2)
            }
            """,
            // Bound callable ref
            """
            class Box {
                fun plus(x: Int): Int = x
            }
            fun main4(box: Box): Int {
                val f = box::plus
                return f(7)
            }
            """,
            // Non-throwing tag call
            """
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

            let module = try #require(ctx.kir)

            do {
                let mainBody = try findKIRFunctionBody(named: "main1", in: module, interner: ctx.interner)
                let callees = extractCallees(from: mainBody, interner: ctx.interner)
                #expect(
                    callees.contains("kk_callable_ref_tag_kfunction"),
                    "KIR main1 body should contain kk_callable_ref_tag_kfunction call. Callees: \(callees)"
                )
            }

            do {
                let mainBody = try findKIRFunctionBody(named: "main2", in: module, interner: ctx.interner)
                let callees = extractCallees(from: mainBody, interner: ctx.interner)
                #expect(
                    callees.contains("kk_callable_ref_tag_kproperty"),
                    "Property callable ref should be tagged as KProperty. Callees: \(callees)"
                )
                #expect(
                    !callees.contains("kk_callable_ref_tag_kfunction"),
                    "Property callable ref should NOT be tagged as KFunction."
                )
            }

            do {
                let mainBody = try findKIRFunctionBody(named: "main3", in: module, interner: ctx.interner)
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

            do {
                let mainBody = try findKIRFunctionBody(named: "main4", in: module, interner: ctx.interner)
                let callees = extractCallees(from: mainBody, interner: ctx.interner)
                #expect(
                    callees.contains("kk_callable_ref_tag_kfunction"),
                    "Bound callable ref box::plus should emit KFunction tag. Callees: \(callees)"
                )
            }

            do {
                let mainBody = try findKIRFunctionBody(named: "main5", in: module, interner: ctx.interner)
                let tagCall = mainBody.first { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_callable_ref_tag_kfunction"
                }
                guard case let .call(_, _, _, _, canThrow, _, _, _) = tagCall else {
                    Issue.record("Expected kk_callable_ref_tag_kfunction call in main5 body.")
                    return
                }
                #expect(!(canThrow), "Callable ref tagging call should be non-throwing.")
            }
        }
    }
}
#endif
