import AppKit
import Chiikawa_in_myMacCore

/// 스프라이트 시트를 칸별 그림으로 잘라 둔 것. 줄마다 그림이 있는 칸 수가 달라 빈 칸은 뺀다.
struct SpriteSheet {
    /// 줄(동작)별 칸 그림.
    let frames: [PetAnimation: [CGImage]]
    /// 한 칸의 픽셀 크기.
    let cellSize: CGSize
    /// 시트의 줄 대신 보여 줄 동작 (`pet.json` 의 `motions`). 받은 GIF 에서 만든 것들이다.
    var clips: [PetAnimation: SpecialMotion] = [:]

    func frames(for animation: PetAnimation) -> [CGImage] {
        // 시트에 없는 줄(9줄짜리 시트의 추가 동작)은 가만히 있는 동작으로 대신한다.
        frames[animation] ?? frames[.idle] ?? []
    }

    static func load(from url: URL) -> SpriteSheet? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let columns = PetAnimation.columns
        guard image.width % columns == 0,
              let rows = PetAnimation.supportedRowCounts.first(where: { image.height % $0 == 0 }) else { return nil }
        let cellWidth = image.width / columns
        let cellHeight = image.height / rows
        guard let alpha = AlphaMap(image: image) else { return nil }

        var frames: [PetAnimation: [CGImage]] = [:]
        for animation in PetAnimation.allCases where animation.rawValue < rows {
            var cells: [CGImage] = []
            for column in 0..<columns {
                let rect = CGRect(x: column * cellWidth, y: animation.rawValue * cellHeight, width: cellWidth, height: cellHeight)
                // 빈 칸이 나오면 그 줄은 거기서 끝난다.
                guard alpha.hasContent(in: rect), let cell = image.cropping(to: rect) else { break }
                cells.append(cell)
            }
            if !cells.isEmpty { frames[animation] = cells }
        }
        guard frames[.idle] != nil else { return nil }
        var sheet = SpriteSheet(frames: frames, cellSize: CGSize(width: cellWidth, height: cellHeight))
        // 같은 폴더의 pet.json 이 줄을 다른 동작으로 바꾸라고 하면 읽어 둔다. 칸 크기가 같은 것만 쓴다.
        let folder = url.deletingLastPathComponent()
        if let data = try? Data(contentsOf: folder.appendingPathComponent("pet.json")),
           let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let motions = manifest["motions"] as? [String: String] {
            for animation in PetAnimation.allCases {
                guard let name = motions[animation.name], let clip = SpecialMotion.load(named: name, in: folder),
                      clip.cellSize == sheet.cellSize else { continue }
                sheet.clips[animation] = clip
            }
        }
        return sheet
    }
}

/// 특수 모션: 평소 시트와 따로 둔 한 번짜리 동작. 칸마다 보여 주는 시각이 정해져 있어 음성과 맞물린다.
struct SpecialMotion {
    let frames: [CGImage]
    /// 각 칸을 보여 주기 시작하는 시각(초).
    let times: [TimeInterval]
    /// 마지막 칸을 내리는 시각.
    let end: TimeInterval
    /// 한 칸의 픽셀 크기. 평소 칸보다 넓을 수 있다 (좌우로 오가는 움직임이 담겨 있다).
    let cellSize: CGSize
    /// 끝까지 가면 처음부터 다시 도는지.
    let loops: Bool

    /// 지금 시각에 보여 줄 칸: 시작 시각이 지난 것 가운데 마지막.
    func frameIndex(at elapsed: TimeInterval) -> Int {
        max(0, (times.firstIndex { $0 > elapsed } ?? times.count) - 1)
    }

    /// 펫 폴더의 `<이름>.json` 과 그것이 가리키는 시트를 읽는다.
    static func load(named name: String, in folder: URL) -> SpecialMotion? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sheetName = manifest["spritesheetPath"] as? String,
              let width = manifest["cellWidth"] as? Int, let height = manifest["cellHeight"] as? Int,
              let columns = manifest["columns"] as? Int, columns > 0, width > 0, height > 0,
              let times = manifest["times"] as? [Double], !times.isEmpty,
              let end = manifest["end"] as? Double,
              let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(sheetName) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var frames: [CGImage] = []
        for index in times.indices {
            let rect = CGRect(x: (index % columns) * width, y: (index / columns) * height, width: width, height: height)
            guard let frame = image.cropping(to: rect) else { return nil }
            frames.append(frame)
        }
        return SpecialMotion(
            frames: frames, times: times, end: end, cellSize: CGSize(width: width, height: height),
            loops: manifest["loop"] as? Bool ?? false
        )
    }
}

/// 그림의 불투명한 곳을 찾기 위한 투명도 표.
private struct AlphaMap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    /// `rect` 는 그림의 왼쪽 위가 원점인 픽셀 좌표. 메모리의 첫 줄이 그림의 맨 윗줄이다.
    func hasContent(in rect: CGRect) -> Bool {
        // 4픽셀 간격으로만 봐도 캐릭터를 놓치지 않는다.
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 4) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 4) where bytes[y * width + x] > 24 {
                return true
            }
        }
        return false
    }
}

enum PetLocator {
    /// 펫 폴더(`pet.json` + 스프라이트 시트)를 찾는다. `CHIIKAWA_PET_DIR` 로 다른 펫을 가리킬 수 있다 (시험용).
    static func spritesheetURL() -> URL? {
        petFolder().map { $0.folder.appendingPathComponent($0.sheet) }
    }

    /// 펫 폴더와 그 안의 스프라이트 시트 이름.
    static func petFolder() -> (folder: URL, sheet: String)? {
        var folders = resourceCandidates("Pets/usagi")
        if let path = ProcessInfo.processInfo.environment["CHIIKAWA_PET_DIR"] {
            folders.insert(URL(fileURLWithPath: path), at: 0)
        }
        for folder in folders {
            let manifest = folder.appendingPathComponent("pet.json")
            guard let data = try? Data(contentsOf: manifest),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = object["spritesheetPath"] as? String else { continue }
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) { return (folder, name) }
        }
        return nil
    }

    /// 메뉴바 아이콘 그림.
    static func menuIconURL() -> URL? {
        resourceCandidates("MenuIcon.png").first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 말풍선 글꼴 파일.
    static func fontURL() -> URL? {
        resourceCandidates("Fonts/Jua-Regular.ttf").first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 우사기 음성 파일.
    static func voiceURL(_ name: String) -> URL? {
        resourceCandidates("Voices/\(name)").first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 리소스가 있을 수 있는 곳: 앱 번들 → 소스에서 실행할 때의 패키지 폴더.
    private static func resourceCandidates(_ relativePath: String) -> [URL] {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(relativePath))
        }
        // `swift run` 은 <패키지>/.build/<구성>/Chiikawa_in_myMac 을 실행하므로 위로 올라가며 찾는다.
        var directory = Bundle.main.bundleURL
        for _ in 0..<5 {
            candidates.append(directory.appendingPathComponent("Resources").appendingPathComponent(relativePath))
            directory.deleteLastPathComponent()
        }
        return candidates
    }
}
