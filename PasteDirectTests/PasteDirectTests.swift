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

    @MainActor
    func testUserDefaultsReadWrite() {
        let original = PasteUserDefaults.pasteDirect
        PasteUserDefaults.pasteDirect = !original
        XCTAssertEqual(PasteUserDefaults.pasteDirect, !original)
        PasteUserDefaults.pasteDirect = original // 恢复
    }

    // MARK: - PasteSQLManager (actor)

    func testSQLManagerInsertAndSearch() async {
        let manager = await makeTempManager()
        let model = makeTextModel(string: "unit test item \(UUID().uuidString)")

        await manager.insert(item: model)
        let results = await manager.search(limit: 1, offset: 0)
        XCTAssertFalse(results.isEmpty, "插入后应能搜索到数据")
    }

    func testSQLManagerDeleteByHash() async {
        let manager = await makeTempManager()
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
        let manager = await makeTempManager()
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
    }

    func testSQLManagerDatabaseSize() async {
        let manager = await makeTempManager()
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

    /// 创建一个挂在独立临时路径上的 PasteSQLManager 并建表,
    /// 避免测试读写用户真实的剪贴板历史库。临时文件随测试进程丢弃。
    private func makeTempManager() async -> PasteSQLManager {
        let path = NSTemporaryDirectory()
            .appending("pd-tests-\(UUID().uuidString)/paste.sqlite3")
        let manager = PasteSQLManager(dbPath: path)
        await manager.setup()
        return manager
    }

    private func makeTextModel(string: String, appName: String = "Test") -> PasteboardModel {
        let data = string.data(using: .utf8)!
        return PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: data.hashValue, date: Date(),
            appPath: "/Applications/Test.app", appName: appName,
            dataString: string, length: string.count
        )
    }

    // MARK: - OCR (图片文字识别,附属字段方案)

    func testPasteboardModelOCRTextField() {
        // 普通文本项不带 ocrText
        let plain = makeTextModel(string: "纯文本")
        XCTAssertNil(plain.ocrText)
        XCTAssertEqual(plain.type, .string)

        // 图片项识别前 ocrText 为 nil,识别后通过 withOCRText 写入
        let imgData = Data([0x89, 0x50, 0x4E, 0x47])
        let image = PasteboardModel(
            pasteboardType: .png, data: imgData, showData: nil,
            hashValue: imgData.hashValue, date: Date(),
            appPath: "/Applications/Safari.app", appName: "Safari",
            dataString: "", length: 0
        )
        XCTAssertNil(image.ocrText)
        XCTAssertEqual(image.type, .image)

        let recognized = image.withOCRText("图片里的文字")
        // 识别后类型仍是图片(附属字段不改变展示类型)
        XCTAssertEqual(recognized.type, .image)
        XCTAssertEqual(recognized.ocrText, "图片里的文字")
        // 关键字段不变,仍与源图相等(hashValue 一致)
        XCTAssertEqual(recognized.hashValue, image.hashValue)
        XCTAssertEqual(recognized, image)
    }

    @MainActor
    func testMakeTextStableHash() {
        let img = PasteboardModel(
            pasteboardType: .png, data: Data([0x89]), showData: nil,
            hashValue: 1, date: Date(),
            appPath: "/A.app", appName: "A", dataString: "", length: 0
        )

        // makeText 由文本构造 .string 项,继承来源图片的 app 信息
        let a = PasteboardModel.makeText("识别出的同一段文字", from: img)
        XCTAssertEqual(a.type, .string)
        XCTAssertEqual(a.dataString, "识别出的同一段文字")
        XCTAssertEqual(a.appName, "A")
        XCTAssertNil(a.ocrText)
    }

    func testSQLManagerOCRTextColumnRoundTrip() async {
        let manager = await makeTempManager()
        let unique = "ocr-col-\(UUID().uuidString)"
        let model = PasteboardModel(
            pasteboardType: .png, data: unique.data(using: .utf8)!, showData: nil,
            hashValue: unique.hashValue, date: Date(),
            appPath: "", appName: "", dataString: "", length: 0,
            ocrText: unique
        )
        await manager.insert(item: model)

        // 能把 ocrText 原样读回
        let results = await manager.search(limit: 200, offset: 0)
        let fetched = results.first(where: { $0.hashValue == unique.hashValue })
        XCTAssertEqual(fetched?.ocrText, unique, "ocrText 应能持久化并读回")
    }

    func testSQLManagerUpdateOCRTextAndSearch() async {
        let manager = await makeTempManager()
        let hash = Int.random(in: 1_000_000...9_000_000)
        let keyword = "ocrkw\(UUID().uuidString.prefix(8))"

        // 先插入一张没有 OCR 文本的图片
        let image = PasteboardModel(
            pasteboardType: .png, data: Data([0x89, 0x50]), showData: nil,
            hashValue: hash, date: Date(),
            appPath: "", appName: "", dataString: "", length: 0
        )
        await manager.insert(item: image)

        // 关键字此时搜不到(图片本身无文本)
        var state = FilterState.empty
        let before = await manager.searchWithParams(
            keyword: String(keyword), state: state, limit: 100, offset: 0
        )
        XCTAssertFalse(before.contains(where: { $0.hashValue == hash }),
                       "识别前不应被关键字命中")

        // 回写 OCR 文本后,关键字应能命中这张图片
        await manager.updateOCRText("含有关键字 \(keyword) 的内容", forHash: hash)
        let after = await manager.searchWithParams(
            keyword: String(keyword), state: state, limit: 100, offset: 0
        )
        let hit = after.first(where: { $0.hashValue == hash })
        XCTAssertNotNil(hit, "识别后应能按 OCR 文本搜到图片")
        XCTAssertEqual(hit?.type, .image, "命中项仍是图片类型")

        // 图片筛选仍应包含它
        state.selectedType = .image
        let byImage = await manager.searchWithParams(
            keyword: "", state: state, limit: 200, offset: 0
        )
        XCTAssertTrue(byImage.contains(where: { $0.hashValue == hash }))
    }
}
