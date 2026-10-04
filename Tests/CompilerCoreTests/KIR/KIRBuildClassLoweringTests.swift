#if canImport(Testing)
@testable import CompilerCore
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

    @Test func testBuildKIRPhaseProducesModuleForValidInput() throws {
        let source = """
        fun answer(): Int = 42
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 1)
        assertNoDiagnostic("KSWIFTK-KIR-0001", in: ctx)
    }

    @Test func testClassLoweringSynthesizesCompanionInitializerFunction() throws {
        let source = """
        class Host {
            companion object {
                val answer: Int = 42
            }
        }
        fun main(): Int = Host.answer
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let functionNames = findAllKIRFunctions(in: module).map { function in
            ctx.interner.resolve(function.name)
        }

        #expect(
            functionNames.contains(where: { $0.hasPrefix("__companion_init_") }),
            "Expected synthesized companion initializer, got: \(functionNames)"
        )
    }

    @Test func testCompanionInitializerDoesNotCallSyntheticAnyConstructor() throws {
        let source = """
        class Host {
            companion object {
                val answer: Int = 42
            }
        }
        fun main(): Int = Host.answer
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let companionInitializers = findAllKIRFunctions(in: module).filter { function in
            ctx.interner.resolve(function.name).hasPrefix("__companion_init_")
        }
        #expect(!companionInitializers.isEmpty, "Expected synthesized companion initializer")

        let hasSyntheticAnyConstructorCall = companionInitializers.contains { function in
            function.body.contains { instruction in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      let symbol,
                      ctx.interner.resolve(callee) == "<init>",
                      let symbolInfo = sema.symbols.symbol(symbol)
                else {
                    return false
                }
                return symbolInfo.flags.contains(.synthetic)
                    && sema.symbols.parentSymbol(for: symbol) == sema.types.anyClassSymbol
            }
        }
        #expect(
            !hasSyntheticAnyConstructorCall,
            "Companion initializer must not call the body-less synthetic Any constructor"
        )
    }

    @Test(arguments: ["class", "interface"])
    func testStatelessCompanionHasOneSingletonAllocation(ownerKind: String) throws {
        let ctx = makeContextFromSource("""
        interface TokenKey
        \(ownerKind) Host {
            companion object Key : TokenKey
        }
        fun main(): TokenKey = Host.Key
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let host = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Host")]))
        let companion = try #require(sema.symbols.companionObjectSymbol(for: host))
        #expect(sema.symbols.nominalLayout(for: companion)?.vtableSize == 0)
        let globals = module.arena.declarations.filter {
            if case let .global(global) = $0 { return global.symbol == companion }
            return false
        }
        #expect(globals.count == 1)
        let initializers = findAllKIRFunctions(in: module).filter { function in
            function.body.contains { instruction in
                if case let .storeGlobal(_, symbol) = instruction { return symbol == companion }
                return false
            }
        }
        #expect(initializers.count == 1)
        let initializer = try #require(initializers.first)
        #expect(initializer.body.contains { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_object_new"
            }
            return false
        })
    }

    @Test func testClassLoweringGeneratesConstructorDefaultStubForSecondaryConstructor() throws {
        let source = """
        class Box {
            constructor(value: Int = 7)
        }
        fun main() = Box()
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let functionNames = findAllKIRFunctions(in: module).map { function in
            ctx.interner.resolve(function.name)
        }

        // Secondary constructor defaults should generate a default stub path.
        #expect(
            functionNames.contains(where: { $0.hasPrefix("Box") }),
            "Expected lowered Box constructor-related functions, got: \(functionNames)"
        )
    }

    @Test func testClassLoweringLowersSecondaryConstructorSuperDelegation() throws {
        let source = """
        open class Base(x: Int)
        class Child : Base {
            constructor() : super(1)
        }
        fun main() = Child()
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let childConstructors = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
            return ctx.interner.resolve(function.name) == "Child" ? function : nil
        }

        #expect(!childConstructors.isEmpty)
        let hasInitDelegationCall = childConstructors.contains { function in
            extractCallees(from: function.body, interner: ctx.interner).contains("<init>")
        }
        #expect(hasInitDelegationCall, "Expected <init> delegation call in Child constructors")
    }

    @Test func testClassLoweringLowersDelegatedPropertyInitializationPath() throws {
        let source = """
        class DelegateBox {
            operator fun provideDelegate(thisRef: Any?, property: String): DelegateBox = this
            operator fun getValue(thisRef: Any?, property: String): Int = 1
        }

        class Owner {
            val value by DelegateBox()
        }

        fun main(): Int = Owner().value
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let ownerConstructor = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
            return ctx.interner.resolve(function.name) == "Owner" ? function : nil
        }.first

        let body = try #require(ownerConstructor?.body)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("DelegateBox"), "Expected delegate constructor call, got: \(callees)")
    }

    @Test func testClassLoweringEmitsDelegationForwarderEvenWithNoDispatchTargets() throws {
        let source = """
        interface EventSink {
            fun send(message: String): Int
        }

        class Box(delegate: EventSink) : EventSink by delegate

        fun main(): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)

        let forwardingFunctions = findAllKIRFunctions(in: module).filter {
            extractCallees(from: $0.body, interner: ctx.interner).contains("kk_array_get")
        }

        #expect(forwardingFunctions.count == 1, "Expected one delegation forwarder with no dispatch target match")

        let forwardingBody = forwardingFunctions[0].body
        let callees = extractCallees(from: forwardingBody, interner: ctx.interner)
        #expect(
            callees.contains("kk_abort_unreachable"),
            "Expected explicit abort fallback in delegation forwarder, got: \(callees)"
        )
        let abortCallArgumentCounts = forwardingBody.compactMap { instruction -> Int? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_abort_unreachable"
            else {
                return nil
            }
            return arguments.count
        }
        #expect(abortCallArgumentCounts == [1], "Expected kk_abort_unreachable to receive null outThrown.")
    }

    @Test func testClassLoweringResolvesDelegationDispatchByExactSignature() throws {
        let source = """
        interface ComparableInput {
            fun evaluate(value: Int): Int
        }

        class OverloadedSink : ComparableInput {
            fun evaluate(value: String): Int = 0
            override fun evaluate(value: Int): Int = 10
        }

        class Box(delegate: ComparableInput) : ComparableInput by delegate

        fun main(): Int = Box(OverloadedSink()).evaluate(1)
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)

        let forwarderFunction = findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "evaluate"
                && extractCallees(from: $0.body, interner: ctx.interner).contains("kk_object_type_id")
        }

        let forwardingBody = try #require(
            forwarderFunction,
            "Expected delegation forwarder for ComparableInput.evaluate()"
        ).body

        let delegateCallSymbols = delegationTargetSymbols(
            in: forwardingBody,
            interner: ctx.interner
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
            "Expected delegation forwarder to call non-synthetic override target for ComparableInput.evaluate, got: \(delegateCallSymbols)"
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

    @Test(arguments: [false, true])
    func testClassDelegationDispatchIncludesAnonymousOverrides(hasDefault: Bool) throws {
        let source = """
        interface Input {
            fun evaluate(value: Int): Int \(hasDefault ? "= 1" : "")
        }
        class Box(delegate: Input) : Input by delegate
        fun main(): Int {
            val offset = 7
            val input = object : Input {
                fun evaluate(value: String): Int = 0
                override fun evaluate(value: Int): Int = offset + value
            }
            return Box(input).evaluate(2)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let boxSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Box")]))
        let forwardingSymbol = try #require(
            sema.symbols.classDelegationForwardingMethodSymbols(forClass: boxSymbol).first
        )
        let forwarder = try #require(findAllKIRFunctions(in: module).first { $0.symbol == forwardingSymbol })
        let declaredMembers = sema.bindings.declSymbols.values.compactMap { sema.symbols.symbol($0) }.filter {
            $0.kind == .function && $0.flags.contains(.synthetic)
                && ctx.interner.resolve($0.name) == "evaluate"
        }
        let override = try #require(declaredMembers.first { $0.flags.contains(.overrideMember) })
        let overload = try #require(declaredMembers.first { !$0.flags.contains(.overrideMember) })
        let targets = delegationTargetSymbols(in: forwarder.body, interner: ctx.interner)

        #expect(targets.contains(override.id))
        #expect(!targets.contains(overload.id))
        #expect(!targets.contains(forwardingSymbol))
    }

    @Test func testClassDelegationDispatchIncludesAnonymousPropertyAccessors() throws {
        let source = """
        interface Input {
            val answer: Int get() = 1
            var count: Int
        }
        class Box(delegate: Input) : Input by delegate
        fun main(): Int {
            val input = object : Input {
                override val answer: Int get() = 7
                override var count: Int = 2
            }
            val box = Box(input)
            box.count = 9
            return box.answer + box.count
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let boxSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Box")]))
        let forwardingProperties = sema.symbols.classDelegationForwardingPropertySymbols(forClass: boxSymbol)
        let declaredProperties = sema.bindings.declSymbols.values.filter {
            sema.bindings.isObjectLiteralPropertySymbol($0)
        }
        #expect(declaredProperties.count == 2)

        for property in declaredProperties {
            let propertySymbol = try #require(sema.symbols.symbol(property))
            let forwardingProperty = try #require(forwardingProperties.first {
                sema.symbols.symbol($0)?.name == propertySymbol.name
            })
            var accessorPairs = [(
                SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: forwardingProperty),
                SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: property)
            )]
            if propertySymbol.flags.contains(.mutable) {
                accessorPairs.append((
                    SyntheticSymbolScheme.propertySetterAccessorSymbol(for: forwardingProperty),
                    SyntheticSymbolScheme.propertySetterAccessorSymbol(for: property)
                ))
            }
            for (forwardingAccessor, declaredAccessor) in accessorPairs {
                let forwarder = try #require(findAllKIRFunctions(in: module).first {
                    $0.symbol == forwardingAccessor
                })
                let targets = delegationTargetSymbols(in: forwarder.body, interner: ctx.interner)
                #expect(targets.contains(declaredAccessor))
                #expect(!targets.contains(forwardingAccessor))
            }
        }
    }

    @Test func testMapInterfaceDelegationResolvesDirectMembersAndMapDispatch() throws {
        let source = """
        class CustomMap : Map<String, Int> by mapOf("k" to 1)

        fun readMap(map: Map<String, Int>): Int {
            val value = map["k"] ?: 0
            return map.keys.size + value + if (map.isEmpty()) 1 else 0
        }

        fun main(): Int {
            val m = CustomMap()
            return readMap(m) + (m["k"] ?: 0)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let classSymbol = try #require(
            sema.symbols.lookup(fqName: [ctx.interner.intern("CustomMap")])
        )

        let forwardingMethodNames = sema.symbols
            .classDelegationForwardingMethodSymbols(forClass: classSymbol)
            .compactMap { sema.symbols.symbol($0)?.name }
            .map(ctx.interner.resolve)
        #expect(forwardingMethodNames.contains("isEmpty"))
        #expect(forwardingMethodNames.contains("get"))

        let forwardingPropertyNames = sema.symbols
            .classDelegationForwardingPropertySymbols(forClass: classSymbol)
            .compactMap { sema.symbols.symbol($0)?.name }
            .map(ctx.interner.resolve)
        for propertyName in ["entries", "keys", "size", "values"] {
            #expect(forwardingPropertyNames.contains(propertyName))
        }

        let readMap = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name) == "readMap"
        })
        let readMapCallees = extractCallees(from: readMap.body, interner: ctx.interner)
        #expect(readMapCallees.contains("__kk_map_is_empty"))
        #expect(readMapCallees.contains("__kk_map_get"))
        #expect(readMapCallees.contains("__kk_map_keys"))

        let main = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name) == "main"
        })
        #expect(extractCallees(from: main.body, interner: ctx.interner).contains("get"))
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
