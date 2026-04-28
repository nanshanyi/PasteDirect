//
//  PasteDirectTests.swift
//  PasteDirectTests
//
//  Created by 南山忆 on 2022/11/16.
//

import XCTest
@testable import PasteDirect

final class PasteDirectTests: XCTestCase {

    // MARK: - PasteboardModel (struct Sendable)

    func testPasteboardModelIsValueType() {
        let model = makeTextModel(string: "hello")
        var copy = model
        // struct 是值类型，copy 和 model 独立
        XCTAssertEqual(copy, model)
        copy = model.withUpdatedDate()
        // withUpdatedDate 返回新实例，原 model 不变
        XCTAssertEqual(model.hashValue, copy.hashValue)
    }

    func testWithUpdatedDate() {
        let model = makeTextModel(string: "test")
        let oldDate = model.date
        // 等一小段时间确保日期不同
        Thread.sleep(forTimeInterval: 0.01)
        let updated = model.withUpdatedDate()
        XCTAssertGreaterThan(updated.date, oldDate)
        XCTAssertEqual(updated.data, model.data)
        XCTAssertEqual(updated.hashValue, model.hashValue)
    }

    func testHexColorDetection() {
        let colorModel = makeTextModel(string: "#FF5733")
        XCTAssertEqual(colorModel.type, .color)
        XCTAssertEqual(colorModel.hexColorString, "#FF5733")

        let plainModel = makeTextModel(string: "hello world")
        XCTAssertEqual(plainModel.type, .string)
        XCTAssertNil(plainModel.hexColorString)
    }

    func testImageType() {
        let data = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        let model = PasteboardModel(
            pasteboardType: .png, data: data, showData: nil,
            hashValue: data.hashValue, date: Date(),
            appPath: "", appName: "", dataString: "", length: 0
        )
        XCTAssertEqual(model.type, .image)
    }

    func testEquality() {
        let data = "test".data(using: .utf8)!
        let m1 = PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: 12345, date: Date(),
            appPath: "", appName: "", dataString: "test", length: 4
        )
        let m2 = PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: 12345, date: Date(),
            appPath: "/other", appName: "Other", dataString: "test", length: 4
        )
        let m3 = PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: 99999, date: Date(),
            appPath: "", appName: "", dataString: "test", length: 4
        )
        XCTAssertEqual(m1, m2, "相同 hashValue 应相等")
        XCTAssertNotEqual(m1, m3, "不同 hashValue 应不等")
    }

    func testSizeString() {
        let model = makeTextModel(string: "hello")
        let size = model.sizeString()
        XCTAssertTrue(size.contains("5"), "应包含字符数")
    }

    // MARK: - FilterState (Sendable)

    func testFilterStateEmpty() {
        let state = FilterState.empty
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.selectedApp)
        XCTAssertNil(state.selectedType)
        XCTAssertNil(state.selectedDateRange)
    }

    func testFilterStateActive() {
        var state = FilterState.empty
        state.selectedApp = "Xcode"
        XCTAssertTrue(state.isActive)

        state.selectedApp = nil
        state.selectedType = .image
        XCTAssertTrue(state.isActive)
    }

    // MARK: - HexColorValidator

    func testHexColorFormats() {
        XCTAssertNotNil(HexColorValidator.isValidHexColor("#FFF"))
        XCTAssertNotNil(HexColorValidator.isValidHexColor("#FF5733"))
        XCTAssertNotNil(HexColorValidator.isValidHexColor("0xFF5733"))
        XCTAssertNotNil(HexColorValidator.isValidHexColor("FF5733"))
        XCTAssertNil(HexColorValidator.isValidHexColor("hello"))
        XCTAssertNil(HexColorValidator.isValidHexColor(""))
        XCTAssertNil(HexColorValidator.isValidHexColor("#GGG"))
    }

    func testTextColorContrast() {
        let white = NSColor.white
        let black = NSColor.black
        // 白色背景应返回深色文字
        let onWhite = HexColorValidator.textColor(for: white)
        XCTAssertEqual(onWhite, .black)
        // 黑色背景应返回浅色文字
        let onBlack = HexColorValidator.textColor(for: black)
        XCTAssertEqual(onBlack, .white)
    }

    // MARK: - PasteUserDefaults

    func testUserDefaultsReadWrite() {
        let original = PasteUserDefaults.pasteDirect
        PasteUserDefaults.pasteDirect = !original
        XCTAssertEqual(PasteUserDefaults.pasteDirect, !original)
        PasteUserDefaults.pasteDirect = original // 恢复
    }

    // MARK: - PasteSQLManager (actor)

    func testSQLManagerInsertAndSearch() async {
        let manager = PasteSQLManager()
        let model = makeTextModel(string: "unit test item \(UUID().uuidString)")

        await manager.insert(item: model)
        let results = await manager.search(limit: 1, offset: 0)
        XCTAssertFalse(results.isEmpty, "插入后应能搜索到数据")

        // 清理
        await manager.deleteByHash(model.hashValue)
    }

    func testSQLManagerDeleteByHash() async {
        let manager = PasteSQLManager()
        let model = makeTextModel(string: "to delete \(UUID().uuidString)")

        await manager.insert(item: model)
        await manager.deleteByHash(model.hashValue)

        let results = await manager.searchWithParams(
            keyword: model.dataString, state: .empty, limit: 10, offset: 0
        )
        let found = results.contains(where: { $0.hashValue == model.hashValue })
        XCTAssertFalse(found, "删除后不应找到该条目")
    }

    func testSQLManagerSearchWithParams() async {
        let manager = PasteSQLManager()
        let unique = UUID().uuidString
        let model = makeTextModel(string: unique, appName: "TestApp")

        await manager.insert(item: model)

        // 按关键词搜索
        let byKeyword = await manager.searchWithParams(
            keyword: unique, state: .empty, limit: 10, offset: 0
        )
        XCTAssertTrue(byKeyword.contains(where: { $0.dataString == unique }))

        // 按应用筛选
        var state = FilterState.empty
        state.selectedApp = "TestApp"
        let byApp = await manager.searchWithParams(
            keyword: "", state: state, limit: 10, offset: 0
        )
        XCTAssertTrue(byApp.contains(where: { $0.dataString == unique }))

        // 清理
        await manager.deleteByHash(model.hashValue)
    }

    func testSQLManagerDatabaseSize() async {
        let manager = PasteSQLManager()
        let size = await manager.databaseSize
        XCTAssertGreaterThan(size, 0)
    }

    // MARK: - LoadState

    func testLoadStateSendable() {
        // 编译通过即验证 Sendable
        let state: LoadState = .idle
        Task {
            let _ = state // 跨 Task 传递
        }
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Helpers

    private func makeTextModel(string: String, appName: String = "Test") -> PasteboardModel {
        let data = string.data(using: .utf8)!
        return PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: data.hashValue, date: Date(),
            appPath: "/Applications/Test.app", appName: appName,
            dataString: string, length: string.count
        )
    }
}
