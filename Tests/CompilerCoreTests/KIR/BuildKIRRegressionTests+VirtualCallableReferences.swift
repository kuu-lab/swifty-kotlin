#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test(arguments: ["Float", "Double"])
    func testFloatingPointRangeReferencesProbeBeforeInterfaceDispatch(element: String) throws {
        let ctx = makeContextFromSource("""
        fun probe(range: ClosedFloatingPointRange<\(element)>, value: \(element)): Boolean {
            val unbound = ClosedRange<\(element)>::contains
            val bound = range::contains
            val empty = range::isEmpty
            val less = range::lessThanOrEquals
            return unbound(range, value) && bound(value) && !empty() && less(value, value)
        }
        """)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let thunks = findAllKIRFunctions(in: module).filter { function in
            function.body.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee).hasPrefix("__kk_floating_range_")
            } && function.body.contains { instruction in
                if case .virtualCall = instruction { return true }
                return false
            }
        }
        for probe in ["contains", "isEmpty", "lessThanOrEquals"] {
            let thunk = try #require(thunks.first { function in
                function.body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "__kk_floating_range_" + probe + "_or_null"
                }
            })
            let dispatchIndex = try #require(thunk.body.firstIndex { instruction in
                guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction,
                      ctx.interner.resolve(callee) == probe else { return false }
                if case .itableDynamic = dispatch { return true }
                return false
            })
            #expect(thunk.body[..<dispatchIndex].contains { if case .jumpIfEqual = $0 { true } else { false } })
            #expect(thunk.body[(dispatchIndex + 1)...].contains { if case .label = $0 { true } else { false } })
        }
    }

    @Test
    func testArrayExtensionReferenceKeepsStaticDispatch() throws {
        let ctx = makeContextFromSource("""
        fun <T> probe(array: Array<T>, value: T): Boolean {
            val contains = Array<T>::contains
            return contains(array, value)
        }
        """)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let array = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Array")]))
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                guard case let .virtualCall(target, _, _, _, _, _, _, _) = instruction,
                      let target,
                      let signature = sema.symbols.functionSignature(for: target),
                      let receiver = signature.receiverType,
                      case let .classType(type) = sema.types.kind(of: sema.types.makeNonNullable(receiver)),
                      type.classSymbol == array
                else { continue }
                Issue.record("Array extension reference must use static dispatch: \(sema.symbols.symbol(target)?.fqName.map(ctx.interner.resolve) ?? [])")
            }
        }
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    private func virtualCalls(
        named name: String,
        in module: KIRModule,
        interner: StringInterner
    ) -> [(callee: String, dispatch: KIRDispatchKind)] {
        findAllKIRFunctions(in: module).flatMap { function in
            function.body.compactMap { instruction -> (String, KIRDispatchKind)? in
                guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction,
                      interner.resolve(callee) == name
                else { return nil }
                return (interner.resolve(callee), dispatch)
            }
        }
    }

    /// `Named::label` used as a function value must read the property through
    /// the interface's itable, not call the declaring (abstract) accessor.
    @Test
    func testInterfacePropertyReferenceFunctionValueDispatchesThroughItable() throws {
        let source = """
        interface Named { val label: String }
        class Person(override val label: String) : Named
        fun labels(people: List<Person>): List<String> = people.map(Named::label)
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let getterDispatches = virtualCalls(named: "get", in: module, interner: ctx.interner)
        #expect(
            getterDispatches.contains { call in
                if case .itableDynamic = call.dispatch { return true }
                return false
            },
            "Named::label must dispatch its getter through the itable, got: \(getterDispatches)"
        )
    }

    /// The KProperty1 wrapper (`val ref = Named::label`) shares the same
    /// dispatch requirement as the plain function-value form.
    @Test
    func testInterfacePropertyReferenceKPropertyWrapperDispatchesThroughItable() throws {
        let source = """
        interface Named { val label: String }
        class Person(override val label: String) : Named
        fun read(p: Person): String {
            val ref = Named::label
            return ref.get(p)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let getterDispatches = virtualCalls(named: "get", in: module, interner: ctx.interner)
        #expect(
            getterDispatches.contains { call in
                if case .itableDynamic = call.dispatch { return true }
                return false
            },
            "KProperty1 wrapper for Named::label must dispatch through the itable, got: \(getterDispatches)"
        )
    }

    /// `t::apply` with `t` typed as an interface must call `apply` through the
    /// itable; a final receiver type (`d::apply`) keeps the direct call.
    @Test
    func testBoundInterfaceMethodReferenceDispatchesThroughItable() throws {
        let source = """
        interface Transformer<A, B> { fun apply(a: A): B }
        class Doubler : Transformer<Int, Int> { override fun apply(a: Int) = a * 2 }
        fun viaInterface(t: Transformer<Int, Int>): List<Int> = listOf(1, 2).map(t::apply)
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let applyDispatches = virtualCalls(named: "apply", in: module, interner: ctx.interner)
        #expect(
            applyDispatches.contains { call in
                if case .itableDynamic = call.dispatch { return true }
                return false
            },
            "t::apply must dispatch through the itable, got: \(applyDispatches)"
        )
    }

    /// An open class property referenced unbound (`Base::tag`) dispatches
    /// through the vtable so an override is honoured.
    @Test
    func testOpenClassPropertyReferenceDispatchesThroughVtable() throws {
        let source = """
        open class Base { open val tag: String get() = "base" }
        class Derived : Base() { override val tag: String get() = "derived" }
        fun tags(items: List<Base>): List<String> = items.map(Base::tag)
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let getterDispatches = virtualCalls(named: "get", in: module, interner: ctx.interner)
        #expect(
            getterDispatches.contains { call in
                if case .vtable = call.dispatch { return true }
                return false
            },
            "Base::tag must dispatch its getter through the vtable, got: \(getterDispatches)"
        )
    }
}
#endif
