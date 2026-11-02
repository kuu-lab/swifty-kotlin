@testable import CompilerCore
import Testing

private struct NominalLUBFixture {
    let types = TypeSystem()
    let box = SymbolID(rawValue: 100)
    let module = SymbolID(rawValue: 101)
    let a = SymbolID(rawValue: 102)
    let b = SymbolID(rawValue: 103)
    let unrelated = SymbolID(rawValue: 104)

    init(variance: TypeVariance = .out) {
        types.setNominalTypeParameterVariances([variance], for: box)
        types.setNominalDirectSupertypes([module], for: a)
        types.setNominalDirectSupertypes([module], for: b)
    }

    func nominal(_ symbol: SymbolID) -> TypeID {
        types.make(.classType(ClassType(classSymbol: symbol)))
    }

    func applied(_ argument: TypeArg) -> TypeID {
        types.make(.classType(ClassType(classSymbol: box, args: [argument])))
    }
}

extension TypeSystemTests {
    // Invariant and `out`-declared positions both join to a covariant
    // argument (`lub(Box<A>, Box<B>) == Box<out Module>` in kotlinc); only
    // an `in`-declared position still approximates to `Any`.
    @Test(arguments: [TypeVariance.out, .invariant, .in])
    func nominalLUBCombinesOutBoundablePositions(variance: TypeVariance) {
        let fixture = NominalLUBFixture(variance: variance)
        let types = fixture.types
        let left = fixture.applied(.invariant(fixture.nominal(fixture.a)))
        let right = fixture.applied(.invariant(fixture.nominal(fixture.b)))
        let expected = variance == .in
            ? types.anyType : fixture.applied(.out(fixture.nominal(fixture.module)))
        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
        #expect(types.isSubtype(left, expected))
        #expect(types.isSubtype(right, expected))
        if variance != .out {
            #expect(!types.isSubtype(left, fixture.applied(.invariant(fixture.nominal(fixture.module)))))
        }
    }

    /// KUU-3919: `KSerializer<Any?>` joined with `KSerializer<out Any>` on
    /// the invariant `KSerializer<T>` must produce `KSerializer<out Any?>`
    /// (Ktor `TypeInfo.serializer()`'s `?:` branch). Previously the
    /// invariant composed projection bailed out and the join fell back to
    /// `Any`, failing the `KSerializer<out Any?>` return-type check.
    @Test
    func nominalLUBJoinsInvariantAndUseSiteOutArgument() {
        let fixture = NominalLUBFixture(variance: .invariant)
        let types = fixture.types
        let left = fixture.applied(.invariant(types.nullableAnyType))
        let right = fixture.applied(.out(types.anyType))
        let expected = fixture.applied(.out(types.nullableAnyType))
        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
        #expect(types.isSubtype(left, expected))
        #expect(types.isSubtype(right, expected))
    }

    @Test
    func nominalLUBCombinesUseSiteOutProjections() {
        let fixture = NominalLUBFixture(variance: .invariant)
        let left = fixture.applied(.out(fixture.nominal(fixture.a)))
        let right = fixture.applied(.out(fixture.nominal(fixture.b)))
        let expected = fixture.applied(.out(fixture.nominal(fixture.module)))
        #expect(fixture.types.lub([left, right]) == expected)
        #expect(fixture.types.lub([right, left]) == expected)
    }

    @Test
    func nominalLUBKeepsUnrelatedArgumentsAtAny() {
        let fixture = NominalLUBFixture()
        let left = fixture.applied(.invariant(fixture.nominal(fixture.a)))
        let right = fixture.applied(.invariant(fixture.nominal(fixture.unrelated)))
        let expected = fixture.applied(.out(fixture.types.anyType))
        #expect(fixture.types.lub([left, right]) == expected)
        #expect(fixture.types.lub([right, left]) == expected)
        #expect(!fixture.types.isSubtype(expected, fixture.applied(.invariant(fixture.nominal(fixture.module)))))
    }

    @Test(arguments: [false, true])
    func nominalLUBPreservesInnerAndOuterNullability(nullableArgument: Bool) {
        let fixture = NominalLUBFixture()
        let types = fixture.types
        let a = fixture.nominal(fixture.a)
        let b = fixture.nominal(fixture.b)
        let module = fixture.nominal(fixture.module)
        let left = fixture.applied(.invariant(nullableArgument ? types.makeNullable(a) : a))
        let right = fixture.applied(.invariant(b))
        let expected = fixture.applied(.out(nullableArgument ? types.makeNullable(module) : module))
        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
        #expect(types.lub([types.makeNullable(left), right]) == types.makeNullable(expected))
        #expect(types.lub([right, types.makeNullable(left)]) == types.makeNullable(expected))
        #expect(types.lub([left, right, types.nullableNothingType]) == types.makeNullable(expected))
    }

    @Test
    func nominalLUBLiftsInheritedGenericArgumentsBeforeCombining() {
        let fixture = NominalLUBFixture()
        let types = fixture.types
        let middle = SymbolID(rawValue: 105)
        let leftChild = SymbolID(rawValue: 106)
        let rightChild = SymbolID(rawValue: 107)
        for child in [middle, leftChild, rightChild] {
            let parameter = SymbolID(rawValue: child.rawValue + 100)
            let parameterType = types.make(.typeParam(TypeParamType(symbol: parameter)))
            types.setNominalTypeParameterSymbols([parameter], for: child)
            types.setNominalTypeParameterVariances([.out], for: child)
            let parent = child == middle ? fixture.box : middle
            types.setNominalDirectSupertypes([parent], for: child)
            types.setNominalSupertypeTypeArgs([.invariant(parameterType)], for: child, supertype: parent)
        }
        let left = types.make(.classType(ClassType(classSymbol: leftChild, args: [.invariant(fixture.nominal(fixture.a))])))
        let right = types.make(.classType(ClassType(classSymbol: rightChild, args: [.invariant(fixture.nominal(fixture.b))])))
        let expected = types.make(.classType(ClassType(classSymbol: middle, args: [.out(fixture.nominal(fixture.module))])))
        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
        #expect(types.isSubtype(left, expected))
        #expect(types.isSubtype(right, expected))
    }

    @Test(arguments: [2, TypeSystem.maxNominalLUBDepth])
    func nominalLUBCombinesNestedInstancesOfTheSameConstructor(depth: Int) {
        let fixture = NominalLUBFixture()
        var left = fixture.nominal(fixture.a)
        var right = fixture.nominal(fixture.b)
        var expected = fixture.nominal(fixture.module)
        for _ in 0 ..< depth {
            left = fixture.applied(.invariant(left))
            right = fixture.applied(.invariant(right))
            expected = fixture.applied(.out(expected))
        }
        #expect(fixture.types.lub([left, right]) == expected)
        #expect(fixture.types.lub([right, left]) == expected)
    }

    @Test
    func nominalLUBTerminatesForRecursiveGenericSupertypes() {
        let fixture = NominalLUBFixture()
        let types = fixture.types
        for child in [fixture.a, fixture.b] {
            types.setNominalDirectSupertypes([fixture.box], for: child)
            types.setNominalSupertypeTypeArgs([.invariant(fixture.nominal(child))], for: child, supertype: fixture.box)
        }
        let left = fixture.nominal(fixture.a)
        let right = fixture.nominal(fixture.b)
        let expected = fixture.applied(.out(types.anyType))
        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
        #expect(types.isSubtype(left, expected))
        #expect(types.isSubtype(right, expected))
        #expect(types.activeNominalLUBInputs.isEmpty)
    }

    @Test
    func nominalLUBUsesSoundApproximationForDeepNesting() {
        let fixture = NominalLUBFixture()
        var left = fixture.nominal(fixture.a)
        var right = fixture.nominal(fixture.b)
        for _ in 0 ..< TypeSystem.maxNominalLUBDepth + 1 {
            left = fixture.applied(.invariant(left))
            right = fixture.applied(.invariant(right))
        }
        for inputs in [[left, right], [right, left]] {
            let result = fixture.types.lub(inputs)
            #expect(result != fixture.types.anyType)
            #expect(inputs.allSatisfy { fixture.types.isSubtype($0, result) })
            #expect(fixture.types.activeNominalLUBInputs.isEmpty)
        }
    }

    @Test
    func nominalLUBPreservesUnchangedInvariantAndContravariantPositions() {
        let fixture = NominalLUBFixture()
        let types = fixture.types
        types.setNominalTypeParameterVariances([.invariant, .in, .out], for: fixture.box)
        func applied(_ argument: TypeID, first: TypeID) -> TypeID {
            types.make(.classType(ClassType(classSymbol: fixture.box, args: [
                .invariant(first), .invariant(types.intType), .invariant(argument),
            ])))
        }
        let left = applied(fixture.nominal(fixture.a), first: types.stringType)
        let right = applied(fixture.nominal(fixture.b), first: types.stringType)
        let expected = types.make(.classType(ClassType(classSymbol: fixture.box, args: [
            .invariant(types.stringType), .invariant(types.intType), .out(fixture.nominal(fixture.module)),
        ])))
        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
        let incompatible = applied(fixture.nominal(fixture.b), first: types.intType)
        // Differing arguments on an invariant position join covariantly
        // (`Box<out Any>` for `Box<String>` vs `Box<Int>`), matching
        // kotlinc; the identical `in` and differing `out` positions are
        // unchanged.
        let incompatibleExpected = types.make(.classType(ClassType(classSymbol: fixture.box, args: [
            .out(types.anyType), .invariant(types.intType), .out(fixture.nominal(fixture.module)),
        ])))
        #expect(types.lub([left, incompatible]) == incompatibleExpected)
        #expect(types.lub([incompatible, left]) == incompatibleExpected)
        #expect(types.isSubtype(left, incompatibleExpected))
        #expect(types.isSubtype(incompatible, incompatibleExpected))
    }

    @Test
    func nominalLUBTerminatesWhenRecursiveArgumentsGrow() {
        let fixture = NominalLUBFixture()
        let types = fixture.types
        for child in [fixture.a, fixture.b] {
            let parameter = SymbolID(rawValue: child.rawValue + 100)
            let parameterType = types.make(.typeParam(TypeParamType(symbol: parameter)))
            types.setNominalTypeParameterSymbols([parameter], for: child)
            types.setNominalTypeParameterVariances([.out], for: child)
            let expanded = types.make(.classType(ClassType(classSymbol: child, args: [
                .invariant(fixture.applied(.invariant(parameterType))),
            ])))
            types.setNominalDirectSupertypes([fixture.box], for: child)
            types.setNominalSupertypeTypeArgs([.invariant(expanded)], for: child, supertype: fixture.box)
        }
        let left = types.make(.classType(ClassType(classSymbol: fixture.a, args: [.invariant(types.stringType)])))
        let right = types.make(.classType(ClassType(classSymbol: fixture.b, args: [.invariant(types.stringType)])))
        for inputs in [[left, right], [right, left]] {
            let result = types.lub(inputs)
            guard case let .classType(joined) = types.kind(of: result) else {
                Issue.record("Expected the recursive common constructor")
                return
            }
            #expect(joined.classSymbol == fixture.box)
            #expect(inputs.allSatisfy { types.isSubtype($0, result) })
            #expect(types.activeNominalLUBInputs.isEmpty)
        }
    }
}
