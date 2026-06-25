@testable import CompilerCore
import XCTest

extension ASTModelsTests {
    func testDeclVariantClassDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let classDecl = ClassDecl(range: r, name: interner.intern("MyClass"), modifiers: [.public], typeParams: [], primaryConstructorParams: [])
        let decl = Decl.classDecl(classDecl)
        if case let .classDecl(d) = decl {
            XCTAssertEqual(d.name, interner.intern("MyClass"))
        } else {
            XCTFail("Expected .classDecl")
        }
    }

    func testDeclVariantInterfaceDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let ifaceDecl = InterfaceDecl(range: r, name: interner.intern("MyInterface"), modifiers: [.abstract])
        let decl = Decl.interfaceDecl(ifaceDecl)
        if case let .interfaceDecl(d) = decl {
            XCTAssertEqual(d.name, interner.intern("MyInterface"))
            XCTAssertEqual(d.modifiers, [.abstract])
        } else {
            XCTFail("Expected .interfaceDecl")
        }
    }

    func testDeclVariantFunDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let funDecl = FunDecl(range: r, name: interner.intern("doStuff"), modifiers: [.suspend])
        let decl = Decl.funDecl(funDecl)
        if case let .funDecl(d) = decl {
            XCTAssertEqual(d.name, interner.intern("doStuff"))
            XCTAssertTrue(d.modifiers.contains(.suspend))
        } else {
            XCTFail("Expected .funDecl")
        }
    }

    func testDeclVariantPropertyDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let propDecl = PropertyDecl(range: r, name: interner.intern("count"), modifiers: [.private], type: TypeRefID(rawValue: 0))
        let decl = Decl.propertyDecl(propDecl)
        if case let .propertyDecl(d) = decl {
            XCTAssertEqual(d.name, interner.intern("count"))
            XCTAssertTrue(d.modifiers.contains(.private))
        } else {
            XCTFail("Expected .propertyDecl")
        }
    }

    func testDeclVariantTypeAliasDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let alias = TypeAliasDecl(range: r, name: interner.intern("StringList"), modifiers: [.internal])
        let decl = Decl.typeAliasDecl(alias)
        if case let .typeAliasDecl(d) = decl {
            XCTAssertEqual(d.name, interner.intern("StringList"))
            XCTAssertEqual(d.modifiers, [.internal])
        } else {
            XCTFail("Expected .typeAliasDecl")
        }
    }

    func testDeclVariantObjectDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let objDecl = ObjectDecl(range: r, name: interner.intern("Companion"), modifiers: [.public])
        let decl = Decl.objectDecl(objDecl)
        if case let .objectDecl(d) = decl {
            XCTAssertEqual(d.name, interner.intern("Companion"))
        } else {
            XCTFail("Expected .objectDecl")
        }
    }

    func testDeclVariantEnumEntryDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let entry = EnumEntryDecl(range: r, name: interner.intern("RED"))
        let decl = Decl.enumEntryDecl(entry)
        if case let .enumEntryDecl(d) = decl {
            XCTAssertEqual(d.name, interner.intern("RED"))
        } else {
            XCTFail("Expected .enumEntryDecl")
        }
    }

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

        XCTAssertEqual(arena.declarations().count, 7)

        if case .classDecl = arena.decl(classID) {} else { XCTFail("Expected classDecl") }
        if case .interfaceDecl = arena.decl(ifaceID) {} else { XCTFail("Expected interfaceDecl") }
        if case .funDecl = arena.decl(funID) {} else { XCTFail("Expected funDecl") }
        if case .propertyDecl = arena.decl(propID) {} else { XCTFail("Expected propertyDecl") }
        if case .typeAliasDecl = arena.decl(aliasID) {} else { XCTFail("Expected typeAliasDecl") }
        if case .objectDecl = arena.decl(objID) {} else { XCTFail("Expected objectDecl") }
        if case .enumEntryDecl = arena.decl(enumID) {} else { XCTFail("Expected enumEntryDecl") }
    }

    // MARK: - TypeRef variants

    func testTypeRefNamedVariant() {
        let interner = StringInterner()
        let arena = ASTArena()
        let id = arena.appendTypeRef(.named(path: [interner.intern("kotlin"), interner.intern("String")], args: [], nullable: false))
        if case let .named(path, args, nullable) = arena.typeRef(id) {
            XCTAssertEqual(path.count, 2)
            XCTAssertTrue(args.isEmpty)
            XCTAssertFalse(nullable)
        } else {
            XCTFail("Expected .named")
        }
    }

    func testTypeRefNamedNullableVariant() {
        let interner = StringInterner()
        let arena = ASTArena()
        let id = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: true))
        if case let .named(_, _, nullable) = arena.typeRef(id) {
            XCTAssertTrue(nullable)
        } else {
            XCTFail("Expected .named")
        }
    }

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
            XCTAssertEqual(path.count, 1)
            XCTAssertEqual(args.count, 1)
        } else {
            XCTFail("Expected .named")
        }
    }

    func testTypeRefFunctionTypeVariant() {
        let arena = ASTArena()
        let paramID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let returnID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let id = arena.appendTypeRef(.functionType(contextReceivers: [], receiver: nil, params: [paramID], returnType: returnID, isSuspend: false, nullable: false))
        if case let .functionType(contextReceivers, _, params, ret, isSuspend, nullable) = arena.typeRef(id) {
            XCTAssertTrue(contextReceivers.isEmpty)
            XCTAssertEqual(params.count, 1)
            XCTAssertEqual(ret, returnID)
            XCTAssertFalse(isSuspend)
            XCTAssertFalse(nullable)
        } else {
            XCTFail("Expected .functionType")
        }
    }

    func testTypeRefFunctionTypeSuspendNullable() {
        let arena = ASTArena()
        let returnID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let id = arena.appendTypeRef(.functionType(contextReceivers: [], receiver: nil, params: [], returnType: returnID, isSuspend: true, nullable: true))
        if case let .functionType(contextReceivers, _, params, _, isSuspend, nullable) = arena.typeRef(id) {
            XCTAssertTrue(contextReceivers.isEmpty)
            XCTAssertTrue(params.isEmpty)
            XCTAssertTrue(isSuspend)
            XCTAssertTrue(nullable)
        } else {
            XCTFail("Expected .functionType")
        }
    }

    func testTypeRefEquality() {
        let interner = StringInterner()
        let a = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: false)
        let b = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: false)
        let c = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTypeArgRefAllVariants() {
        let typeRef = TypeRefID(rawValue: 5)
        let invariant = TypeArgRef.invariant(typeRef)
        let outArg = TypeArgRef.out(typeRef)
        let inArg = TypeArgRef.in(typeRef)
        let star = TypeArgRef.star

        // Each variant is distinct
        XCTAssertNotEqual(invariant, outArg)
        XCTAssertNotEqual(invariant, inArg)
        XCTAssertNotEqual(invariant, star)
        XCTAssertNotEqual(outArg, inArg)
        XCTAssertNotEqual(outArg, star)
        XCTAssertNotEqual(inArg, star)

        // Same variant with same value is equal
        XCTAssertEqual(TypeArgRef.invariant(typeRef), invariant)
        XCTAssertEqual(TypeArgRef.out(typeRef), outArg)
        XCTAssertEqual(TypeArgRef.in(typeRef), inArg)
        XCTAssertEqual(TypeArgRef.star, star)
    }
}
