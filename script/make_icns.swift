#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: make_icns.swift <iconset-directory> <output.icns>\n".utf8)
    )
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    let encoded = value.bigEndian
    return withUnsafeBytes(of: encoded) { Array($0) }
}

var body = Data()
for entry in entries {
    let data = try Data(contentsOf: directory.appending(path: entry.file))
    body.append(contentsOf: entry.type.utf8)
    body.append(contentsOf: bigEndianBytes(UInt32(data.count + 8)))
    body.append(data)
}

var container = Data("icns".utf8)
container.append(contentsOf: bigEndianBytes(UInt32(body.count + 8)))
container.append(body)
try container.write(to: output, options: .atomic)
