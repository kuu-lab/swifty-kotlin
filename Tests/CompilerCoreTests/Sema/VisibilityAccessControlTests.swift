@testable import CompilerCore
import Foundation
import Testing

@Suite
struct VisibilityAccessControlTests {
    @Test
    func testPublicFunctionAccessibleWithinSameFile() throws {
        let source = """
        package test
        public fun greet(): Int = 1
        fun main(): Int = greet()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisPub")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0041", in: ctx)
        }
    }

    @Test
    func testInternalFunctionAccessibleWithinSameFile() throws {
        let source = """
        package test
        internal fun helper(): Int = 1
        fun main(): Int = helper()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisInternal")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
        }
    }

    @Test
    func testPrivateFunctionAccessibleWithinSameFile() throws {
        let source = """
        package test
        private fun secret(): Int = 42
        fun main(): Int = secret()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisPrivSame")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
        }
    }

    @Test
    func testPrivatePropertyAccessibleWithinSameFile() throws {
        let source = """
        package test
        private val secretVal: Int = 99
        fun main(): Int = secretVal
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "VisPrivPropSame")
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0040", in: ctx)
        }
    }

    private func defineSymbol(
        _ symbols: SymbolTable,
        interner: StringInterner,
        kind: SymbolKind,
        name: String,
        visibility: Visibility,
        file: FileID = FileID(rawValue: 0)
    ) -> SymbolID {
        let interned = interner.intern(name)
        return symbols.define(
            kind: kind,
            name: interned,
            fqName: [interned],
            declSite: makeRange(file: file),
            visibility: visibility,
            flags: []
        )
    }

    @Test
    func testVisibilityCheckerPublicAlwaysAccessible() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "pubFn", visibility: .public)
        let symbol = try #require(symbols.symbol(sym))
        #expect(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil))
    }

    @Test
    func testVisibilityCheckerInternalAlwaysAccessible() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "intFn", visibility: .internal)
        let symbol = try #require(symbols.symbol(sym))
        #expect(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil))
    }

    @Test
    func testVisibilityCheckerPrivateSameFile() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "privFn", visibility: .private, file: FileID(rawValue: 0))
        let symbol = try #require(symbols.symbol(sym))
        #expect(checker.isAccessible(symbol, fromFile: FileID(rawValue: 0), enclosingClass: nil))
    }

    @Test
    func testVisibilityCheckerPrivateDifferentFile() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "privFn2", visibility: .private, file: FileID(rawValue: 0))
        let symbol = try #require(symbols.symbol(sym))
        #expect(!(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil)))
    }

    @Test
    func testVisibilityCheckerProtectedInSameClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "MyClass", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protMethod", visibility: .protected)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try #require(symbols.symbol(memberSym))
        #expect(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: classSym))
    }

    @Test
    func testVisibilityCheckerProtectedOutsideClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "MyClass2", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protMethod2", visibility: .protected)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try #require(symbols.symbol(memberSym))
        #expect(!(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: nil)))
    }

    @Test
    func testVisibilityCheckerProtectedInSubclass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let baseSym = defineSymbol(symbols, interner: interner, kind: .class, name: "Base", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protSubMethod", visibility: .protected)
        symbols.setParentSymbol(baseSym, for: memberSym)
        let childSym = defineSymbol(symbols, interner: interner, kind: .class, name: "Child", visibility: .public)
        symbols.setDirectSupertypes([baseSym], for: childSym)
        let member = try #require(symbols.symbol(memberSym))
        #expect(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: childSym))
    }

    @Test
    func testVisibilityCheckerPrivateMemberInSameClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "PrivClass", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "privMethod", visibility: .private)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try #require(symbols.symbol(memberSym))
        #expect(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: classSym))
    }

    @Test
    func testVisibilityCheckerPrivateMemberOutsideClass() throws {
        let (_, symbols, _, interner) = makeSemaModule()
        let checker = VisibilityChecker(symbols: symbols)
        let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "OwnerClass", visibility: .public)
        let otherClassSym = defineSymbol(symbols, interner: interner, kind: .class, name: "OtherClass", visibility: .public)
        let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "privMethod2", visibility: .private)
        symbols.setParentSymbol(classSym, for: memberSym)
        let member = try #require(symbols.symbol(memberSym))
        #expect(!(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: otherClassSym)))
    }
}
