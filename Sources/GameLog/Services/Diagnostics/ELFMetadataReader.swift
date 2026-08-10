import Foundation

struct ELFMetadata: Hashable, Sendable {
    let abi: NativeABI
    let buildID: String?
}

enum ELFMetadataReader {
    static func read(from url: URL) throws -> ELFMetadata {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 52,
              data[0] == 0x7F,
              data[1] == 0x45,
              data[2] == 0x4C,
              data[3] == 0x46 else {
            throw ELFMetadataError.invalidELF
        }

        let elfClass = data[4]
        let byteOrder = data[5]
        guard elfClass == 1 || elfClass == 2,
              byteOrder == 1 || byteOrder == 2 else {
            throw ELFMetadataError.unsupportedFormat
        }
        let littleEndian = byteOrder == 1
        let machine = try readInteger(
            UInt16.self,
            from: data,
            offset: 18,
            littleEndian: littleEndian
        )
        let abi: NativeABI
        switch machine {
        case 183: abi = .arm64
        case 40: abi = .arm
        case 62: abi = .x86_64
        case 3: abi = .x86
        default: abi = .unknown
        }

        let programOffset: UInt64
        let programEntrySize: UInt16
        let programCount: UInt16
        if elfClass == 2 {
            programOffset = try readInteger(
                UInt64.self,
                from: data,
                offset: 32,
                littleEndian: littleEndian
            )
            programEntrySize = try readInteger(
                UInt16.self,
                from: data,
                offset: 54,
                littleEndian: littleEndian
            )
            programCount = try readInteger(
                UInt16.self,
                from: data,
                offset: 56,
                littleEndian: littleEndian
            )
        } else {
            programOffset = UInt64(try readInteger(
                UInt32.self,
                from: data,
                offset: 28,
                littleEndian: littleEndian
            ))
            programEntrySize = try readInteger(
                UInt16.self,
                from: data,
                offset: 42,
                littleEndian: littleEndian
            )
            programCount = try readInteger(
                UInt16.self,
                from: data,
                offset: 44,
                littleEndian: littleEndian
            )
        }

        var buildID: String?
        for index in 0..<Int(programCount) {
            let headerOffset = try checkedOffset(
                base: programOffset,
                addition: UInt64(index) * UInt64(programEntrySize),
                dataCount: data.count
            )
            let type = try readInteger(
                UInt32.self,
                from: data,
                offset: headerOffset,
                littleEndian: littleEndian
            )
            guard type == 4 else { continue } // PT_NOTE

            let noteOffset: UInt64
            let noteSize: UInt64
            if elfClass == 2 {
                noteOffset = try readInteger(
                    UInt64.self,
                    from: data,
                    offset: headerOffset + 8,
                    littleEndian: littleEndian
                )
                noteSize = try readInteger(
                    UInt64.self,
                    from: data,
                    offset: headerOffset + 32,
                    littleEndian: littleEndian
                )
            } else {
                noteOffset = UInt64(try readInteger(
                    UInt32.self,
                    from: data,
                    offset: headerOffset + 4,
                    littleEndian: littleEndian
                ))
                noteSize = UInt64(try readInteger(
                    UInt32.self,
                    from: data,
                    offset: headerOffset + 16,
                    littleEndian: littleEndian
                ))
            }
            buildID = try parseBuildID(
                data: data,
                offset: noteOffset,
                size: noteSize,
                littleEndian: littleEndian
            )
            if buildID != nil { break }
        }
        return ELFMetadata(abi: abi, buildID: buildID)
    }

    private static func parseBuildID(
        data: Data,
        offset: UInt64,
        size: UInt64,
        littleEndian: Bool
    ) throws -> String? {
        let start = try checkedOffset(base: offset, addition: 0, dataCount: data.count)
        let end64 = offset.addingReportingOverflow(size)
        guard !end64.overflow, end64.partialValue <= UInt64(data.count) else {
            throw ELFMetadataError.invalidBounds
        }
        let end = Int(end64.partialValue)
        var cursor = start

        while cursor + 12 <= end {
            let nameSize = Int(try readInteger(
                UInt32.self,
                from: data,
                offset: cursor,
                littleEndian: littleEndian
            ))
            let descriptionSize = Int(try readInteger(
                UInt32.self,
                from: data,
                offset: cursor + 4,
                littleEndian: littleEndian
            ))
            let type = try readInteger(
                UInt32.self,
                from: data,
                offset: cursor + 8,
                littleEndian: littleEndian
            )
            cursor += 12
            let paddedNameSize = aligned4(nameSize)
            let paddedDescriptionSize = aligned4(descriptionSize)
            guard nameSize >= 0,
                  descriptionSize >= 0,
                  cursor + paddedNameSize + paddedDescriptionSize <= end else {
                throw ELFMetadataError.invalidBounds
            }
            let name = data[cursor..<cursor + nameSize]
            cursor += paddedNameSize
            let description = data[cursor..<cursor + descriptionSize]
            cursor += paddedDescriptionSize

            if type == 3, name.starts(with: Data("GNU".utf8)), !description.isEmpty {
                return description.map { String(format: "%02x", $0) }.joined()
            }
        }
        return nil
    }

    private static func aligned4(_ value: Int) -> Int {
        (value + 3) & ~3
    }

    private static func checkedOffset(
        base: UInt64,
        addition: UInt64,
        dataCount: Int
    ) throws -> Int {
        let result = base.addingReportingOverflow(addition)
        guard !result.overflow, result.partialValue <= UInt64(dataCount) else {
            throw ELFMetadataError.invalidBounds
        }
        return Int(result.partialValue)
    }

    private static func readInteger<T: FixedWidthInteger>(
        _ type: T.Type,
        from data: Data,
        offset: Int,
        littleEndian: Bool
    ) throws -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= data.count else {
            throw ELFMetadataError.invalidBounds
        }
        var value: T = 0
        for byteIndex in 0..<MemoryLayout<T>.size {
            let shiftIndex = littleEndian ? byteIndex : MemoryLayout<T>.size - byteIndex - 1
            value |= T(data[offset + byteIndex]) << T(shiftIndex * 8)
        }
        return value
    }
}

enum ELFMetadataError: LocalizedError, Sendable {
    case invalidELF
    case unsupportedFormat
    case invalidBounds

    var errorDescription: String? {
        switch self {
        case .invalidELF: "不是有效的 ELF 符号文件。"
        case .unsupportedFormat: "ELF 位宽或字节序不受支持。"
        case .invalidBounds: "ELF 元数据范围无效。"
        }
    }
}
