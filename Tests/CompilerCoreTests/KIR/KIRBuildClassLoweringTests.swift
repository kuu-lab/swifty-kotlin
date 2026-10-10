#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct KIRBuildClassLoweringTests {
    @Test func testDelegatedGetterPreservesAccessorOnlyRuntimeBridge() throws {
        let ctx = makeContextFromSource("""
        interface View { val size: Int get() = 0 }
        class Wrapped(delegate: View) : View by delegate
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookup(fqName: ["View", "size"].map(ctx.interner.intern)))
        let getter = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: property)
        sema.symbols.setExternalLinkName("__kk_list_size", for: getter)
        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let wrapped = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Wrapped")]))
        let forwardingProperty = try #require(sema.symbols.classDelegationForwardingPropertySymbols(forClass: wrapped).first)
        let forwardingGetter = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: forwardingProperty)
        let function = try #require(findAllKIRFunctions(in: module).first { $0.symbol == forwardingGetter })
        #expect(kirCalls(in: function.body).contains { $0.symbol == getter }, "\(function.body)")
    }

    @Test func testNestedGenericOverrideMatchingPreservesUnrelatedOverloads() throws {
        let ctx = makeContextFromSource("""
        class Box<T>
        interface Input {
            fun <T> evaluate(value: Box<Box<T>>): Int = 1
        }
        class OverrideInput : Input {
            fun evaluate(value: String): Int = 2
            override fun <E> evaluate(value: Box<Box<E>>): Int = 3
        }
        class DefaultInput : Input {
            fun evaluate(value: String): Int = 4
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let method = ctx.interner.intern("evaluate")
        let input = ctx.interner.intern("Input")
        let interfaceMethod = try #require(sema.symbols.lookup(fqName: [input, method]))
        let overrideInput = ctx.interner.intern("OverrideInput")
        let overrideClass = try #require(sema.symbols.lookup(fqName: [overrideInput]))
        let overrideMethod = try #require(sema.symbols.lookupAll(fqName: [overrideInput, method]).first {
            sema.symbols.symbol($0)?.flags.contains(.overrideMember) == true
        })
        let defaultClass = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("DefaultInput")]))

        #expect(kirFindOverrideMethod(for: interfaceMethod, in: overrideClass, sema: sema, interner: ctx.interner) == overrideMethod)
        #expect(kirFindOverrideMethod(for: interfaceMethod, in: defaultClass, sema: sema, interner: ctx.interner) == interfaceMethod)
    }

    @Test func testObjectDelegatedPropertyAccessUsesSynthesizedAccessors() throws {
        let ctx = makeContextFromSource("""
        interface Parent { var value: Int }
        class Impl : Parent { override var value: Int = 7 }
        object Delegated : Parent by Impl() {
            fun localRead(): Int = value
            fun localWrite(newValue: Int) { value = newValue }
        }
        class Outer {
            object Nested : Parent by Impl()
            companion object : Parent by Impl()
        }
        fun main() {
            println(Delegated.value)
            println(Outer.Nested.value)
            println(Outer.value)
            Delegated.value = 8
            Outer.Nested.value = 9
            Outer.value = 10
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let main = try findKIRFunction(named: "main", in: module, interner: ctx.interner)
        let forwardingProperties = sema.symbols.allSymbols().filter {
            sema.symbols.classDelegationForwardingPropertyInfo(for: $0.id) != nil
        }
        let getterSymbols = Set(forwardingProperties.map {
            SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: $0.id)
        })
        let setterSymbols = Set(forwardingProperties.map {
            SyntheticSymbolScheme.propertySetterAccessorSymbol(for: $0.id)
        })
        let getters = kirCalls(in: main.body).compactMap(\.symbol).filter { getterSymbols.contains($0) }
        #expect(getters.count == 3, "Body: \(main.body)")
        let setters = kirCalls(in: main.body).compactMap(\.symbol).filter { setterSymbols.contains($0) }
        #expect(setters.count == 3)
        #expect(main.body.allSatisfy { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return true }
            return !forwardingProperties.contains { $0.name == callee }
        }, "Body: \(main.body)")
        #expect((getters + setters).allSatisfy { accessor in
            findAllKIRFunctions(in: module).contains { $0.symbol == accessor }
        })
        #expect(!forwardingProperties.isEmpty)
        let companionInitializer = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name).hasPrefix("__companion_init_")
        })
        #expect(!kirCalls(to: .registerITableMethod, in: companionInitializer.body, interner: ctx.interner).isEmpty)
        for (functionName, accessorName) in [("localRead", "get"), ("localWrite", "set")] {
            let function = try findKIRFunction(named: functionName, in: module, interner: ctx.interner)
            let accessors = accessorName == "get" ? getterSymbols : setterSymbols
            #expect(kirCalls(in: function.body).contains {
                $0.symbol.map { accessors.contains($0) } == true
            })
        }
    }

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

    @Test func testCompanionInitializerRegistersInterfaceMethods() throws {
        let ctx = makeContextFromSource("""
        interface Factory<T> { fun create(): T }
        class Widget {
            companion object : Factory<Widget> {
                override fun create(): Widget = Widget()
            }
        }
        fun main() { val factory: Factory<Widget> = Widget; factory.create() }
        """)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let initializer = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name).hasPrefix("__companion_init_")
        })
        #expect(!kirCalls(to: .registerITableInterface, in: initializer.body, interner: ctx.interner).isEmpty)
        #expect(!kirCalls(to: .registerITableMethod, in: initializer.body, interner: ctx.interner).isEmpty)
        #expect(!ctx.diagnostics.hasError)
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
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction,
                      let symbol,
                      sema.symbols.symbol(symbol)?.kind == .constructor,
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
        #expect(!kirCalls(to: .objectNew, in: initializer.body, interner: ctx.interner).isEmpty)
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
            return function.name == ctx.interner.intern("Child") ? function : nil
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
            return function.name == ctx.interner.intern("Owner") ? function : nil
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
            !kirCalls(to: .arrayGet, in: $0.body, interner: ctx.interner).isEmpty
        }

        #expect(forwardingFunctions.count == 1, "Expected one delegation forwarder with no dispatch target match")

        let forwardingBody = forwardingFunctions[0].body
        #expect(kirCalls(to: .abortUnreachable, in: forwardingBody, interner: ctx.interner).isEmpty)
        #expect(forwardingBody.contains { instruction in
            guard case let .virtualCall(_, callee, _, arguments, _, _, _, dispatch) = instruction,
                  case .itableDynamic = dispatch
            else { return false }
            return ctx.interner.resolve(callee) == "send" && arguments.count == 1
        }, "A downstream implementation must remain callable without a compile-time dispatch target.")
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

        let sema = try #require(ctx.sema)
        let box = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Box")]))
        let forwarderSymbol = try #require(sema.symbols.classDelegationForwardingMethodSymbols(forClass: box).first)
        let forwarderFunction = findAllKIRFunctions(in: module).first { $0.symbol == forwarderSymbol }

        let forwardingBody = try #require(
            forwarderFunction,
            "Expected delegation forwarder for ComparableInput.evaluate()"
        ).body
        #expect(!kirCalls(to: .objectTypeID, in: forwardingBody, interner: ctx.interner).isEmpty)

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
                    || ctx.sema?.symbols.classDelegationForwardingMethodInfo(for: symbol) != nil
            },
            "Expected delegation dispatch targets to be source implementations or registered forwarders, got: \(delegateCallSymbols)"
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
                && $0.name == ctx.interner.intern("evaluate")
        }
        let override = try #require(declaredMembers.first { $0.flags.contains(.overrideMember) })
        let overload = try #require(declaredMembers.first { !$0.flags.contains(.overrideMember) })
        let targets = delegationTargetSymbols(in: forwarder.body, interner: ctx.interner)

        #expect(targets.contains(override.id))
        #expect(!targets.contains(overload.id))
        try assertDelegationTargetsUseStoredDelegate(in: forwarder.body, interner: ctx.interner)
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
        let inputSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Input")]))
        let declaredProperties = sema.bindings.declSymbols.values.filter {
            guard sema.bindings.isObjectLiteralPropertySymbol($0),
                  let owner = sema.symbols.parentSymbol(for: $0)
            else {
                return false
            }
            return sema.symbols.directSupertypes(for: owner).contains(inputSymbol)
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
                try assertDelegationTargetsUseStoredDelegate(in: forwarder.body, interner: ctx.interner)
            }
        }
    }

    @Test(arguments: [false, true])
    func testInheritedGenericMethodMatchesNestedProjectedTypeParameters(covariant: Bool) throws {
        let source = """
        class Payload<\(covariant ? "out " : "")K, V>
        interface Sink<K, V> {
            fun accept(payload: Payload<out K, V>)
        }
        open class BaseSink<K, V> : Sink<K, V> {
            override fun accept(payload: Payload<\(covariant ? "" : "out ")K, V>) {}
        }
        class StringSink : BaseSink<String, Int>()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interfaceMethod = try #require(sema.symbols.lookup(
            fqName: ["Sink", "accept"].map(ctx.interner.intern)
        ))
        let inheritedMethod = try #require(sema.symbols.lookup(
            fqName: ["BaseSink", "accept"].map(ctx.interner.intern)
        ))
        let nominalSymbol = try #require(sema.symbols.lookup(
            fqName: [ctx.interner.intern("StringSink")]
        ))
        #expect(kirFindOverrideMethod(
            for: interfaceMethod,
            in: nominalSymbol,
            sema: sema,
            interner: ctx.interner
        ) == inheritedMethod)
    }

    @Test func testIncompatibleNestedGenericArgumentsDoNotMatch() throws {
        let source = """
        class Payload<T>
        interface Sink {
            fun accept(payload: Payload<String>)
        }
        class IntSink {
            fun accept(payload: Payload<Int>) {}
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interfaceMethod = try #require(sema.symbols.lookup(
            fqName: ["Sink", "accept"].map(ctx.interner.intern)
        ))
        let nominalSymbol = try #require(sema.symbols.lookup(
            fqName: [ctx.interner.intern("IntSink")]
        ))
        #expect(kirFindOverrideMethod(
            for: interfaceMethod,
            in: nominalSymbol,
            sema: sema,
            interner: ctx.interner
        ) == nil)
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

        let readMap = try findKIRFunction(named: "readMap", in: module, interner: ctx.interner)
        #expect(!kirCalls(to: .mapIsEmpty, in: readMap.body, interner: ctx.interner).isEmpty)
        #expect(!kirCalls(to: .mapGet, in: readMap.body, interner: ctx.interner).isEmpty)
        #expect(!kirCalls(to: .mapKeys, in: readMap.body, interner: ctx.interner).isEmpty)

        let main = try findKIRFunction(named: "main", in: module, interner: ctx.interner)
        #expect(extractCallees(from: main.body, interner: ctx.interner).contains("get"))
    }

    private func assertDelegationTargetsUseStoredDelegate(
        in body: [KIRInstruction],
        interner: StringInterner
    ) throws {
        let delegate = try #require(
            kirCalls(to: .arrayGet, in: body, interner: interner).compactMap(\.result).first
        )
        let targets = Set(delegationTargetSymbols(in: body, interner: interner))
        #expect(!targets.isEmpty)
        // Wrappers may delegate to another instance of their own class. Such
        // calls must receive the stored delegate rather than recurse on `this`.
        for call in kirCalls(in: body) {
            guard let symbol = call.symbol, targets.contains(symbol)
            else { continue }
            #expect(call.arguments.first == delegate)
        }
    }

    private func delegationTargetSymbols(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [SymbolID] {
        let runtimeTargets = Set([KIRRuntimeFunction.arrayGet, .objectTypeID, .abortUnreachable].map {
            $0.name(in: interner)
        })
        return kirCalls(in: body).filter { !runtimeTargets.contains($0.callee) }.compactMap(\.symbol)
    }
}
#endif
