#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KIRBuildClassLoweringTests {
    @Test func testBuildKIRPhaseThrowsInvalidInputWhenASTOrSemaMissing() {
        let ctx = makeCompilationContext(inputs: [])

        do {
            try BuildKIRPhase().run(ctx)
            Issue.record("Expected invalidInput, got no error")
        } catch let error as CompilerPipelineError {
            guard case let .invalidInput(message) = error else {
                Issue.record("Expected invalidInput, got: \(error)")
                return
            }
            #expect(message.contains("Sema phase did not run"))
        } catch {
            Issue.record("Expected CompilerPipelineError, got: \(error)")
        }
    }

    @Test func testBuildKIRPhaseEmitsWarningWhenNoFunctionsAreLowered() throws {
        let ctx = makeCompilationContext(inputs: [])
        let astArena = ASTArena()
        let ast = ASTModule(
            files: [
                ASTFile(
                    fileID: FileID(rawValue: 0),
                    packageFQName: [],
                    imports: [],
                    topLevelDecls: [],
                    scriptBody: []
                ),
            ],
            arena: astArena,
            declarationCount: 0,
            tokenCount: 0
        )

        let setup = makeSemaModule()
        ctx.ast = ast
        ctx.sema = setup.ctx

        try BuildKIRPhase().run(ctx)

        let module = try #require(ctx.kir)
        #expect(module.functionCount == 0)
        assertHasDiagnostic("KSWIFTK-KIR-0001", in: ctx)
    }

    @Test func testBuildKIRClassLoweringScenarios() throws {
        let sources = [
            """
            package sample0
            fun answer0(): Int = 42
            """,
            """
            package sample1
            class Host1 {
                companion object {
                    val answer: Int = 42
                }
            }
            fun main1(): Int = Host1.answer
            """,
            """
            package sample2
            class Box2 {
                constructor(value: Int = 7)
            }
            fun main2() = Box2()
            """,
            """
            package sample3
            open class Base3(x: Int)
            class Child3 : Base3 {
                constructor() : super(1)
            }
            fun main3() = Child3()
            """,
            """
            package sample4
            class DelegateBox4 {
                operator fun provideDelegate(thisRef: Any?, property: String): DelegateBox4 = this
                operator fun getValue(thisRef: Any?, property: String): Int = 1
            }
            class Owner4 {
                val value by DelegateBox4()
            }
            fun main4(): Int = Owner4().value
            """,
            """
            package sample5
            interface EventSink5 {
                fun send(message: String): Int
            }
            class Box5(delegate: EventSink5) : EventSink5 by delegate
            fun main5(): Int = 0
            """,
            """
            package sample6
            interface ComparableInput6 {
                fun evaluate(value: Int): Int
            }
            class OverloadedSink6 : ComparableInput6 {
                fun evaluate(value: String): Int = 0
                override fun evaluate(value: Int): Int = 10
            }
            class Box6(delegate: ComparableInput6) : ComparableInput6 by delegate
            fun main6(): Int = Box6(OverloadedSink6()).evaluate(1)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let functionNames = findAllKIRFunctions(in: module).map { function in
                interner.resolve(function.name)
            }

            assertNoDiagnostic("KSWIFTK-KIR-0001", in: ctx)
            #expect(module.functionCount >= 1)

            // sample1: companion initializer
            #expect(
                functionNames.contains(where: { $0.hasPrefix("__companion_init_") }),
                "Expected synthesized companion initializer, got: \(functionNames)"
            )

            // sample2: secondary constructor default stub
            #expect(
                functionNames.contains(where: { $0.hasPrefix("Box2") }),
                "Expected lowered Box2 constructor-related functions, got: \(functionNames)"
            )

            // sample3: secondary constructor super delegation
            do {
                let childConstructors = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
                    return interner.resolve(function.name) == "Child3" ? function : nil
                }
                #expect(!childConstructors.isEmpty)
                let hasInitDelegationCall = childConstructors.contains { function in
                    function.body.contains { instruction in
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                        return interner.resolve(callee) == "<init>"
                    }
                }
                #expect(hasInitDelegationCall, "Expected <init> delegation call in Child3 constructors")
            }

            // sample4: delegated property initialization path
            do {
                let ownerConstructor = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
                    return interner.resolve(function.name) == "Owner4" ? function : nil
                }.first

                let body = try #require(ownerConstructor?.body)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("DelegateBox4"), "Expected delegate constructor call, got: \(callees)")
            }

            // sample5: delegation forwarder with no dispatch targets
            do {
                let forwardingFunctions = loweredFunctions(in: module).filter {
                    interner.resolve($0.name) == "send"
                        && hasCall(named: "kk_array_get", in: $0.body, interner: interner)
                }

                #expect(forwardingFunctions.count == 1, "Expected one delegation forwarder with no dispatch target match, got \(forwardingFunctions.count)")

                let forwardingBody = forwardingFunctions[0].body
                let callees = extractCallees(from: forwardingBody, interner: interner)
                #expect(
                    callees.contains("kk_abort_unreachable"),
                    "Expected explicit abort fallback in delegation forwarder, got: \(callees)"
                )
                let abortCallArgumentCounts = forwardingBody.compactMap { instruction -> Int? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          interner.resolve(callee) == "kk_abort_unreachable"
                    else {
                        return nil
                    }
                    return arguments.count
                }
                #expect(abortCallArgumentCounts == [1], "Expected kk_abort_unreachable to receive null outThrown.")
            }

            // sample6: delegation dispatch by exact signature
            do {
                let forwarderFunction = loweredFunctions(in: module).first {
                    interner.resolve($0.name) == "evaluate"
                        && hasCall(named: "kk_object_type_id", in: $0.body, interner: interner)
                }

                let forwardingBody = try #require(
                    forwarderFunction,
                    "Expected delegation forwarder for ComparableInput6.evaluate()"
                ).body

                let delegateCallSymbols = delegationTargetSymbols(
                    in: forwardingBody,
                    interner: interner
                )

                let nonSyntheticOverrideCalls = delegateCallSymbols.compactMap { symbol -> SymbolID? in
                    guard let signatureSymbol = ctx.sema?.symbols.symbol(symbol),
                          signatureSymbol.flags.contains(.overrideMember),
                          !signatureSymbol.flags.contains(.synthetic)
                    else {
                        return nil
                    }
                    return symbol
                }

                #expect(
                    nonSyntheticOverrideCalls.isEmpty == false,
                    "Expected delegation forwarder to call non-synthetic override target for ComparableInput6.evaluate, got: \(delegateCallSymbols)"
                )
                #expect(
                    delegateCallSymbols.allSatisfy { symbol in
                        guard let signatureSymbol = ctx.sema?.symbols.symbol(symbol) else {
                            return false
                        }
                        return !signatureSymbol.flags.contains(.synthetic)
                    },
                    "Expected delegation dispatch targets to exclude synthetic forwarding functions, got: \(delegateCallSymbols)"
                )
            }
        }
    }

    private func loweredFunctions(in module: KIRModule) -> [KIRFunction] {
        findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
            return function
        }
    }

    private func hasCall(
        named calleeName: String,
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> Bool {
        body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return interner.resolve(callee) == calleeName
        }
    }

    private func delegationTargetSymbols(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [SymbolID] {
        body.compactMap { instruction -> SymbolID? in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                  let symbol
            else {
                return nil
            }

            switch interner.resolve(callee) {
            case "kk_array_get", "kk_object_type_id", "kk_abort_unreachable":
                return nil
            default:
                return symbol
            }
        }
    }
}
#endif
