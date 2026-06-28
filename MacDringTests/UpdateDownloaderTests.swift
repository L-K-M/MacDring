import XCTest
@testable import MacDring

final class UpdateDownloaderTests: XCTestCase {

    func testUniqueDestinationAvoidsCollisions() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let first = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring.dmg", fileManager: fm)
        XCTAssertEqual(first.lastPathComponent, "MacDring.dmg")
        XCTAssertTrue(fm.createFile(atPath: first.path, contents: Data()))

        let second = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring.dmg", fileManager: fm)
        XCTAssertEqual(second.lastPathComponent, "MacDring-1.dmg")
        XCTAssertTrue(fm.createFile(atPath: second.path, contents: Data()))

        let third = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring.dmg", fileManager: fm)
        XCTAssertEqual(third.lastPathComponent, "MacDring-2.dmg")
    }

    func testUniqueDestinationHandlesNameWithoutExtension() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let first = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring", fileManager: fm)
        XCTAssertEqual(first.lastPathComponent, "MacDring")
        XCTAssertTrue(fm.createFile(atPath: first.path, contents: Data()))

        let second = UpdateDownloader.uniqueDestination(in: dir, fileName: "MacDring", fileManager: fm)
        XCTAssertEqual(second.lastPathComponent, "MacDring-1")
    }

    func testUniqueDestinationSanitizesPathlikeNames() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("UpdateDownloaderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let nested = UpdateDownloader.uniqueDestination(in: dir, fileName: "../../MacDring.dmg", fileManager: fm)
        XCTAssertEqual(nested.deletingLastPathComponent(), dir)
        XCTAssertEqual(nested.lastPathComponent, "MacDring.dmg")

        let empty = UpdateDownloader.uniqueDestination(in: dir, fileName: "   ", fileManager: fm)
        XCTAssertEqual(empty.lastPathComponent, "download")
    }
}
