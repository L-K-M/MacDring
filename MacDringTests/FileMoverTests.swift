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

    func testDroppingFileIntoItsOwnDirectoryIsANoOp() throws {
        let file = dst.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: file)

        XCTAssertTrue(FileMover.move([file], into: dst))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))   // untouched
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.appendingPathComponent("note 2.txt").path))   // not renamed
    }

    func testSelfDropSkipsButOtherFilesStillMove() throws {
        let resident = dst.appendingPathComponent("resident.txt")
        try Data("r".utf8).write(to: resident)
        let incoming = src.appendingPathComponent("incoming.txt")
        try Data("i".utf8).write(to: incoming)

        XCTAssertTrue(FileMover.move([resident, incoming], into: dst))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resident.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.appendingPathComponent("resident 2.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("incoming.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path))
    }

    func testRenamesOnCollision() throws {
        try Data("a".utf8).write(to: dst.appendingPathComponent("note.txt"))
        let file = src.appendingPathComponent("note.txt")
        try Data("b".utf8).write(to: file)

        XCTAssertTrue(FileMover.move([file], into: dst))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("note.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("note 2.txt").path))
    }

    func testMovingFilesReportsMovesAndUndoRestoresThem() throws {
        let fm = FileManager.default
        let a = src.appendingPathComponent("a.txt")
        let b = src.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)

        let result = FileMover.movingFiles([a, b], into: dst)
        XCTAssertTrue(result.allSucceeded)
        XCTAssertEqual(result.moves.count, 2)
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("a.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: a.path))

        XCTAssertTrue(FileMover.undo(result.moves))
        // Each file is back at its original path; none left in the destination.
        XCTAssertTrue(fm.fileExists(atPath: a.path))
        XCTAssertTrue(fm.fileExists(atPath: b.path))
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("a.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("b.txt").path))
    }
}
