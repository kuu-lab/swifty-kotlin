@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibIrModuleTests {
    private static var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/demo.klib")
            .path
    }

    private static func openFixture() throws -> KlibIrModule? {
        guard FileManager.default.fileExists(atPath: fixturePath) else { return nil }
        return try KlibIrModule(container: KlibContainer(path: fixturePath))
    }

    @Test
    func readsFileAndStringTables() throws {
        guard let module = try Self.openFixture() else { return }
        #expect(module.hasIR)
        #expect(module.fileCount == 1)

        let file = try module.file(0)
        #expect(try module.fqName(file.fqName, fileIndex: 0) == "demo")
        // demo.kt declares `add` and `Greeter` at top level.
        #expect(file.declarationIds.count == 2)
    }

    @Test
    func decodesTopLevelDeclarations() throws {
        guard let module = try Self.openFixture() else { return }
        let declarations = try module.declarations(fileIndex: 0)
        #expect(declarations.count == 2)

        var functionNames: [String] = []
        var classNames: [String] = []
        for declaration in declarations {
            switch declaration {
            case .function(let function):
                functionNames.append(try module.string(function.base.nameType.nameIndex, fileIndex: 0))
                #expect(function.base.base.symbol.kind == .function)
                // `add` has a serialized body.
                #expect(function.base.bodyIndex != nil)
            case .class(let cls):
                classNames.append(try module.string(cls.nameIndex, fileIndex: 0))
                #expect(cls.base.symbol.kind == .class)
            default:
                Issue.record("unexpected declaration: \(declaration)")
            }
        }
        #expect(functionNames == ["add"])
        #expect(classNames == ["Greeter"])
    }

    @Test
    func decodesClassMembers() throws {
        guard let module = try Self.openFixture() else { return }
        let declarations = try module.declarations(fileIndex: 0)
        guard case .class(let cls) = declarations.first(where: {
            if case .class = $0 { return true }
            return false
        }) else {
            Issue.record("no class declaration")
            return
        }

        var memberNames: [String] = []
        var sawConstructor = false
        var sawProperty = false
        for member in cls.declarations {
            switch member {
            case .function(let function):
                memberNames.append(try module.string(function.base.nameType.nameIndex, fileIndex: 0))
            case .constructor:
                sawConstructor = true
            case .property:
                sawProperty = true
            default:
                break
            }
        }
        #expect(memberNames.contains("greet"))
        #expect(sawConstructor)
        // `val name` in the primary constructor.
        #expect(sawProperty)
    }

    @Test
    func decodesFunctionBody() throws {
        guard let module = try Self.openFixture() else { return }
        let declarations = try module.declarations(fileIndex: 0)
        guard case .function(let function) = declarations.first(where: {
            guard case .function = $0 else { return false }
            return true
        }), let bodyIndex = function.base.bodyIndex else {
            Issue.record("no function with a body")
            return
        }

        let body = try module.body(bodyIndex, fileIndex: 0)
        guard case .blockBody(let statements) = body.kind else {
            Issue.record("expected blockBody, got \(body.kind)")
            return
        }
        #expect(!statements.isEmpty)
    }

    @Test
    func resolvesSignaturesToReadableNames() throws {
        guard let module = try Self.openFixture() else { return }
        let declarations = try module.declarations(fileIndex: 0)
        guard case .function(let function) = declarations.first(where: {
            guard case .function = $0 else { return false }
            return true
        }) else {
            Issue.record("no function declaration")
            return
        }
        let signature = try module.signature(function.base.base.symbol.signatureIndex, fileIndex: 0)
        let description = try module.signatureDescription(signature, fileIndex: 0)
        #expect(description.hasPrefix("demo/add"))
    }

    @Test
    func dumpCoversFileAndDeclarations() throws {
        guard let module = try Self.openFixture() else { return }
        let text = try KlibIrDump.dump(module)
        #expect(text.contains("package demo"))
        #expect(text.contains("fun add"))
        #expect(text.contains("class Greeter"))
        #expect(text.contains("greet"))
    }

    @Test
    func handlesKlibWithoutIr() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).klib")
        try fm.createDirectory(at: root.appendingPathComponent("default"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "unique_name=noir\nabi_version=2.3.0\nir_signature_versions=1\n".write(
            to: root.appendingPathComponent("default/manifest"), atomically: true, encoding: .utf8
        )

        let module = try KlibIrModule(container: KlibContainer(path: root.path))
        #expect(!module.hasIR)
        #expect(module.fileCount == 0)
        #expect(throws: KlibFormatError.self) {
            _ = try module.declarations(fileIndex: 0)
        }
    }

    @Test
    func decodesBinarySymbolAndLatticeHelpers() {
        // symbol = (signatureId << 8) | kind
        let code: Int64 = (123 << 8) | Int64(KlibSymbolKind.function.rawValue)
        let ref = KlibSymbolRef(code)
        #expect(ref?.signatureIndex == 123)
        #expect(ref?.kind == .function)
        #expect(KlibSymbolRef((1 << 8) | 200) == nil) // invalid kind

        // name_type lattice: encode (17, 5) with the Kotlin interleave
        // algorithm, then decode back.
        let encoded = Self.interleave(17) | (Self.interleave(5) << 1)
        let pair = KlibBinaryEncoding.decodeNameAndType(Int64(bitPattern: encoded))
        #expect(pair.nameIndex == 17)
        #expect(pair.typeIndex == 5)
    }

    /// Mirrors Kotlin `BinaryLattice.interleaveBits` for test round-trips.
    private static func interleave(_ input: Int32) -> UInt64 {
        var word = UInt64(UInt32(bitPattern: input))
        word = (word ^ (word << 16)) & 0x0000_FFFF_0000_FFFF
        word = (word ^ (word << 8)) & 0x00FF_00FF_00FF_00FF
        word = (word ^ (word << 4)) & 0x0F0F_0F0F_0F0F_0F0F
        word = (word ^ (word << 2)) & 0x3333_3333_3333_3333
        word = (word ^ (word << 1)) & 0x5555_5555_5555_5555
        return word
    }
}
