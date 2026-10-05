@testable import CompilerCore
import Testing

extension SymbolTableTests {
    @Test(arguments: [false, true])
    func testClassAndFactoryCoexistAndDuplicateClassReusesClassifier(factoryFirst: Bool) {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let name = interner.intern("Foo")
        let fqName = [interner.intern("dup"), name]
        func define(_ kind: SymbolKind) -> SymbolID {
            symbols.define(kind: kind, name: name, fqName: fqName, declSite: nil, visibility: .public)
        }
        let first = define(factoryFirst ? .function : .class)
        let second = define(factoryFirst ? .class : .function)
        let classifier = factoryFirst ? second : first
        #expect(first != second)
        #expect(define(.class) == classifier)
        #expect(symbols.lookupAll(fqName: fqName).count == 2)
    }
}
