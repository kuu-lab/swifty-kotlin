@testable import CompilerCore
import Testing

@Suite
struct PackedConstructorCallByLoweringTests {
    @Test(arguments: ["Int", "String", "Double"])
    func reflectionConstructorHasSeparatePackedAllocatingWrapper(element: String) throws {
        let ctx = makeContextFromSource("""
        class Packed(vararg values: \(element)) { val count = values.size }
        fun probe() { val reference: (\(element)) -> Packed = ::Packed }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let functions = findAllKIRFunctions(in: module)
        let packed = try #require(functions.first {
            ctx.interner.resolve($0.name).hasPrefix("kk_reflect_constructor_packed_")
        })
        try #require(packed.params.count == 1)
        let expectedName = element == "String" ? "kotlin.Array" : "kotlin.\(element)Array"
        #expect(className(packed.params[0].type, sema: sema, interner: ctx.interner) == expectedName)
        #expect(extractCallees(from: packed.body, interner: ctx.interner).contains("kk_object_new"))
        let scalarType = element == "Int" ? sema.types.intType
            : element == "Double" ? sema.types.doubleType : sema.types.stringType
        let ordinary = try #require(functions.first { function in
            function.symbol != packed.symbol && function.params.count == 1
                && function.params[0].type == scalarType
                && extractCallees(from: function.body, interner: ctx.interner).contains("kk_object_new")
        }, "The ordinary callable-reference wrapper must retain its scalar ABI")
        #expect(ordinary.params[0].type != packed.params[0].type)
        let invoker = try #require(functions.first { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_reflect_invoke_")
                && function.body.contains { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == packed.symbol
                }
        })
        let unpackCallees = extractCallees(from: invoker.body, interner: ctx.interner)
        #expect(!unpackCallees.contains("__kk_array_toList"))
        if element != "String" {
            #expect(!unpackCallees.contains("__kk_array_toList"))
            #expect(!unpackCallees.contains(element == "Int" ? "kk_unbox_int" : "kk_unbox_double"))
        }
    }

    @Test(arguments: ["String", "Double"])
    func optionalConstructorCloneKeepsPackedStorageAndDefaultMask(element: String) throws {
        let defaultValue = element == "String" ? "arrayOf(\"default\")" : "doubleArrayOf(1.5)"
        let ctx = makeContextFromSource("""
        class OptionalPacked(vararg values: \(element) = \(defaultValue)) { val count = values.size }
        fun probe() { val reference = ::OptionalPacked }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let functions = findAllKIRFunctions(in: module)
        let packed = try #require(functions.first {
            ctx.interner.resolve($0.name).hasPrefix("kk_reflect_constructor_packed_")
        })
        let clone = try #require(functions.first {
            let name = ctx.interner.resolve($0.name)
            return name.hasPrefix("kk_reflect_invoke_") && name.hasSuffix("_constructor")
                && $0.params.first?.symbol == packed.params.first?.symbol
                && extractCallees(from: $0.body, interner: ctx.interner).contains("OptionalPacked$default")
        })
        try #require(clone.params.count == 2)
        #expect(className(clone.params[0].type, sema: sema, interner: ctx.interner)
            == (element == "String" ? "kotlin.Array" : "kotlin.DoubleArray"))
        #expect(clone.params[1].type == sema.types.intType)
        #expect(extractCallees(from: clone.body, interner: ctx.interner).contains("kk_object_new"))
        let stub = try #require(functions.first { ctx.interner.resolve($0.name) == "OptionalPacked$default" })
        #expect(stub.params.last?.type == sema.types.intType)
        #expect(className(stub.params[1].type, sema: sema, interner: ctx.interner)
            == (element == "String" ? "kotlin.Array" : "kotlin.DoubleArray"))
        #expect(!extractCallees(from: stub.body, interner: ctx.interner).contains("__kk_array_toList"))
        #expect(!extractCallees(from: packed.body, interner: ctx.interner).contains("__kk_collection_toTypedArray"))
    }

    @Test
    func ordinaryOptionalVarargUsesDefaultMaskWithArrayStorage() throws {
        let ctx = makeContextFromSource("""
        fun defaults(vararg values: Double = doubleArrayOf(1.5)) = values.size
        fun probe() = defaults()
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let probe = try findKIRFunction(named: "probe", in: module, interner: ctx.interner)
        let arguments = try #require(probe.body.compactMap { instruction -> [KIRExprID]? in
            if case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
               ctx.interner.resolve(callee) == "defaults$default" { return arguments }
            return nil
        }.first)
        try #require(arguments.count == 2)
        #expect(className(try #require(module.arena.exprType(arguments[0])), sema: sema, interner: ctx.interner) == "kotlin.DoubleArray")
        #expect(module.arena.expr(arguments[1]) == .intLiteral(1))
        #expect(!extractCallees(from: probe.body, interner: ctx.interner).contains("kk_array_new"))
    }

    @Test(arguments: ["listOf(\"wrong\")", "arrayOf(1)"])
    func referenceVarargDefaultRejectsListAndWrongElement(defaultExpression: String) throws {
        let ctx = makeContextFromSource("""
        fun invalid(vararg values: String = \(defaultExpression)) = values.size
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A vararg declaration default must be its source array type")
    }

    @Test
    func tailrecOptionalReferenceDefaultUsesPackedTemporary() throws {
        let ctx = makeContextFromSource("""
        tailrec fun repeat(n: Int, vararg values: String = arrayOf("default")): Int =
            if (n == 0) values.size else repeat(n - 1)
        fun probe() = repeat(1)
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let repeatFunction = try findKIRFunction(named: "repeat", in: module, interner: ctx.interner)
        let arguments = try #require(repeatFunction.body.compactMap { instruction -> [KIRExprID]? in
            if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
               symbol == repeatFunction.symbol { return arguments }
            return nil
        }.first)
        try #require(arguments.count == 2)
        #expect(className(try #require(module.arena.exprType(arguments[1])), sema: sema, interner: ctx.interner) == "kotlin.Array")
        let callees = extractCallees(from: repeatFunction.body, interner: ctx.interner)
        #expect(!callees.contains("__kk_array_toList"))
        #expect(!callees.contains("repeat$default"))
    }

    @Test
    func referenceBodyAndConstructorPropertyKeepThePackedArray() throws {
        let ctx = makeContextFromSource("""
        class Words(vararg val words: String)
        open class BaseWords { open fun pack(vararg words: String): Array<out String> = words }
        class DerivedWords : BaseWords() { override fun pack(vararg words: String): Array<out String> = words }
        fun virtualProbe(base: BaseWords) { val whole: (Array<out String>) -> Array<out String> = base::pack; val scalar: (String) -> Array<out String> = base::pack }
        fun words(vararg values: String): Array<out String> = values
        fun probe() { val function: (Array<out String>) -> Array<out String> = ::words; val constructor: (Array<out String>) -> Words = ::Words }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let words = try findKIRFunction(named: "words", in: module, interner: ctx.interner)
        #expect(className(words.params[0].type, sema: sema, interner: ctx.interner) == "kotlin.Array")
        let thunks = findAllKIRFunctions(in: module).filter { function in
            sema.symbols.symbol(function.symbol)?.fqName.first.map(ctx.interner.resolve)?.hasPrefix("kk_function_virtual_thunk_") == true
        }
        try #require(!thunks.isEmpty)
        for thunk in thunks {
            #expect(thunk.params.count == 2)
            #expect(className(thunk.params[1].type, sema: sema, interner: ctx.interner) == "kotlin.Array")
            #expect(!extractCallees(from: thunk.body, interner: ctx.interner).contains("kk_array_new"), "already packed virtual arguments stay packed")
        }
        let allCalls = findAllKIRFunctions(in: module).flatMap { extractCallees(from: $0.body, interner: ctx.interner) }
        #expect(!allCalls.contains("__kk_array_toList"))
        #expect(!allCalls.contains("__kk_collection_toTypedArray"))
    }

    @Test
    func nonVarargReifiedClassAndComponentSlotsAreIndependent() throws {
        let ctx = makeContextFromSource("""
        inline fun <reified T> token(value: T): String = T::class.simpleName ?: "?"
        inline fun <reified T> defaults(value: T? = null): Array<T> = emptyArray<T>()
        inline fun <reified A, reified B> ordered(supplier: () -> Array<B> = { emptyArray<B>() }): Pair<Array<A>, Array<B>> = Pair(emptyArray<A>(), supplier())
        fun probe() = token<String>("x")
        fun pairProbe() = ordered<String, Array<String>>()
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let token = try findKIRFunction(named: "token", in: module, interner: ctx.interner)
        try #require(token.params.count == 3)
        let sema = try #require(ctx.sema)
        let signature = try #require(sema.symbols.functionSignature(for: token.symbol))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        #expect(token.params[1].symbol == SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameter))
        #expect(token.params[2].symbol == SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: typeParameter))
        let defaults = try findKIRFunction(named: "defaults$default", in: module, interner: ctx.interner)
        #expect(defaults.params.count == 4, "value/class/component/default-mask slots")
        let probe = try findKIRFunction(named: "probe", in: module, interner: ctx.interner)
        let arguments = try #require(probe.body.compactMap { instruction -> [KIRExprID]? in
            if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction, symbol == token.symbol { return arguments }
            return nil
        }.first)
        #expect(arguments.count == 3)
        #expect(extractCallees(from: probe.body, interner: ctx.interner).contains("__kk_array_component_type"))
        let ordered = try findKIRFunction(named: "ordered", in: module, interner: ctx.interner)
        let orderedSignature = try #require(sema.symbols.functionSignature(for: ordered.symbol))
        try #require(orderedSignature.typeParameterSymbols.count == 2)
        let hiddenSymbols = orderedSignature.typeParameterSymbols.flatMap { parameter in
            [SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: parameter), SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: parameter)]
        }
        #expect(ordered.params.count == 5, "closure plus class/component pairs for A and B")
        #expect(Array(ordered.params.suffix(4)).map(\.symbol) == hiddenSymbols, "ordered class-A/component-A/class-B/component-B slots")
        #expect(ordered.params.suffix(4).allSatisfy { $0.type == sema.types.intType })
        let orderedStub = try findKIRFunction(named: "ordered$default", in: module, interner: ctx.interner)
        #expect(orderedStub.params.count == 6, "closure/four hidden words/default mask")
        #expect(orderedStub.params.last?.type == sema.types.intType)
        #expect(extractCallees(from: orderedStub.body, interner: ctx.interner).contains("__kk_pair_new"))
    }

    @Test
    func typedEmptyArrayFactoriesCarryComponentMetadata() throws {
        let ctx = makeContextFromSource("""
        fun strings() = emptyArray<String>()
        fun nested() = emptyArray<Array<String>>()
        fun boxedInts() = emptyArray<Int>()
        inline fun <reified T> reifiedEmpty() = emptyArray<T>()
        fun probe() {
            strings()
            nested()
            boxedInts()
            reifiedEmpty<Array<String>>()
        }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        for name in ["strings", "nested", "boxedInts", "reifiedEmpty"] {
            let function = try findKIRFunction(named: name, in: module, interner: ctx.interner)
            let callees = extractCallees(from: function.body, interner: ctx.interner)
            #expect(callees.contains("kk_array_new"), "\(name) allocates a typed empty array")
            #expect(callees.contains("kk_array_tag_type"), "\(name) retains Array nominal identity")
            #expect(callees.contains("__kk_array_tag_component"), "\(name) attaches its component descriptor")
            #expect(!callees.contains("kk_empty_array"), "\(name) does not discard its allocation component")
        }
    }

    @Test
    func capturedReifiedDescriptorUsesOneRootedPairAndTwoDecodedSlots() throws {
        let ctx = makeContextFromSource("""
        inline fun <reified T> capture(): Array<T> { val supplier = { emptyArray<T>() }; return supplier() }
        inline fun <reified T> defaultCapture(value: Array<T> = run { val supplier = { emptyArray<T>() }; supplier() }): Array<T> = value
        inline fun <reified T> defaultSupplier(supplier: () -> Array<T> = { emptyArray<T>() }): Array<T> = supplier()
        fun probe() = capture<Array<String>>()
        fun defaultProbe() = defaultCapture<Array<String>>()
        fun supplierProbe() = defaultSupplier<Array<String>>()
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let capture = try findKIRFunction(named: "capture", in: module, interner: ctx.interner)
        #expect(capture.params.count == 2, "class/component hidden slots")
        #expect(extractCallees(from: capture.body, interner: ctx.interner).contains("__kk_pair_new"))
        let defaultStub = try findKIRFunction(named: "defaultCapture$default", in: module, interner: ctx.interner)
        #expect(defaultStub.params.count == 4, "array/class/component/mask")
        #expect(extractCallees(from: defaultStub.body, interner: ctx.interner).contains("__kk_pair_new"))
        let supplierStub = try findKIRFunction(named: "defaultSupplier$default", in: module, interner: ctx.interner)
        #expect(supplierStub.params.count == 4, "closure/class/component/mask")
        #expect(extractCallees(from: supplierStub.body, interner: ctx.interner).contains("__kk_pair_new"), "function-valued default captures both hidden descriptors")
        let lambdas = findAllKIRFunctions(in: module).filter {
            extractCallees(from: $0.body, interner: ctx.interner).contains("__kk_pair_first")
        }
        try #require(!lambdas.isEmpty)
        for lambda in lambdas {
            #expect(lambda.params.count == 1, "one rooted pair capture, no extra hidden receiver/member slot")
            #expect(extractCallees(from: lambda.body, interner: ctx.interner).contains("__kk_pair_second"))
        }
    }

    @Test
    func genericCallableArrayAndScalarShapesStayDistinct() throws {
        let ctx = makeContextFromSource("""
        fun <T> identity(vararg values: T): Array<out T> = values
        fun nestedIdentity(vararg values: Array<String>): Array<out Array<String>> = values
        fun passthrough(values: Array<out String>): Array<out String> = values
        fun passthroughProbe(values: Array<out String>): Array<out String> = passthrough(values)
        fun probe() {
            val whole: (Array<out String>) -> Array<out String> = ::identity
            val scalar: (String) -> Array<out String> = ::identity
            val scalarInt: (Int) -> Array<out Int> = ::identity
            val scalarNullable: (String?) -> Array<out String?> = ::identity
            val nestedWhole: (Array<out Array<String>>) -> Array<out Array<String>> = ::nestedIdentity
        }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let passthrough = try findKIRFunction(named: "passthroughProbe", in: module, interner: ctx.interner)
        #expect(!extractCallees(from: passthrough.body, interner: ctx.interner).contains("__kk_array_tag_component"), "return types cannot manufacture missing allocation components")
        let identity = try findKIRFunction(named: "identity", in: module, interner: ctx.interner)
        let nested = try findKIRFunction(named: "nestedIdentity", in: module, interner: ctx.interner)
        let wrappers = findAllKIRFunctions(in: module).filter { function in
            function.symbol != identity.symbol && function.body.contains { instruction in
                if case let .call(symbol, _, _, _, _, _, _, _) = instruction { return symbol == identity.symbol || symbol == nested.symbol }
                return false
            }
        }
        let allocations = wrappers.map { extractCallees(from: $0.body, interner: ctx.interner).contains("kk_array_new") }
        #expect(allocations.contains(false), "whole-array invoke preserves identity")
        #expect(allocations.filter { $0 }.count >= 3, "generic scalar String, Int and nullable adapters retain reference Array storage")
        let sema = try #require(ctx.sema)
        let stringToken = RuntimeTypeCheckToken.encode(type: sema.types.stringType, sema: sema, interner: ctx.interner)
        let stringComponents = wrappers.flatMap(\.body).filter { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "__kk_array_component_type",
                  let classifier = arguments.first else { return false }
            return module.arena.expr(classifier) == .intLiteral(stringToken)
        }
        #expect(stringComponents.count >= 2, "String and nullable String use the specialized erased reference component")
        let intToken = RuntimeTypeCheckToken.encode(type: sema.types.intType, sema: sema, interner: ctx.interner)
        let intComponents = wrappers.flatMap(\.body).filter { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "__kk_array_component_type",
                  let classifier = arguments.first else { return false }
            return module.arena.expr(classifier) == .intLiteral(intToken)
        }
        #expect(!intComponents.isEmpty, "specializing T to Int keeps reference storage with boxed Integer component")
    }

    @Test(arguments: [false, true])
    func arrayContextDoesNotRetryAFailedPackedMatchAsScalar(generic: Bool) throws {
        let declaration = generic
            ? "fun <T> identity(vararg values: T): Array<out T> = values"
            : "fun identity(vararg values: Array<String>): Array<out Array<String>> = values"
        let ctx = makeContextFromSource("""
        \(declaration)
        fun probe() { val invalid: (Array<String>) -> Array<out Array<String>> = ::identity }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Kotlin2.3.10 rejects generic and concrete Array-shaped scalar callable references")
    }


    @Test(arguments: ["direct", "nested", "mutual", "deep", "valid", "reified"])
    func cyclicComponentMetadataTerminatesWithoutInventingAClassifier(shape: String) {
        // Exercise the lowering boundary directly, independent of whether a
        // source parser or a library metadata importer admits these bounds.
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(),
                              diagnostics: DiagnosticEngine(), interner: interner)
        let arraySymbol = symbols.define(kind: .class, name: interner.intern("Array"),
            fqName: [interner.intern("kotlin"), interner.intern("Array")],
            declSite: nil, visibility: .public)
        func array(_ element: TypeID) -> TypeID {
            types.make(.classType(ClassType(classSymbol: arraySymbol,
                args: [.out(element)], nullability: .nonNull)))
        }
        func parameter(_ name: String) -> (SymbolID, TypeID) {
            let symbol = symbols.define(kind: .typeParameter, name: interner.intern(name),
                fqName: [interner.intern(name)], declSite: nil, visibility: .public,
                flags: shape == "reified" ? .reifiedTypeParameter : [])
            return (symbol, types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull))))
        }
        let (tSymbol, t) = parameter("T")
        let input: TypeID
        switch shape {
        case "direct":
            symbols.setTypeParameterUpperBounds([t], for: tSymbol)
            input = t
        case "nested", "reified":
            symbols.setTypeParameterUpperBounds([array(t)], for: tSymbol)
            input = t
        case "mutual":
            let (uSymbol, u) = parameter("U")
            symbols.setTypeParameterUpperBounds([array(u)], for: tSymbol)
            symbols.setTypeParameterUpperBounds([array(t)], for: uSymbol)
            input = t
        case "deep":
            var nested = types.stringType
            for _ in 0..<80 { nested = array(nested) }
            input = nested
        default:
            input = array(array(types.stringType))
        }
        let arena = KIRArena()
        var instructions: [KIRInstruction] = []
        let result = runtimeArrayComponentTypeExpr(for: input, useReifiedToken: shape == "reified",
            sema: sema, arena: arena, interner: interner, instructions: &instructions)
        let descriptorCalls = extractCallees(from: instructions, interner: interner)
            .filter { $0 == "__kk_array_component_type" }
        if shape == "reified" {
            let token = SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: tSymbol)
            #expect(arena.expr(result) == .symbolRef(token))
            #expect(descriptorCalls.isEmpty)
            #expect(instructions.count == 1, "reified tokens bypass erasure of their bounds")
        } else if shape == "valid" {
            #expect(arena.expr(result) != .intLiteral(0))
            #expect(descriptorCalls.count == 3, "valid nested components still use each concrete classifier")
        } else {
            #expect(arena.expr(result) == .intLiteral(0))
            #expect(descriptorCalls.isEmpty, "unknown metadata must not manufacture an Any descriptor")
            #expect(instructions.count == 1, "failure propagates directly through every parent")
        }
    }

    private func className(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> String? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol) else { return nil }
        return symbol.fqName.map(interner.resolve).joined(separator: ".")
    }
}
