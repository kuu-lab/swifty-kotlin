@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PlatformUnitTests {
    @Test
    func unitJavaBoundariesAreAcceptedAndCheckedSelectively() throws {
        let ctx = makeContextFromSource("""
        import java.util.LinkedList
        fun tail(q: LinkedList<Unit>): Unit = q.peekLast()
        fun take(value: Unit) {}
        fun <T> identity(value: T): T = value
        fun main() {
            val q = LinkedList<Unit>(); q.add(Unit)
            val local: Unit = q.peekLast()
            val nullable: Unit? = q.peekLast()
            take(q.peekLast())
            take(local)
            identity(local)
            println(q.peekLast())
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let assertions = sema.bindings.platformNullAssertionTypes.filter { isUserSourceExpr($0.key, in: ctx) }
        #expect(assertions.count == 2)
        #expect(assertions.values.allSatisfy { $0 == sema.types.unitType })
        #expect(sema.bindings.unitReturnCoercionExprs.filter { isUserSourceExpr($0, in: ctx) }.count == 1)
    }

    @Test
    func platformUnitRetainsFlexibleBoundsAndSubstitution() {
        let types = TypeSystem()
        let platform = types.withNullability(.platformType, for: types.unitType)
        let nullable = types.makeNullable(types.unitType)
        #expect(platform != nullable)
        #expect(types.nullability(of: platform) == .platformType)
        #expect(!types.isDefinitelyNonNull(platform))
        #expect(types.makeNonNullable(platform) == types.unitType)
        #expect(types.makeNullable(platform) == nullable)
        #expect(types.withNullability(.platformType, for: nullable) == platform)
        #expect(types.isSubtype(platform, types.unitType))
        #expect(types.isSubtype(platform, nullable))
        #expect(types.isSubtype(platform, types.anyType))
        #expect(types.isSubtype(types.unitType, platform))
        #expect(types.isSubtype(nullable, platform))
        #expect(types.isSubtype(types.nullableNothingType, platform))
        #expect(!types.isSubtype(nullable, types.unitType))
        #expect(!types.isSubtype(types.intType, platform))
        #expect(!types.isSubtype(platform, types.intType))
        #expect(types.renderType(platform) == "Unit!")
        let parameter = SymbolID(rawValue: 100)
        let variable = TypeVarID(rawValue: 0)
        let flexible = types.make(.typeParam(TypeParamType(symbol: parameter, nullability: .platformType)))
        #expect(types.substituteTypeParameters(in: flexible, substitution: [variable: types.unitType],
                                              typeVarBySymbol: [parameter: variable]) == platform)
        #expect(types.substituteTypeParameters(in: flexible, substitution: [variable: nullable],
                                              typeVarBySymbol: [parameter: variable]) == nullable)
    }

    @Test
    func unitMetadataRetainsPlatformWithoutChangingABI() throws {
        let types = TypeSystem()
        let symbols = SymbolTable()
        let interner = StringInterner()
        let name = interner.intern("platformUnit")
        let function = symbols.define(kind: .function, name: name, fqName: [name],
                                      declSite: nil, visibility: .public)
        let platform = types.withNullability(.platformType, for: types.unitType)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: [], returnType: platform), for: function)
        let symbol = try #require(symbols.symbol(function))
        #expect(NameMangler().mangledSignature(for: symbol, symbols: symbols, types: types) == "F0<Q<U>>")
        let records = MetadataEncoder().buildRecords(symbols: symbols, types: types,
            moduleName: "UnitContract", interner: interner, functionLinkNames: [:])
        let token = try #require(records.first { $0.fqName == "platformUnit" }?.typeSignature)
        #expect(token == "F0<P<U>>")
        let imported = try #require(DataFlowSemaPhase().decodeImportedTypeSignature(
            token: token, symbols: symbols, types: types, interner: interner,
            diagnostics: DiagnosticEngine(), metadataPath: "unit.kklib", ownerFQName: [name]
        ))
        guard case let .functionType(signature) = types.kind(of: imported) else {
            Issue.record("Expected imported callable type")
            return
        }
        #expect(signature.returnType == platform)
        #expect(types.displayName(of: platform, symbols: symbols, interner: interner) == "Unit!")
    }
}
