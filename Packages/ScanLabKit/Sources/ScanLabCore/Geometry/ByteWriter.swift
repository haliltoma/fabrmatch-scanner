import Foundation

/// Little-endian binary writer used by chunk files and binary exporters.
public struct ByteWriter: Sendable {
    public private(set) var data = Data()

    public init(capacity: Int = 0) { data.reserveCapacity(capacity) }

    public mutating func write<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    public mutating func write(_ value: Float) { write(value.bitPattern) }

    public mutating func write(_ v: SIMD3<Float>) {
        write(v.x); write(v.y); write(v.z)
    }

    public mutating func write(bytes: some Sequence<UInt8>) { data.append(contentsOf: bytes) }

    public mutating func write(_ uuid: UUID) {
        withUnsafeBytes(of: uuid.uuid) { data.append(contentsOf: $0) }
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        data.removeAll(keepingCapacity: keepingCapacity)
    }
}
