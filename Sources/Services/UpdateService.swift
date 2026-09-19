import Foundation

@MainActor
final class UpdateService: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release, Double)
        case downloaded(Release, URL)
        case failed(String)
    }

    struct Release: Decodable, Equatable {
        let version: String
        let notes: String
        let ipaURL: URL
        let ipaName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case assets
        }

        struct Asset: Decodable, Equatable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        init(version: String, notes: String, ipaURL: URL, ipaName: String) {
            self.version = version
            self.notes = notes
            self.ipaURL = ipaURL
            self.ipaName = ipaName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let tag = try container.decode(String.self, forKey: .tagName)
            let assets = try container.decode([Asset].self, forKey: .assets)
            guard let ipa = assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") }) else {
                throw UpdateError.noIPA
            }
            let rawVersion = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            version = rawVersion.split(separator: "-").first.map(String.init) ?? rawVersion
            notes = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
            ipaURL = ipa.browserDownloadURL
            ipaName = ipa.name
        }
    }

    enum UpdateError: LocalizedError {
        case invalidResponse
        case noIPA
        case invalidDownload

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "GitHub returned an invalid response."
            case .noIPA: "The latest release does not contain an IPA."
            case .invalidDownload: "The downloaded file is not a valid IPA."
            }
        }
    }

    @Published private(set) var state: State = .idle

    var availableRelease: Release? {
        if case .available(let release) = state { release } else { nil }
    }

    // The release the update UI is talking about, stable across the whole
    // download flow. availableRelease turns nil the moment the state moves to
    // downloading, which used to swap the drawer back to the demo version.
    var presentedRelease: Release? {
        switch state {
        case .available(let release), .downloading(let release, _), .downloaded(let release, _):
            release
        default:
            nil
        }
    }
    private let releasesURL = URL(string: "https://api.github.com/repos/Malti2/Era/releases?per_page=20")!

    func check(currentVersion: String) async {
        state = .checking
        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Era-iOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.invalidResponse
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            guard let release = releases.first else { throw UpdateError.noIPA }
            state = release.version.compare(currentVersion, options: .numeric) == .orderedDescending
                ? .available(release)
                : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func download(_ release: Release) async {
        state = .downloading(release, 0)
        do {
            var request = URLRequest(url: release.ipaURL)
            request.setValue("Era-iOS/\(release.version)", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else { throw UpdateError.invalidDownload }

            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Updates", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safeVersion = release.version.replacingOccurrences(of: "/", with: "-")
            let destination = folder.appendingPathComponent("Era-\(safeVersion)-unsigned.ipa")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            state = .downloaded(release, destination)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
