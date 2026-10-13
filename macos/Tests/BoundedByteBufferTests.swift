import Foundation
import XCTest
@testable import MyShell

final class BoundedByteBufferTests: XCTestCase {
    func testAppendKeepsNewestBytesWithinCapacity() {
        var buffer = BoundedByteBuffer(capacity: 5)

        buffer.append(Data("abc".utf8))
        buffer.append(Data("def".utf8))

        XCTAssertEqual(String(decoding: buffer.data, as: UTF8.self), "bcdef")
    }

    func testOversizedAppendDropsOlderContent() {
        var buffer = BoundedByteBuffer(capacity: 4)

        buffer.append(Data("old".utf8))
        buffer.append(Data("123456".utf8))

        XCTAssertEqual(String(decoding: buffer.data, as: UTF8.self), "3456")
    }

    func testCapacityHasMinimumOfOneByte() {
        let buffer = BoundedByteBuffer(capacity: 0)

        XCTAssertEqual(buffer.capacity, 1)
    }

    func testRepeatedWraparoundPreservesByteOrder() {
        var buffer = BoundedByteBuffer(capacity: 8)

        for value in ["abc", "def", "ghi", "jkl"] {
            buffer.append(Data(value.utf8))
        }

        XCTAssertEqual(String(decoding: buffer.data, as: UTF8.self), "efghijkl")
    }

    func testRemoveAllCanReleaseStorageAndAcceptNewData() {
        var buffer = BoundedByteBuffer(capacity: 4)
        buffer.append(Data("abcd".utf8))

        buffer.removeAll(keepingCapacity: false)
        buffer.append(Data("xy".utf8))

        XCTAssertEqual(buffer.data, Data("xy".utf8))
    }
}
