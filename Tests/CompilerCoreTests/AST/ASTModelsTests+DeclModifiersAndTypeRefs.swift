#if canImport(Testing)
@testable import CompilerCore
import Testing

extension ASTModelsTests {
    @Test
    func testDeclVariantClassDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let classDecl = ClassDecl(range: r, name: interner.intern("MyClass"), modifiers: [.public], typeParams: [], primaryConstructorParams: [])
        let decl = Decl.classDecl(classDecl)
        if case let .classDecl(d) = decl {
            #expect(d.name == interner.intern("MyClass"))
        } else {
            Issue.record("Expected .classDecl")
        }
    }

    @Test
    func testDeclVariantInterfaceDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let ifaceDecl = InterfaceDecl(range: r, name: interner.intern("MyInterface"), modifiers: [.abstract])
        let decl = Decl.interfaceDecl(ifaceDecl)
        if case let .interfaceDecl(d) = decl {
            #expect(d.name == interner.intern("MyInterface"))
            #expect(d.modifiers == [.abstract])
        } else {
            Issue.record("Expected .interfaceDecl")
        }
    }

    @Test
    func testDeclVariantFunDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let funDecl = FunDecl(range: r, name: interner.intern("doStuff"), modifiers: [.suspend])
        let decl = Decl.funDecl(funDecl)
        if case let .funDecl(d) = decl {
            #expect(d.name == interner.intern("doStuff"))
            #expect(d.modifiers.contains(.suspend))
        } else {
            Issue.record("Expected .funDecl")
        }
    }

    @Test
    func testDeclVariantPropertyDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let propDecl = PropertyDecl(range: r, name: interner.intern("count"), modifiers: [.private], type: TypeRefID(rawValue: 0))
        let decl = Decl.propertyDecl(propDecl)
        if case let .propertyDecl(d) = decl {
            #expect(d.name == interner.intern("count"))
            #expect(d.modifiers.contains(.private))
        } else {
            Issue.record("Expected .propertyDecl")
        }
    }

    @Test
    func testDeclVariantTypeAliasDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let alias = TypeAliasDecl(range: r, name: interner.intern("StringList"), modifiers: [.internal])
        let decl = Decl.typeAliasDecl(alias)
        if case let .typeAliasDecl(d) = decl {
            #expect(d.name == interner.intern("StringList"))
            #expect(d.modifiers == [.internal])
        } else {
            Issue.record("Expected .typeAliasDecl")
        }
    }

    @Test
    func testDeclVariantObjectDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let objDecl = ObjectDecl(range: r, name: interner.intern("Companion"), modifiers: [.public])
        let decl = Decl.objectDecl(objDecl)
        if case let .objectDecl(d) = decl {
            #expect(d.name == interner.intern("Companion"))
        } else {
            Issue.record("Expected .objectDecl")
        }
    }

    @Test
    func testDeclVariantEnumEntryDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let entry = EnumEntryDecl(range: r, name: interner.intern("RED"))
        let decl = Decl.enumEntryDecl(entry)
        if case let .enumEntryDecl(d) = decl {
            #expect(d.name == interner.intern("RED"))
        } else {
            Issue.record("Expected .enumEntryDecl")
        }
    }

    @Test
    func testAllDeclVariantsInArena() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()

        let classID = arena.appendDecl(.classDecl(ClassDecl(range: r, name: interner.intern("C"), modifiers: [], typeParams: [], primaryConstructorParams: [])))
        let ifaceID = arena.appendDecl(.interfaceDecl(InterfaceDecl(range: r, name: interner.intern("I"), modifiers: [])))
        let funID = arena.appendDecl(.funDecl(FunDecl(range: r, name: interner.intern("f"), modifiers: [])))
        let propID = arena.appendDecl(.propertyDecl(PropertyDecl(range: r, name: interner.intern("p"), modifiers: [], type: nil)))
        let aliasID = arena.appendDecl(.typeAliasDecl(TypeAliasDecl(range: r, name: interner.intern("A"), modifiers: [])))
        let objID = arena.appendDecl(.objectDecl(ObjectDecl(range: r, name: interner.intern("O"), modifiers: [])))
        let enumID = arena.appendDecl(.enumEntryDecl(EnumEntryDecl(range: r, name: interner.intern("E"))))

        #expect(arena.declarations().count == 7)

        if case .classDecl = arena.decl(classID) {} else { Issue.record("Expected classDecl") }
        if case .interfaceDecl = arena.decl(ifaceID) {} else { Issue.record("Expected interfaceDecl") }
        if case .funDecl = arena.decl(funID) {} else { Issue.record("Expected funDecl") }
        if case .propertyDecl = arena.decl(propID) {} else { Issue.record("Expected propertyDecl") }
        if case .typeAliasDecl = arena.decl(aliasID) {} else { Issue.record("Expected typeAliasDecl") }
        if case .objectDecl = arena.decl(objID) {} else { Issue.record("Expected objectDecl") }
        if case .enumEntryDecl = arena.decl(enumID) {} else { Issue.record("Expected enumEntryDecl") }
    }

    // MARK: - Visibility enum all cases

    @Test
    func testVisibilityAllCases() {
        #expect(Visibility.public.rawValue == 0)
        #expect(Visibility.private.rawValue == 1)
        #expect(Visibility.internal.rawValue == 2)
        #expect(Visibility.protected.rawValue == 3)
    }

    @Test
    func testVisibilityInitFromRawValue() {
        #expect(Visibility(rawValue: 0) == .public)
        #expect(Visibility(rawValue: 1) == .private)
        #expect(Visibility(rawValue: 2) == .internal)
        #expect(Visibility(rawValue: 3) == .protected)
        #expect(Visibility(rawValue: 4) == nil)
        #expect(Visibility(rawValue: -1) == nil)
    }

    // MARK: - Modifiers all flags and combinations

    @Test
    func testModifiersAllIndividualFlags() {
        let allFlags: [(Modifiers, Int32)] = [
            (.public, 1 << 0),
            (.internal, 1 << 1),
            (.private, 1 << 2),
            (.protected, 1 << 3),
            (.final, 1 << 4),
            (.open, 1 << 5),
            (.abstract, 1 << 6),
            (.sealed, 1 << 7),
            (.data, 1 << 8),
            (.annotationClass, 1 << 9),
            (.inline, 1 << 10),
            (.suspend, 1 << 11),
            (.tailrec, 1 << 12),
            (.operator, 1 << 13),
            (.infix, 1 << 14),
            (.crossinline, 1 << 15),
            (.noinline, 1 << 16),
            (.vararg, 1 << 17),
            (.external, 1 << 18),
            (.expect, 1 << 19),
            (.actual, 1 << 20),
            (.value, 1 << 21),
            (.enumModifier, 1 << 22),
        ]
        for (flag, expected) in allFlags {
            #expect(flag.rawValue == expected, "Flag with rawValue \(flag.rawValue) expected \(expected)")
        }
    }

    @Test
    func testModifiersEmptySet() {
        let empty: Modifiers = []
        #expect(empty.isEmpty)
        #expect(empty.rawValue == 0)
        #expect(!(empty.contains(.public)))
    }

    @Test
    func testModifiersCombinationAccessModifiers() {
        let combo: Modifiers = [.public, .final, .data]
        #expect(combo.contains(.public))
        #expect(combo.contains(.final))
        #expect(combo.contains(.data))
        #expect(!(combo.contains(.private)))
        #expect(!(combo.contains(.abstract)))
    }

    @Test
    func testModifiersCombinationFunctionModifiers() {
        let combo: Modifiers = [.suspend, .inline, .tailrec, .operator, .infix]
        #expect(combo.contains(.suspend))
        #expect(combo.contains(.inline))
        #expect(combo.contains(.tailrec))
        #expect(combo.contains(.operator))
        #expect(combo.contains(.infix))
        #expect(!(combo.contains(.crossinline)))
    }

    @Test
    func testModifiersCombinationParameterModifiers() {
        let combo: Modifiers = [.crossinline, .noinline, .vararg]
        #expect(combo.contains(.crossinline))
        #expect(combo.contains(.noinline))
        #expect(combo.contains(.vararg))
        #expect(!(combo.contains(.suspend)))
    }

    @Test
    func testModifiersCombinationPlatformModifiers() {
        let combo: Modifiers = [.external, .expect, .actual]
        #expect(combo.contains(.external))
        #expect(combo.contains(.expect))
        #expect(combo.contains(.actual))
        #expect(!(combo.contains(.value)))
    }

    @Test
    func testModifiersCombinationClassModifiers() {
        let combo: Modifiers = [.abstract, .sealed, .open, .value, .enumModifier, .annotationClass]
        #expect(combo.contains(.abstract))
        #expect(combo.contains(.sealed))
        #expect(combo.contains(.open))
        #expect(combo.contains(.value))
        #expect(combo.contains(.enumModifier))
        #expect(combo.contains(.annotationClass))
        #expect(!(combo.contains(.final)))
    }

    @Test
    func testModifiersUnionAndIntersection() {
        let a: Modifiers = [.public, .final]
        let b: Modifiers = [.final, .data]
        let union = a.union(b)
        #expect(union.contains(.public))
        #expect(union.contains(.final))
        #expect(union.contains(.data))
        let intersection = a.intersection(b)
        #expect(intersection.contains(.final))
        #expect(!(intersection.contains(.public)))
        #expect(!(intersection.contains(.data)))
    }

    @Test
    func testModifiersSymmetricDifference() {
        let a: Modifiers = [.public, .final]
        let b: Modifiers = [.final, .open]
        let diff = a.symmetricDifference(b)
        #expect(diff.contains(.public))
        #expect(diff.contains(.open))
        #expect(!(diff.contains(.final)))
    }

    // MARK: - TypeRef variants

    @Test
    func testTypeRefNamedVariant() {
        let interner = StringInterner()
        let arena = ASTArena()
        let id = arena.appendTypeRef(.named(path: [interner.intern("kotlin"), interner.intern("String")], args: [], nullable: false))
        if case let .named(path, args, nullable) = arena.typeRef(id) {
            #expect(path.count == 2)
            #expect(args.isEmpty)
            #expect(!(nullable))
        } else {
            Issue.record("Expected .named")
        }
    }

    @Test
    func testTypeRefNamedNullableVariant() {
        let interner = StringInterner()
        let arena = ASTArena()
        let id = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: true))
        if case let .named(_, _, nullable) = arena.typeRef(id) {
            #expect(nullable)
        } else {
            Issue.record("Expected .named")
        }
    }

    @Test
    func testTypeRefNamedWithTypeArgs() {
        let interner = StringInterner()
        let arena = ASTArena()
        let innerID = arena.appendTypeRef(.named(path: [interner.intern("String")], args: [], nullable: false))
        let id = arena.appendTypeRef(.named(
            path: [interner.intern("List")],
            args: [.invariant(innerID)],
            nullable: false
        ))
        if case let .named(path, args, _) = arena.typeRef(id) {
            #expect(path.count == 1)
            #expect(args.count == 1)
        } else {
            Issue.record("Expected .named")
        }
    }

    @Test
    func testTypeRefFunctionTypeVariant() {
        let arena = ASTArena()
        let paramID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let returnID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let id = arena.appendTypeRef(.functionType(contextReceivers: [], receiver: nil, params: [paramID], returnType: returnID, isSuspend: false, nullable: false))
        if case let .functionType(contextReceivers, _, params, ret, isSuspend, nullable) = arena.typeRef(id) {
            #expect(contextReceivers.isEmpty)
            #expect(params.count == 1)
            #expect(ret == returnID)
            #expect(!(isSuspend))
            #expect(!(nullable))
        } else {
            Issue.record("Expected .functionType")
        }
    }

    @Test
    func testTypeRefFunctionTypeSuspendNullable() {
        let arena = ASTArena()
        let returnID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let id = arena.appendTypeRef(.functionType(contextReceivers: [], receiver: nil, params: [], returnType: returnID, isSuspend: true, nullable: true))
        if case let .functionType(contextReceivers, _, params, _, isSuspend, nullable) = arena.typeRef(id) {
            #expect(contextReceivers.isEmpty)
            #expect(params.isEmpty)
            #expect(isSuspend)
            #expect(nullable)
        } else {
            Issue.record("Expected .functionType")
        }
    }

    @Test
    func testTypeRefEquality() {
        let interner = StringInterner()
        let a = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: false)
        let b = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: false)
        let c = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: true)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func testTypeArgRefAllVariants() {
        let typeRef = TypeRefID(rawValue: 5)
        let invariant = TypeArgRef.invariant(typeRef)
        let outArg = TypeArgRef.out(typeRef)
        let inArg = TypeArgRef.in(typeRef)
        let star = TypeArgRef.star

        // Each variant is distinct
        #expect(invariant != outArg)
        #expect(invariant != inArg)
        #expect(invariant != star)
        #expect(outArg != inArg)
        #expect(outArg != star)
        #expect(inArg != star)

        // Same variant with same value is equal
        #expect(TypeArgRef.invariant(typeRef) == invariant)
        #expect(TypeArgRef.out(typeRef) == outArg)
        #expect(TypeArgRef.in(typeRef) == inArg)
        #expect(TypeArgRef.star == star)
    }
}
#endif
