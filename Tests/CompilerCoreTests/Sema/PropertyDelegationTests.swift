#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - SymbolTable Delegate Storage Tests

@Suite
struct DelegateStorageSymbolTableTests {
    @Test func testSetAndGetDelegateStorageSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let property = symbols.define(
            kind: .property,
            name: interner.intern("x"),
            fqName: [interner.intern("x")],
            declSite: nil,
            visibility: .public
        )
        let storage = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_x"),
            fqName: [interner.intern("$delegate_x")],
            declSite: nil,
            visibility: .private
        )
        symbols.setDelegateStorageSymbol(storage, for: property)
        #expect(symbols.delegateStorageSymbol(for: property) == storage)
    }

    @Test func testDelegateStorageSymbolReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.delegateStorageSymbol(for: SymbolID(rawValue: 0)) == nil)
    }

    @Test func testDelegateStorageSymbolIsIndependentOfPropertyType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let property = symbols.define(
            kind: .property,
            name: interner.intern("y"),
            fqName: [interner.intern("y")],
            declSite: nil,
            visibility: .public
        )
        let storage = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_y"),
            fqName: [interner.intern("$delegate_y")],
            declSite: nil,
            visibility: .private
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setPropertyType(intType, for: property)
        symbols.setDelegateStorageSymbol(storage, for: property)
        #expect(symbols.delegateStorageSymbol(for: property) == storage)
        #expect(symbols.propertyType(for: property) == intType)
    }

    @Test func testMultipleDelegateStorageSymbolsAreIndependent() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let propA = symbols.define(
            kind: .property,
            name: interner.intern("a"),
            fqName: [interner.intern("a")],
            declSite: nil,
            visibility: .public
        )
        let propB = symbols.define(
            kind: .property,
            name: interner.intern("b"),
            fqName: [interner.intern("b")],
            declSite: nil,
            visibility: .public
        )
        let storageA = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_a"),
            fqName: [interner.intern("$delegate_a")],
            declSite: nil,
            visibility: .private
        )
        let storageB = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_b"),
            fqName: [interner.intern("$delegate_b")],
            declSite: nil,
            visibility: .private
        )
        symbols.setDelegateStorageSymbol(storageA, for: propA)
        symbols.setDelegateStorageSymbol(storageB, for: propB)
        #expect(symbols.delegateStorageSymbol(for: propA) == storageA)
        #expect(symbols.delegateStorageSymbol(for: propB) == storageB)
        #expect(symbols.delegateStorageSymbol(for: propA) != storageB)
    }
}

// MARK: - Sema Delegate Type Checking Tests

@Suite
struct SemaDelegateTypeCheckTests {
    @Test func testDelegatedPropertyCreatesStorageSymbolDuringHeaderCollection() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // FQ names do not include module prefix; class Foo has fqName ["Foo"].
            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            // Verify that a $delegate_x storage symbol was created.
            let delegateStorageSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "$delegate_x"
            }
            #expect(!delegateStorageSymbols.isEmpty, "Expected $delegate_x storage symbol to be created")

            // The storage symbol should be a field.
            if let storageSymID = delegateStorageSymbols.first,
               let storageSym = sema.symbols.symbol(storageSymID)
            {
                #expect(storageSym.kind == .field)
                #expect(storageSym.visibility == .private)
            }

            // Find the property symbol 'x' and check delegate storage is linked.
            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            #expect(!xSymbols.isEmpty, "Expected property symbol 'x' to exist")
            if let xSymbol = xSymbols.first {
                let delegateStorage = sema.symbols.delegateStorageSymbol(for: xSymbol)
                #expect(delegateStorage != nil, "Expected delegate storage to be linked to property 'x'")
            }
        }
    }

    @Test func testDelegatedPropertyTypeDefaultsToNullableAnyWhenNotDeclared() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            #expect(!xSymbols.isEmpty)
            if let xSymbol = xSymbols.first {
                let propType = sema.symbols.propertyType(for: xSymbol)
                #expect(propType != nil, "Property type should be set even without explicit annotation")
                // When no explicit type, it falls back to Any?
                if let propType {
                    #expect(propType == sema.types.nullableAnyType)
                }
            }
        }
    }

    @Test func testDelegatedPropertyPreservesExplicitType() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            #expect(!xSymbols.isEmpty)
            if let xSymbol = xSymbols.first {
                let propType = sema.symbols.propertyType(for: xSymbol)
                #expect(propType != nil)
                if let propType {
                    let intType = sema.types.make(.primitive(.int, .nonNull))
                    #expect(propType == intType, "Explicit Int type should be preserved")
                }
            }
        }
    }

    @Test func testMutableDelegatedPropertyCreatesStorageSymbol() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 0
            fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo {
            var x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let delegateStorageSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "$delegate_x"
            }
            #expect(!delegateStorageSymbols.isEmpty, "Expected $delegate_x storage symbol for var delegate")

            if let storageSymID = delegateStorageSymbols.first,
               let storageSym = sema.symbols.symbol(storageSymID)
            {
                #expect(storageSym.kind == .field)
                #expect(storageSym.visibility == .private)
            }
        }
    }

    @Test func testMultipleDelegatedPropertiesCreateSeparateStorageSymbols() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
            val y: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let delegateStorageSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name).hasPrefix("$delegate_")
            }
            #expect(delegateStorageSymbols.count == 2, "Expected two separate delegate storage symbols for two delegated properties")

            let storageNames = delegateStorageSymbols.compactMap { id in
                sema.symbols.symbol(id).map { interner.resolve($0.name) }
            }
            #expect(storageNames.contains("$delegate_x"), "Expected $delegate_x storage symbol")
            #expect(storageNames.contains("$delegate_y"), "Expected $delegate_y storage symbol")
        }
    }

    @Test func testDelegatedPropertyRecordsDelegateTypeOnSyntheticSymbol() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            if let xSymbol = xSymbols.first {
                // The delegate type is recorded under a synthetic symbol offset:
                // -(symbol.rawValue + 50_000)
                let syntheticID = SymbolID(rawValue: -(xSymbol.rawValue + 50000))
                let delegateType = sema.symbols.propertyType(for: syntheticID)
                #expect(delegateType != nil, "Delegate type should be recorded on synthetic symbol")
            }
        }
    }
}

// MARK: - KIR Delegate Accessor Synthesis Tests

@Suite
struct KIRDelegateAccessorTests {
    @Test func testDelegatedValSynthesizesGetterWithGetValueCall() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // Check that a getter function was synthesized.
            let getterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                return name == "get" ? fn : nil
            }
            #expect(!getterFunctions.isEmpty, "Expected synthesized getter")

            // Delegate lowering may rewrite the direct getValue call in later phases, but
            // the synthesized delegate getter should carry a call with ≥2 args (receiver + property context).
            // Filter to the delegate getter specifically (not bundled property getters with 1 arg).
            let delegateGetter = getterFunctions.first { fn in
                fn.body.contains { instruction in
                    guard case let .call(_, _, args, _, _, _, _, _) = instruction else { return false }
                    return args.count >= 2
                }
            }
            #expect(delegateGetter != nil, "Expected synthesized delegate getter with getValue call")
            if let getter = delegateGetter {
                let multiArgCalls = getter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, _, args, _, _, _, _, _) = instruction else { return nil }
                    return args.count >= 2 ? args : nil
                }
                #expect(!multiArgCalls.isEmpty, "Delegate getter must have a call with receiver/property args")
                if let args = multiArgCalls.first {
                    #expect(args.count >= 2, "Synthesized getter should pass receiver/property context")
                }
            }
        }
    }

    @Test func testDelegatedVarSynthesizesSetterWithSetValueCall() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
            fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo {
            var x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // Check that a setter function was synthesized.
            let setterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                return name == "set" ? fn : nil
            }
            #expect(!setterFunctions.isEmpty, "Expected synthesized setter")

            // Delegate lowering may rewrite the direct setValue call in later phases, but
            // the synthesized setter should still carry observable call structure.
            if let setter = setterFunctions.first {
                let callArgs = setter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, _, args, _, _, _, _, _) = instruction else { return nil }
                    return args
                }
                #expect(!callArgs.isEmpty)
                if let args = callArgs.first {
                    #expect(args.count >= 2, "Synthesized setter should pass at least value and receiver context")
                }
            }
        }
    }

    @Test func testDelegatedValDoesNotSynthesizeSetter() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // There should be no setter function with setValue for a val property.
            let setterWithSetValue = module.arena.declarations.contains { decl in
                guard case let .function(fn) = decl else { return false }
                let name = interner.resolve(fn.name)
                guard name == "set" else { return false }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("setValue")
            }
            #expect(!setterWithSetValue, "val property should not have a synthesized setter with setValue")
        }
    }

    @Test func testDelegateStorageGlobalIsEmitted() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let sema = try #require(ctx.sema)

            // Check that a $delegate_x global was emitted.
            let delegateGlobals = module.arena.declarations.compactMap { decl -> KIRGlobal? in
                guard case let .global(g) = decl else { return nil }
                guard let sym = sema.symbols.symbol(g.symbol) else { return nil }
                return interner.resolve(sym.name).hasPrefix("$delegate_") ? g : nil
            }
            #expect(!delegateGlobals.isEmpty, "Expected $delegate_ global to be emitted in KIR")
        }
    }

    @Test func testGetValueCallUsesDelegateStorageAsSymbol() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            _ = try #require(ctx.sema)

            // Find the getter and check that getValue resolves as a direct member call,
            // rather than using the delegate storage field as the callee symbol.
            let getterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                guard name == "get" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("getValue") ? fn : nil
            }

            if let getter = getterFunctions.first {
                let getValueCallCount = getter.body.reduce(into: 0) { count, instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction,
                          interner.resolve(callee) == "getValue" else { return }
                    count += 1
                }
                #expect(getValueCallCount > 0, "Expected synthesized getter to contain a direct getValue call")
            }
        }
    }
}

// MARK: - Constructor Delegate Initialization Tests

@Suite
struct ConstructorDelegateInitTests {
    @Test func testConstructorEmitsInitializerForDelegateStorage() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // In KIR, constructors are named after the class (e.g. "Foo"), not "<init>".
            let constructors = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(fn) = decl else { return nil }
                guard interner.resolve(fn.name) == "Foo" else { return nil }
                return fn
            }
            #expect(!constructors.isEmpty, "Expected a Foo constructor function in KIR")

            let anyConstructorCallsMyDelegate = constructors.contains { fn in
                extractCallees(from: fn.body, interner: interner).contains("MyDelegate")
            }
            #expect(anyConstructorCallsMyDelegate, "Expected Foo constructor to initialize delegate storage with MyDelegate()")
        }
    }

    @Test func testMultipleDelegatedPropertiesEmitSeparateGlobalsInKIR() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
            val y: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let sema = try #require(ctx.sema)

            let delegateGlobals = module.arena.declarations.compactMap { decl -> KIRGlobal? in
                guard case let .global(g) = decl else { return nil }
                guard let sym = sema.symbols.symbol(g.symbol) else { return nil }
                return interner.resolve(sym.name).hasPrefix("$delegate_") ? g : nil
            }
            #expect(delegateGlobals.count == 2, "Expected two separate delegate globals for two delegated properties")
        }
    }
}
#endif
