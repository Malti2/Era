import Foundation
import AVFoundation

struct AudioMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var era: String?
    var year: Int?
    var artworkData: Data?
}

enum MetadataService {
    static func read(url: URL) async -> AudioMetadata {
        if url.pathExtension.lowercased() == "flac" {
            return FLACVorbisReader.read(url: url) ?? AudioMetadata()
        }
        return await readAVAsset(url: url)
    }

    private static func readAVAsset(url: URL) async -> AudioMetadata {
        var meta = AudioMetadata()
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return meta }
        meta.title = await string(.commonIdentifierTitle, in: items)
        meta.artist = await string(.commonIdentifierArtist, in: items)
        meta.album = await string(.commonIdentifierAlbumName, in: items)
        if let raw = await string(.commonIdentifierCreationDate, in: items) {
            meta.year = Int(raw.prefix(4))
        }
        if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first {
            meta.artworkData = try? await item.load(.dataValue)
        }
        return meta
    }

    private static func string(_ id: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return nil }
        return try? await item.load(.stringValue)
    }
}

// FLAC: eigener Vorbis-Comment-Parser (Spec 13.5) + PICTURE-Block fuer eingebettetes Artwork.
enum FLACVorbisReader {
    static func read(url: URL) -> AudioMetadata? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 8 else { return nil }
        guard data[data.startIndex] == 0x66, data[data.startIndex + 1] == 0x4C,
              data[data.startIndex + 2] == 0x61, data[data.startIndex + 3] == 0x43 else { return nil } // "fLaC"
        var offset = data.startIndex + 4
        var comments: [String: String] = [:]
        var picture: Data?
        while offset + 4 <= data.count {
            let header = data[offset]
            let isLast = (header & 0x80) != 0
            let type = header & 0x7F
            let length = Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            offset += 4
            guard length >= 0, offset + length <= data.count else { break }
            let block = data.subdata(in: offset..<(offset + length))
            if type == 4 { comments = parseComments(block) }
            if type == 6, picture == nil { picture = parsePicture(block) }
            offset += length
            if isLast { break }
        }
        var meta = AudioMetadata()
        meta.title = comments["TITLE"]
        meta.artist = comments["ARTIST"] ?? comments["ALBUMARTIST"]
        meta.album = comments["ALBUM"]
        meta.era = comments["ERA"] ?? comments["GROUPING"]
        if let date = comments["DATE"] ?? comments["YEAR"] { meta.year = Int(date.prefix(4)) }
        meta.artworkData = picture
        return meta
    }

    private static func uint32LE(_ data: Data, at index: inout Int) -> Int? {
        guard index + 4 <= data.count else { return nil }
        let v = Int(data[index]) | Int(data[index + 1]) << 8 | Int(data[index + 2]) << 16 | Int(data[index + 3]) << 24
        index += 4
        return v
    }

    private static func parseComments(_ block: Data) -> [String: String] {
        var result: [String: String] = [:]
        var i = block.startIndex
        guard let vendorLen = uint32LE(block, at: &i), vendorLen >= 0, i + vendorLen <= block.count else { return result }
        i += vendorLen // Vendor-String ueberspringen
        guard let count = uint32LE(block, at: &i), count >= 0 else { return result }
        for _ in 0..<count {
            guard let len = uint32LE(block, at: &i), len >= 0, i + len <= block.count else { break }
            if let entry = String(data: block.subdata(in: i..<(i + len)), encoding: .utf8),
               let eq = entry.firstIndex(of: "=") {
                let key = entry[..<eq].uppercased()
                let value = String(entry[entry.index(after: eq)...])
                result[key] = value
            }
            i += len
        }
        return result
    }

    private static func uint32BE(_ data: Data, at index: inout Int) -> Int? {
        guard index + 4 <= data.count else { return nil }
        let v = Int(data[index]) << 24 | Int(data[index + 1]) << 16 | Int(data[index + 2]) << 8 | Int(data[index + 3])
        index += 4
        return v
    }

    private static func parsePicture(_ block: Data) -> Data? {
        var i = block.startIndex
        guard uint32BE(block, at: &i) != nil else { return nil }              // Bild-Typ
        guard let mimeLen = uint32BE(block, at: &i) else { return nil }
        i += mimeLen                                                          // MIME
        guard let descLen = uint32BE(block, at: &i), i + descLen + 20 <= block.count else { return nil }
        i += descLen                                                          // Beschreibung
        for _ in 0..<4 { guard uint32BE(block, at: &i) != nil else { return nil } } // BxH, Tiefe, Farben
        guard let dataLen = uint32BE(block, at: &i), i + dataLen <= block.count else { return nil }
        return block.subdata(in: i..<(i + dataLen))
    }
}
