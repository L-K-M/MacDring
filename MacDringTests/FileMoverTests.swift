import XCTest
@testable import MacDring

final class FileMoverTests: XCTestCase {

    private var base: URL!
    private var src: URL!
    private var dst: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("macdring-mover-\(UUID().uuidString)")
        src = base.appendingPathComponent("src", isDirectory: true)
        dst = base.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func testMovesFileIntoDirectory() throws {
        let file = src.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: file)

        XCTAssertTrue(FileMover.move([file], into: dst))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("note.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))   // moved, not copied
    }

    func testRenamesOnCollision() throws {
        try Data("a".utf8).write(to: dst.appendingPathComponent("note.txt"))
        let file = src.appendingPathComponent("note.txt")
        try Data("b".utf8).write(to: file)

        XCTAssertTrue(FileMover.move([file], into: dst))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("note.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("note 2.txt").path))
    }
}
