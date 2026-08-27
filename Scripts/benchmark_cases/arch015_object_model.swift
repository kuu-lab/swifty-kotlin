import Foundation
import Darwin
import Runtime

let iterations = 200_000
let slots = 8

func elapsed(_ body: () -> Int) -> (UInt64, Int) {
    let start = DispatchTime.now().uptimeNanoseconds
    let checksum = body()
    return (DispatchTime.now().uptimeNanoseconds - start, checksum)
}

func maxRSS() -> Int64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int64(usage.ru_maxrss)
}

let baselineRSS = maxRSS()
let box = kk_object_new(0, 1)
for slot in 0..<slots {
    _ = kk_object_register_vtable_method(box, slot, 1)
}
for round in 0..<5 {
    let result = elapsed {
        var checksum = 0
        for _ in 0..<iterations {
            checksum ^= kk_vtable_lookup(box, slots - 1)
        }
        return checksum
    }
    print("box round=\(round) ns=\(result.0) checksum=\(result.1)")
}

let functionPointer = UnsafeRawPointer(bitPattern: 1)!
let offsets = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
offsets.initialize(to: 0)
let vtable = UnsafeMutablePointer<UnsafeRawPointer>.allocate(capacity: 1)
vtable.initialize(to: functionPointer)

"arch015".withCString { name in
    var info = KTypeInfo(
        fqName: name,
        instanceSize: 64,
        fieldCount: 0,
        fieldOffsets: UnsafePointer(offsets),
        vtableSize: 1,
        vtable: UnsafePointer(vtable),
        itable: nil,
        gcDescriptor: nil
    )
    withUnsafePointer(to: &info) { infoPointer in
        let object = kk_alloc(64, UnsafeRawPointer(infoPointer))
        let raw = Int(bitPattern: object)
        for round in 0..<5 {
            let result = elapsed {
                var checksum = 0
                for _ in 0..<iterations {
                    checksum ^= kk_vtable_lookup(raw, 0)
                }
                return checksum
            }
            print("ktypeinfo round=\(round) ns=\(result.0) checksum=\(result.1)")
        }
    }
}

let instances = 2_048
let methods = 16
var objects: [Int] = []
objects.reserveCapacity(instances)
for _ in 0..<instances {
    let object = kk_object_new(0, 1)
    objects.append(object)
    for method in 0..<methods {
        _ = kk_object_register_vtable_method(object, method, 1)
    }
}
print("metadata instances=\(instances) methods=\(methods) entries=\(instances * methods) rss_baseline=\(baselineRSS) rss_after=\(maxRSS())")
print("registered_objects=\(kk_debugging_global_object_count()) heap_objects=\(kk_runtime_heap_object_count())")
