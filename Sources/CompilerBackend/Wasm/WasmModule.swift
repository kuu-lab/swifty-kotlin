// WasmModule.swift — minimal WebAssembly binary encoder used by the wasm
// backend. Only what the KIR lowering needs: i64/i32 value types, function
// imports, one funcref table, one memory, mutable globals, exports, active
// element/data segments, and a name custom section for debuggability.

import Foundation

enum WasmValType: UInt8 {
    case i64 = 0x7E
    case i32 = 0x7F
    case f32 = 0x7D
    case f64 = 0x7C
    case funcref = 0x70
    case externref = 0x6F
}

struct WasmFuncType: Hashable {
    var params: [WasmValType]
    var results: [WasmValType]

    static func i64Signature(_ parameterCount: Int) -> WasmFuncType {
        WasmFuncType(params: Array(repeating: .i64, count: parameterCount), results: [.i64])
    }
}

enum WasmExternalKind: UInt8 {
    case function = 0x00
    case table = 0x01
    case memory = 0x02
    case global = 0x03
}

enum WasmOpcode {
    static let unreachable: UInt8 = 0x00
    static let nop: UInt8 = 0x01
    static let block: UInt8 = 0x02
    static let loop: UInt8 = 0x03
    static let `if`: UInt8 = 0x04
    static let `else`: UInt8 = 0x05
    static let end: UInt8 = 0x0B
    static let br: UInt8 = 0x0C
    static let brIf: UInt8 = 0x0D
    static let `return`: UInt8 = 0x0F
    static let call: UInt8 = 0x10
    static let callIndirect: UInt8 = 0x11
    static let drop: UInt8 = 0x1A
    static let localGet: UInt8 = 0x20
    static let localSet: UInt8 = 0x21
    static let localTee: UInt8 = 0x22
    static let globalGet: UInt8 = 0x23
    static let globalSet: UInt8 = 0x24
    static let i32Load: UInt8 = 0x28
    static let i64Load: UInt8 = 0x29
    static let i32Store: UInt8 = 0x36
    static let i64Store: UInt8 = 0x37
    static let memorySize: UInt8 = 0x3F
    static let memoryGrow: UInt8 = 0x40
    static let i32Const: UInt8 = 0x41
    static let i64Const: UInt8 = 0x42
    static let i32Eqz: UInt8 = 0x45
    static let i32Eq: UInt8 = 0x46
    static let i32And: UInt8 = 0x71
    static let i32Or: UInt8 = 0x72
    static let i64Eqz: UInt8 = 0x50
    static let i64Eq: UInt8 = 0x51
    static let i64Ne: UInt8 = 0x52
    static let i64LtS: UInt8 = 0x53
    static let i64LtU: UInt8 = 0x54
    static let i64GtS: UInt8 = 0x55
    static let i64GtU: UInt8 = 0x56
    static let i64LeS: UInt8 = 0x57
    static let i64LeU: UInt8 = 0x58
    static let i64GeS: UInt8 = 0x59
    static let i64GeU: UInt8 = 0x5A
    static let i64Add: UInt8 = 0x7C
    static let i64Sub: UInt8 = 0x7D
    static let i64Mul: UInt8 = 0x7E
    static let i64DivS: UInt8 = 0x7F
    static let i64DivU: UInt8 = 0x80
    static let i64RemS: UInt8 = 0x81
    static let i64RemU: UInt8 = 0x82
    static let i64And: UInt8 = 0x83
    static let i64Or: UInt8 = 0x84
    static let i64Xor: UInt8 = 0x85
    static let i64Shl: UInt8 = 0x86
    static let i64ShrS: UInt8 = 0x87
    static let i64ShrU: UInt8 = 0x88
    static let i32Add: UInt8 = 0x6A
    static let i32Sub: UInt8 = 0x6B
    static let i32Mul: UInt8 = 0x6C
    static let i32WrapI64: UInt8 = 0xA7
    static let i64ExtendI32S: UInt8 = 0xAC
    static let i64ExtendI32U: UInt8 = 0xAD
    static let blockVoid: UInt8 = 0x40
}

/// Byte-sink for a single wasm function body. Each helper appends one
/// instruction; structured constructs are opened/closed explicitly so the
/// emitter can interleave them with flat KIR positions.
struct WasmCode {
    var bytes: [UInt8] = []

    mutating func op(_ opcode: UInt8) { bytes.append(opcode) }
    mutating func append(_ other: WasmCode) { bytes.append(contentsOf: other.bytes) }

    mutating func u(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while v != 0
    }

    mutating func s(_ value: Int64) {
        var v = value
        while true {
            let byte = UInt8(v & 0x7F)
            v >>= 7
            if (v == 0 && byte & 0x40 == 0) || (v == -1 && byte & 0x40 != 0) {
                bytes.append(byte)
                return
            }
            bytes.append(byte | 0x80)
        }
    }

    mutating func localGet(_ index: Int) { op(WasmOpcode.localGet); u(UInt64(index)) }
    mutating func localSet(_ index: Int) { op(WasmOpcode.localSet); u(UInt64(index)) }
    mutating func localTee(_ index: Int) { op(WasmOpcode.localTee); u(UInt64(index)) }
    mutating func globalGet(_ index: Int) { op(WasmOpcode.globalGet); u(UInt64(index)) }
    mutating func globalSet(_ index: Int) { op(WasmOpcode.globalSet); u(UInt64(index)) }
    mutating func i64Const(_ value: Int64) { op(WasmOpcode.i64Const); s(value) }
    mutating func i32Const(_ value: Int32) { op(WasmOpcode.i32Const); s(Int64(value)) }
    mutating func call(_ index: Int) { op(WasmOpcode.call); u(UInt64(index)) }
    mutating func callIndirect(_ typeIndex: Int) {
        op(WasmOpcode.callIndirect); u(UInt64(typeIndex)); u(0)
    }
    mutating func i64Load(offset: UInt64, align: UInt64 = 0) {
        op(WasmOpcode.i64Load); u(align); u(offset)
    }
    mutating func i64Store(offset: UInt64, align: UInt64 = 0) {
        op(WasmOpcode.i64Store); u(align); u(offset)
    }
    mutating func i32Store(offset: UInt64 = 0, align: UInt64 = 0) {
        op(WasmOpcode.i32Store); u(align); u(offset)
    }
    mutating func i32Load8U(offset: UInt64 = 0) {
        op(0x2D); u(0); u(offset)
    }
    mutating func i32Store8(offset: UInt64 = 0) {
        op(0x3A); u(0); u(offset)
    }
    mutating func br(_ depth: Int) { op(WasmOpcode.br); u(UInt64(depth)) }
    mutating func brIf(_ depth: Int) { op(WasmOpcode.brIf); u(UInt64(depth)) }
    mutating func openBlock() { op(WasmOpcode.block); op(WasmOpcode.blockVoid) }
    mutating func openLoop() { op(WasmOpcode.loop); op(WasmOpcode.blockVoid) }
    /// Convert an i64 on the stack to the i32 truthiness `if`/`br_if` require.
    mutating func i64Truthy() {
        i64Const(0)
        op(WasmOpcode.i64Ne)
    }

    mutating func openIf() { op(WasmOpcode.if); op(WasmOpcode.blockVoid) }
    mutating func openIf(result: WasmValType) { op(WasmOpcode.if); op(result.rawValue) }
    mutating func elseBranch() { op(WasmOpcode.else) }
    mutating func end() { op(WasmOpcode.end) }
    mutating func i64ExtendFromComparison() { op(WasmOpcode.i64ExtendI32U) }
}

private func wasmEncodeName(_ string: String) -> [UInt8] {
    var out: [UInt8] = []
    let bytes = Array(string.utf8)
    var v = UInt64(bytes.count)
    repeat {
        var byte = UInt8(v & 0x7F)
        v >>= 7
        if v != 0 { byte |= 0x80 }
        out.append(byte)
    } while v != 0
    out.append(contentsOf: bytes)
    return out
}

/// Accumulates module sections; `encode()` serializes the full binary once all
/// declarations and bodies are known.
final class WasmModule {
    private var types: [WasmFuncType] = []
    private var typeIndexByType: [WasmFuncType: Int] = [:]
    private var imports: [(module: String, name: String, typeIndex: Int)] = []
    private var functionEntries: [(typeIndex: Int, name: String)] = []
    private var bodyByLocalFunctionIndex: [Int: [UInt8]] = [:]
    private var globals: [(mutable: Bool, initValue: Int64, name: String)] = []
    private var exports: [(name: String, kind: WasmExternalKind, index: Int)] = []
    private var tableFunctions: [Int] = []
    private var tableSlotByFunction: [Int: Int] = [:]
    private var dataSegments: [(offset: Int64, bytes: [UInt8])] = []

    var exportMemoryName: String?
    var memoryMinPages: Int = 1

    var functionCount: Int { imports.count + functionEntries.count }

    func funcTypeIndex(_ type: WasmFuncType) -> Int {
        if let existing = typeIndexByType[type] { return existing }
        let index = types.count
        types.append(type)
        typeIndexByType[type] = index
        return index
    }

    func addImportFunction(module: String, name: String, type: WasmFuncType) -> Int {
        let index = imports.count
        imports.append((module, name, funcTypeIndex(type)))
        return index
    }

    func addFunction(type: WasmFuncType, name: String) -> Int {
        let index = imports.count + functionEntries.count
        functionEntries.append((funcTypeIndex(type), name))
        return index
    }

    func setBody(_ bytes: [UInt8], forFunctionIndex index: Int) {
        bodyByLocalFunctionIndex[index - imports.count] = bytes
    }

    func addGlobal(initialValue: Int64 = 0, name: String) -> Int {
        let index = globals.count
        globals.append((true, initialValue, name))
        return index
    }

    /// Patches a previously-declared global's initializer. Used for the heap
    /// base, which is only known once every data segment has been placed.
    func setGlobalInitialValue(index: Int, value: Int64) {
        globals[index].initValue = value
    }

    func addExport(name: String, kind: WasmExternalKind, index: Int) {
        exports.append((name, kind, index))
    }

    /// Registers `functionIndex` in the funcref element segment and returns its
    /// table slot. Function-reference values in KIR become these slot indices.
    func tableSlot(forFunction functionIndex: Int) -> Int {
        if let existing = tableSlotByFunction[functionIndex] { return existing }
        let slot = tableFunctions.count
        tableFunctions.append(functionIndex)
        tableSlotByFunction[functionIndex] = slot
        return slot
    }

    func addDataSegment(offset: Int64, bytes: [UInt8]) {
        dataSegments.append((offset, bytes))
    }

    func functionName(at index: Int) -> String {
        index < imports.count
            ? imports[index].name
            : functionEntries[index - imports.count].name
    }

    func encode() -> [UInt8] {
        var out: [UInt8] = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]

        func writeULEB(_ value: UInt64, to sink: inout [UInt8]) {
            var v = value
            repeat {
                var byte = UInt8(v & 0x7F)
                v >>= 7
                if v != 0 { byte |= 0x80 }
                sink.append(byte)
            } while v != 0
        }

        func writeSection(_ id: UInt8, payload: [UInt8]) {
            out.append(id)
            writeULEB(UInt64(payload.count), to: &out)
            out.append(contentsOf: payload)
        }

        // Type section (1)
        var typeSection: [UInt8] = []
        writeULEB(UInt64(types.count), to: &typeSection)
        for type in types {
            typeSection.append(0x60)
            writeULEB(UInt64(type.params.count), to: &typeSection)
            for param in type.params { typeSection.append(param.rawValue) }
            writeULEB(UInt64(type.results.count), to: &typeSection)
            for result in type.results { typeSection.append(result.rawValue) }
        }
        writeSection(1, payload: typeSection)

        // Import section (2)
        if !imports.isEmpty {
            var importSection: [UInt8] = []
            writeULEB(UInt64(imports.count), to: &importSection)
            for entry in imports {
                importSection.append(contentsOf: wasmEncodeName(entry.module))
                importSection.append(contentsOf: wasmEncodeName(entry.name))
                importSection.append(WasmExternalKind.function.rawValue)
                writeULEB(UInt64(entry.typeIndex), to: &importSection)
            }
            writeSection(2, payload: importSection)
        }

        // Function section (3)
        var functionSection: [UInt8] = []
        writeULEB(UInt64(functionEntries.count), to: &functionSection)
        for entry in functionEntries {
            writeULEB(UInt64(entry.typeIndex), to: &functionSection)
        }
        writeSection(3, payload: functionSection)

        // Table section (4): one funcref table sized to the element segment.
        var tableSection: [UInt8] = []
        writeULEB(1, to: &tableSection)
        tableSection.append(WasmValType.funcref.rawValue)
        tableSection.append(0x00) // limits: min only
        writeULEB(UInt64(max(tableFunctions.count, 1)), to: &tableSection)
        writeSection(4, payload: tableSection)

        // Memory section (5)
        var memorySection: [UInt8] = []
        writeULEB(1, to: &memorySection)
        memorySection.append(0x00)
        writeULEB(UInt64(memoryMinPages), to: &memorySection)
        writeSection(5, payload: memorySection)

        // Global section (6)
        if !globals.isEmpty {
            var globalSection: [UInt8] = []
            writeULEB(UInt64(globals.count), to: &globalSection)
            for global in globals {
                globalSection.append(WasmValType.i64.rawValue)
                globalSection.append(global.mutable ? 0x01 : 0x00)
                globalSection.append(WasmOpcode.i64Const)
                var code = WasmCode()
                code.s(global.initValue)
                globalSection.append(contentsOf: code.bytes)
                globalSection.append(WasmOpcode.end)
            }
            writeSection(6, payload: globalSection)
        }

        // Export section (7)
        var exportSection: [UInt8] = []
        writeULEB(UInt64(exports.count + (exportMemoryName == nil ? 0 : 1)), to: &exportSection)
        for entry in exports {
            exportSection.append(contentsOf: wasmEncodeName(entry.name))
            exportSection.append(entry.kind.rawValue)
            writeULEB(UInt64(entry.index), to: &exportSection)
        }
        if let memoryName = exportMemoryName {
            exportSection.append(contentsOf: wasmEncodeName(memoryName))
            exportSection.append(WasmExternalKind.memory.rawValue)
            writeULEB(0, to: &exportSection)
        }
        writeSection(7, payload: exportSection)

        // Element section (9): active funcref table at offset 0.
        if !tableFunctions.isEmpty {
            var elementSection: [UInt8] = []
            writeULEB(1, to: &elementSection)
            elementSection.append(0x00) // active, table 0, offset expr
            elementSection.append(WasmOpcode.i32Const)
            elementSection.append(0)
            elementSection.append(WasmOpcode.end)
            writeULEB(UInt64(tableFunctions.count), to: &elementSection)
            for index in tableFunctions {
                writeULEB(UInt64(index), to: &elementSection)
            }
            writeSection(9, payload: elementSection)
        }

        // Code section (10)
        var codeSection: [UInt8] = []
        writeULEB(UInt64(functionEntries.count), to: &codeSection)
        for index in functionEntries.indices {
            let body = bodyByLocalFunctionIndex[index] ?? [0x00, WasmOpcode.end]
            writeULEB(UInt64(body.count), to: &codeSection)
            codeSection.append(contentsOf: body)
        }
        writeSection(10, payload: codeSection)

        // Data section (11)
        if !dataSegments.isEmpty {
            var dataSection: [UInt8] = []
            writeULEB(UInt64(dataSegments.count), to: &dataSection)
            for segment in dataSegments {
                dataSection.append(0x00)
                dataSection.append(WasmOpcode.i32Const)
                var code = WasmCode()
                code.s(segment.offset)
                dataSection.append(contentsOf: code.bytes)
                dataSection.append(WasmOpcode.end)
                writeULEB(UInt64(segment.bytes.count), to: &dataSection)
                dataSection.append(contentsOf: segment.bytes)
            }
            writeSection(11, payload: dataSection)
        }

        // Name custom section for debugger readability.
        var nameSubsection: [UInt8] = []
        writeULEB(UInt64(functionCount), to: &nameSubsection)
        for index in 0..<functionCount {
            writeULEB(UInt64(index), to: &nameSubsection)
            nameSubsection.append(contentsOf: wasmEncodeName(functionName(at: index)))
        }
        var nameSection: [UInt8] = []
        nameSection.append(contentsOf: wasmEncodeName("name"))
        nameSection.append(0x01)
        writeULEB(UInt64(nameSubsection.count), to: &nameSection)
        nameSection.append(contentsOf: nameSubsection)
        out.append(0x00)
        writeULEB(UInt64(nameSection.count), to: &out)
        out.append(contentsOf: nameSection)

        return out
    }
}
