import Foundation

struct BoundedByteBuffer: Sendable {
    let capacity: Int
    private var storage = Data()
    private var startIndex = 0
    private var storedCount = 0

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var data: Data {
        guard storedCount > 0 else {
            return Data()
        }
        if startIndex + storedCount <= capacity {
            return storage.subdata(in: startIndex..<(startIndex + storedCount))
        }

        var result = Data()
        result.reserveCapacity(storedCount)
        result.append(storage[startIndex..<capacity])
        result.append(storage[0..<(storedCount - (capacity - startIndex))])
        return result
    }

    mutating func append(_ newData: Data) {
        guard !newData.isEmpty else {
            return
        }

        if newData.count >= capacity {
            storage = Data(newData.suffix(capacity))
            startIndex = 0
            storedCount = capacity
            return
        }

        if storage.count != capacity {
            storage = Data(count: capacity)
        }

        let overflow = max(storedCount + newData.count - capacity, 0)
        if overflow > 0 {
            startIndex = (startIndex + overflow) % capacity
            storedCount -= overflow
        }

        let writeIndex = (startIndex + storedCount) % capacity
        let firstCount = min(newData.count, capacity - writeIndex)
        storage.withUnsafeMutableBytes { destination in
            newData.withUnsafeBytes { source in
                guard let destinationBase = destination.baseAddress,
                      let sourceBase = source.baseAddress else {
                    return
                }
                destinationBase.advanced(by: writeIndex).copyMemory(
                    from: sourceBase,
                    byteCount: firstCount
                )
                let remainingCount = newData.count - firstCount
                if remainingCount > 0 {
                    destinationBase.copyMemory(
                        from: sourceBase.advanced(by: firstCount),
                        byteCount: remainingCount
                    )
                }
            }
        }
        storedCount += newData.count
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        startIndex = 0
        storedCount = 0
        if !keepingCapacity {
            storage.removeAll(keepingCapacity: false)
        }
    }
}
