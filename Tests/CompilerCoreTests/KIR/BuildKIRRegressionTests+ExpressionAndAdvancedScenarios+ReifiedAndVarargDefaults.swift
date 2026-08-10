#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testBuildKIRAddsHiddenTypeTokenForInlineReifiedCalls() throws {
        let (ctx, pickSymbol, mainSymbol, typeParameterSymbol, intType) = makeReifiedCallFixture()

        try BuildKIRPhase().run(ctx)

        let kir = try #require(ctx.kir)
        let pickFunction = try #require(findAllKIRFunctions(in: kir).first { function in
            function.symbol == pickSymbol
        })
        let mainFunction = try #require(findAllKIRFunctions(in: kir).first { function in
            function.symbol == mainSymbol
        })

        let expectedTokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameterSymbol)
        #expect(pickFunction.params.count == 2)
        #expect(pickFunction.params.last?.symbol == expectedTokenSymbol)

        guard let callInstruction = mainFunction.body.first(where: { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else {
                return false
            }
            return symbol == pickSymbol
        }),
            case let .call(_, _, arguments, _, _, _, _, _) = callInstruction
        else {
            Issue.record("Expected main to call inline reified function.")
            return
        }
        #expect(arguments.count == 2)
        let tokenArgument = arguments[1]
        guard case let .intLiteral(tokenLiteral)? = kir.arena.expr(tokenArgument) else {
            Issue.record("Expected hidden type token argument to be lowered as int literal.")
            return
        }
        let sema = try #require(ctx.sema)
        #expect(tokenLiteral == RuntimeTypeCheckToken.encode(type: intType, sema: sema, interner: ctx.interner))
    }

    @Test func testReifiedAndVarargDefaultsKIR() throws {
        let sources = [
            """
            package sample1
            fun sum1(vararg items: Int): Int = 0
            fun main1() = sum1(1, 2, 3)
            """,
            """
            package sample2
            fun greet2(prefix: String = "Hi", vararg names: Int): Int = 0
            fun main2() = greet2("Hello", 1, 2)
            """,
            """
            package sample3
            fun noArgs3(vararg items: Int): Int = 0
            fun main3() = noArgs3()
            """,
            """
            package sample4
            fun greetUser4(name: String, greeting: String = "Hello"): String = greeting
            fun main4() = greetUser4("Alice")
            """,
            """
            package sample5
            fun add5(a: Int, b: Int = 10): Int = a + b
            fun main5() = add5(5)
            """,
            """
            package sample6
            fun compute6(x: Int, y: Int = 1, z: Int = 2): Int = x + y + z
            fun main6() = compute6(10)
            """,
            """
            package sample7
            fun ordered7(a: Int = 1, b: Int = 2, c: Int = 3): Int = a + b + c
            fun main7() = ordered7()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
                #expect(callNames.contains("kk_array_set"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main3", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
            }

            do {
                let allFunctions = findAllKIRFunctions(in: module)
                let stubNames = allFunctions.map { interner.resolve($0.name) }
                    .filter { $0.hasSuffix("$default") }
                #expect(stubNames.contains("greetUser4$default"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main5", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("add5$default"))
            }

            do {
                let stubFunction = findAllKIRFunctions(in: module).first { function in
                    interner.resolve(function.name) == "compute6$default"
                }
                #expect(stubFunction != nil)
                if let stub = stubFunction {
                    #expect(stub.params.count >= 4)
                    let stubCallees = extractCallees(from: stub.body, interner: interner)
                    #expect(stubCallees.contains("compute6"))
                }
            }

            do {
                let stubFunction = findAllKIRFunctions(in: module).first { function in
                    interner.resolve(function.name) == "ordered7$default"
                }
                #expect(stubFunction != nil)
                if let stub = stubFunction {
                    var labelOrder: [Int32] = []
                    for instruction in stub.body {
                        if case let .label(id) = instruction {
                            labelOrder.append(id)
                        }
                    }
                    for i in 1 ..< labelOrder.count {
                        #expect(labelOrder[i] > labelOrder[i - 1])
                    }
                }
            }
        }
    }
}
#endif
