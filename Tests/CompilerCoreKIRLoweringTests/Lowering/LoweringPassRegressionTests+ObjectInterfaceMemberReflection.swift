#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    // KUU-4065: `memberProperties`/`memberFunctions`/`members` on `object`
    // and `interface` KClass values were empty — the member half of the
    // reflection initializer only ran for `class` declarations. The same
    // `__ctor_reflect_init_*` initializer is now emitted for object and
    // interface owners too (member registration only — they declare no
    // `<init>` symbols, so no `__kk_kconstructor_create` calls appear), and
    // interface initializers also register a `-> kotlin.Any` typeParents
    // edge so the inherited-member BFS reaches Any's `equals`/`hashCode`/
    // `toString` handles like kotlin-reflect reports.
    @Test
    func objectAndInterfaceOwnersEmitMemberReflectionRegistration() throws {
        let source = """
            object O { var y: String = ""; fun g(): Int = 1 }
            interface IBase { fun baseFun() }
            interface I : IBase { var x: Int; fun f() }
            class Outer {
                object NestedObj { val p: Int = 1 }
                interface NestedIface { val q: Int }
            }
            fun main() {}
            """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, moduleName: "ObjIfaceMembers", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)

            let memberRegisterName = ctx.interner.intern("__kk_kclass_register_member")
            let ctorCreateName = ctx.interner.intern("__kk_kconstructor_create")
            let registerSuperName = ctx.interner.intern("kk_type_register_super")
            let registerIfaceName = ctx.interner.intern("kk_type_register_iface")
            let anySymbol = try #require(sema.types.anyClassSymbol)
            let anyNominalID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: anySymbol,
                sema: sema,
                interner: ctx.interner
            )
            let ibaseNominalID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("IBase"),
                ])),
                sema: sema,
                interner: ctx.interner
            )

            // `__ctor_reflect_init_<ownerRaw>` -> (memberRegisterCalls,
            // ctorCreateCalls, superEdgeTargetTypeIDs, ifaceEdgeTargetTypeIDs)
            var memberCallsByOwner: [SymbolID: Int] = [:]
            var ctorCallsByOwner: [SymbolID: Int] = [:]
            var superTargetsByOwner: [SymbolID: [Int64]] = [:]
            var ifaceTargetsByOwner: [SymbolID: [Int64]] = [:]
            for declaration in module.arena.declarations {
                guard case let .function(function) = declaration,
                      ctx.interner.resolve(function.name).hasPrefix("__ctor_reflect_init_")
                else { continue }
                let rawSuffix = ctx.interner.resolve(function.name)
                    .split(separator: "_").last.flatMap { Int32($0) }
                let ownerSymbol = try #require(rawSuffix.map { SymbolID(rawValue: $0) })
                var literalByExpr: [KIRExprID: Int64] = [:]
                for instruction in function.body {
                    guard case let .constValue(result, .intLiteral(value)) = instruction
                    else { continue }
                    literalByExpr[result] = value
                }
                for instruction in function.body {
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction
                    else { continue }
                    switch callee {
                    case memberRegisterName:
                        memberCallsByOwner[ownerSymbol, default: 0] += 1
                    case ctorCreateName:
                        ctorCallsByOwner[ownerSymbol, default: 0] += 1
                    case registerSuperName:
                        let target = arguments.dropFirst().first.flatMap { literalByExpr[$0] }
                        superTargetsByOwner[ownerSymbol, default: []]
                            .append(target ?? -1)
                    case registerIfaceName:
                        let target = arguments.dropFirst().first.flatMap { literalByExpr[$0] }
                        ifaceTargetsByOwner[ownerSymbol, default: []]
                            .append(target ?? -1)
                    default:
                        break
                    }
                }
            }

            func ownerSymbol(named name: String) throws -> SymbolID {
                let interned = ctx.interner.intern(name)
                let symbol = try #require(Set(memberCallsByOwner.keys)
                    .union(ctorCallsByOwner.keys)
                    .union(superTargetsByOwner.keys)
                    .union(ifaceTargetsByOwner.keys)
                    .first { sema.symbols.symbol($0)?.name == interned })
                return symbol
            }

            // Every nominal owner got a reflection initializer.
            let objectO = try ownerSymbol(named: "O")
            let interfaceI = try ownerSymbol(named: "I")
            let nestedObj = try ownerSymbol(named: "NestedObj")
            let nestedIface = try ownerSymbol(named: "NestedIface")

            // Member handles are registered on each owner's KClass box:
            // O has `y` + `g`; I has `x` + `f`; each nested decl its member.
            #expect(sema.symbols.symbol(objectO)?.kind == .object)
            #expect(memberCallsByOwner[objectO] == 2)
            #expect(sema.symbols.symbol(interfaceI)?.kind == .interface)
            #expect(memberCallsByOwner[interfaceI] == 2)
            #expect(memberCallsByOwner[nestedObj] == 1)
            #expect(memberCallsByOwner[nestedIface] == 1)

            // Objects/interfaces declare no constructors — the ctor half of
            // the initializer is a no-op for them.
            #expect(ctorCallsByOwner[objectO] == nil)
            #expect(ctorCallsByOwner[interfaceI] == nil)
            #expect(ctorCallsByOwner[nestedObj] == nil)
            #expect(ctorCallsByOwner[nestedIface] == nil)

            // Interfaces register their declared-super edges plus a direct
            // kotlin.Any edge (interfaces never list Any in
            // `directSupertypes`, so the inherited-member BFS could not reach
            // the Any handles without it).
            #expect(superTargetsByOwner[interfaceI]?.contains(anyNominalID) == true)
            #expect(ifaceTargetsByOwner[interfaceI]?.contains(ibaseNominalID) == true)
            #expect(superTargetsByOwner[nestedIface]?.contains(anyNominalID) == true)
        }
    }
}
#endif
