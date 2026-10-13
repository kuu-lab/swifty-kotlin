import Foundation
@testable import Runtime
import Testing

func runtimeTestStringValue(_ raw: Int) -> String {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
}

func runtimeTestMakeArray(_ elements: [Int]) -> Int {
    let arrayRaw = kk_array_new(elements.count)
    var thrown = 0
    for (index, element) in elements.enumerated() {
        _ = kk_array_set(arrayRaw, index, element, &thrown)
        #expect(thrown == 0)
    }
    return arrayRaw
}

func runtimeTestMakeList(_ elements: [Int]) -> Int {
    let arrayRaw = runtimeTestMakeArray(elements)
    return kk_list_of(arrayRaw, elements.count)
}

func makeByteArray(_ bytes: [Int]) -> Int {
    let array = kk_array_new(bytes.count)
    for (index, byte) in bytes.enumerated() {
        _ = kk_array_set(array, index, byte, nil)
    }
    return array
}

func makeByteArray(length: Int) -> Int {
    kk_array_new(length)
}

func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

// Mirrors RuntimeTypeCheckToken's encoding.
func nominalTypeToken(for fqName: String) -> Int {
    let nominalBase: Int64 = 6
    let payloadShift: Int64 = 9
    let typeID = runtimeStableNominalTypeID(fqName: fqName)
    return Int(nominalBase | (typeID << payloadShift))
}

func capturePrintln(_ block: () -> Void) -> String {
    let pipe = Pipe()
    let savedFD = dup(STDOUT_FILENO)
    fflush(nil)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    block()
    fflush(nil)
    dup2(savedFD, STDOUT_FILENO)
    close(savedFD)
    pipe.fileHandleForWriting.closeFile()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func requireThrownBox(_ thrown: Int) throws -> RuntimeThrowableBox {
    let ptr = try #require(
        UnsafeMutableRawPointer(bitPattern: thrown),
        "thrown channel value is not a valid pointer"
    )
    return try #require(
        tryCast(ptr, to: RuntimeThrowableBox.self),
        "thrown value must be a RuntimeThrowableBox"
    )
}

func runtimeString(_ raw: Int) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return ""
    }
    return box.value
}

func runtimeString(_ text: String) -> Int {
    text.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
        }
    }
}

func stringValue(_ raw: Int) -> String {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
}

func makeLocale(language: String, country: String) -> Int {
    var languageLength = 0
    var languageByteCount = 0
    var languageHash = 0
    let languageData = runtimeRegisterFlatString(
        language,
        outLength: &languageLength,
        outByteCount: &languageByteCount,
        outHash: &languageHash
    )

    var countryLength = 0
    var countryByteCount = 0
    var countryHash = 0
    let countryData = runtimeRegisterFlatString(
        country,
        outLength: &countryLength,
        outByteCount: &countryByteCount,
        outHash: &countryHash
    )

    return __kk_locale_new_language_country_flat(
        languageData.map { UnsafePointer($0) },
        languageLength,
        languageByteCount,
        languageHash,
        countryData.map { UnsafePointer($0) },
        countryLength,
        countryByteCount,
        countryHash
    )
}

func runtimeTestListElements(_ listRaw: Int) -> [Int] {
    let size = kk_list_size(listRaw)
    if size <= 0 {
        return []
    }
    return (0 ..< size).map { index in
        kk_list_get(listRaw, index)
    }
}
