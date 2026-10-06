import Foundation

public enum ByteReaderError: Error, Equatable {
    case unexpectedEnd(offset: Int, needed: Int)
}

/// Bounds-checked little-endian reader; truncated input throws instead of crashing.
public struct ByteReader {
    private let data: Data
    public private(set) var offset: Int

    public init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public var remaining: Int { data.count - offset }

    public mutating func read<T: FixedWidthInteger>(_: T.Type = T.self) throws -> T {
        let size = MemoryLayout<T>.size
        let raw = try bytes(size)
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: raw) }
        return T(littleEndian: value)
    }

    public mutating func readFloat() throws -> Float { Float(bitPattern: try read(UInt32.self)) }

    public mutating func readVector() throws -> SIMD3<Float> {
        SIMD3(try readFloat(), try readFloat(), try readFloat())
    }

    public mutating func readUUID() throws -> UUID {
        let b = Array(try bytes(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    public mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw ByteReaderError.unexpectedEnd(offset: offset, needed: count) }
        let start = data.startIndex + offset
        offset += count
        return data[start..<start + count]
    }
}
