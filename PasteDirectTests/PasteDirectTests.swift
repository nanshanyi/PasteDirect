//
//  PasteDirectTests.swift
//  PasteDirectTests
//
//  Created by 南山忆 on 2022/11/16.
//

import AppKit
import SQLite3
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

    func testLinkDetection() {
        XCTAssertEqual(makeTextModel(string: "https://github.com/nanshanyi").type, .link)
        XCTAssertEqual(makeTextModel(string: "  http://a.com/x?y=1 \n").type, .link)
        XCTAssertEqual(makeTextModel(string: "see https://github.com").type, .string)
        XCTAssertEqual(makeTextModel(string: "www.github.com").type, .string)
        XCTAssertEqual(makeTextModel(string: "ftp://a.com").type, .string)
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
        XCTAssertNil(HexColorValidator.isValidHexColor("FF5733"))
        XCTAssertNil(HexColorValidator.isValidHexColor("deadbeef"))
        XCTAssertNil(HexColorValidator.isValidHexColor("123456"))
        XCTAssertEqual(HexColorValidator.isValidHexColor("rgb(255, 87, 51)"), "#FF5733")
        XCTAssertEqual(HexColorValidator.isValidHexColor("rgba(255,87,51,0.5)"), "#FF5733")
        XCTAssertEqual(HexColorValidator.isValidHexColor("rgb(100% 0% 0% / 50%)"), "#FF0000")
        XCTAssertEqual(HexColorValidator.isValidHexColor("hsl(120, 100%, 50%)"), "#00FF00")
        XCTAssertEqual(HexColorValidator.isValidHexColor("hsla(240deg 100% 50% / 0.3)"), "#0000FF")
        XCTAssertNil(HexColorValidator.isValidHexColor("rgb(1, 2)"))
        XCTAssertNil(HexColorValidator.isValidHexColor("rgb(a, b, c)"))
        XCTAssertNil(HexColorValidator.isValidHexColor("hsl(120, 100, 50)"))
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
        let results = await manager.fetchPage(limit: 1).items
        XCTAssertFalse(results.isEmpty, "插入后应能搜索到数据")
    }

    func testSQLManagerDeleteByHash() async {
        let manager = await makeTempManager()
        let model = makeTextModel(string: "to delete \(UUID().uuidString)")

        await manager.insert(item: model)
        await manager.deleteByHash(model.hashValue)

        let results = await manager.fetchPage(
            keyword: model.dataString, state: .empty, limit: 10
        ).items
        let found = results.contains(where: { $0.hashValue == model.hashValue })
        XCTAssertFalse(found, "删除后不应找到该条目")
    }

    func testSQLManagerSearchWithParams() async {
        let manager = await makeTempManager()
        let unique = UUID().uuidString
        let model = makeTextModel(string: unique, appName: "TestApp")

        await manager.insert(item: model)

        // 按关键词搜索
        let byKeyword = await manager.fetchPage(
            keyword: unique, state: .empty, limit: 10
        ).items
        XCTAssertTrue(byKeyword.contains(where: { $0.dataString == unique }))

        // 按应用筛选
        var state = FilterState.empty
        state.selectedApp = "TestApp"
        let byApp = await manager.fetchPage(
            keyword: "", state: state, limit: 10
        ).items
        XCTAssertTrue(byApp.contains(where: { $0.dataString == unique }))
    }

    func testSQLManagerDatabaseSize() async {
        let manager = await makeTempManager()
        let size = await manager.databaseSize
        XCTAssertGreaterThan(size, 0)
    }

    /// LIKE 通配符转义:搜索关键字里的 % / _ 应按字面匹配,不当作通配符
    func testSQLManagerSearchEscapesLikeWildcards() async {
        let manager = await makeTempManager()
        let tag = UUID().uuidString
        // 一条含字面 "%" 的内容,一条不含 "%" 的普通内容(共享 tag 便于隔离本用例数据)
        let withPercent = makeTextModel(string: "discount 50% off \(tag)")
        let plain = makeTextModel(string: "plain text \(tag)")
        await manager.insert(item: withPercent)
        await manager.insert(item: plain)

        // 搜 "50%":未转义时 % 会通配,plain 那条也可能被 "50" 前缀匹配到;
        // 正确行为是只命中真正含 "50%" 字面的那条
        let results = await manager.fetchPage(
            keyword: "50%", state: .empty, limit: 100
        ).items
        let hashes = Set(results.map { $0.hashValue })
        XCTAssertTrue(hashes.contains(withPercent.hashValue), "应命中含字面 50% 的条目")
        XCTAssertFalse(hashes.contains(plain.hashValue), "不应把 % 当通配符匹配到无关条目")
    }

    /// LIKE 通配符转义:单独搜 "_" 不应匹配任意单字符内容
    func testSQLManagerSearchEscapesUnderscore() async {
        let manager = await makeTempManager()
        let tag = UUID().uuidString
        let withUnderscore = makeTextModel(string: "file_name \(tag)")
        let plain = makeTextModel(string: "filename \(tag)")
        await manager.insert(item: withUnderscore)
        await manager.insert(item: plain)

        let results = await manager.fetchPage(
            keyword: "file_name", state: .empty, limit: 100
        ).items
        let hashes = Set(results.map { $0.hashValue })
        XCTAssertTrue(hashes.contains(withUnderscore.hashValue), "应命中含字面下划线的条目")
        XCTAssertFalse(hashes.contains(plain.hashValue), "不应把 _ 当作任意单字符通配符")
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

    func testKindFilterAndCounts() async {
        let manager = await makeTempManager()
        for text in ["https://a.com/\(UUID().uuidString)", "#FF5733", "plain \(UUID().uuidString)"] {
            await manager.insert(item: makeTextModel(string: text))
        }
        let links = await manager.fetchPage(keyword: "", state: FilterState(selectedType: .link), limit: 20).items
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.type, .link)
        let colors = await manager.fetchPage(keyword: "", state: FilterState(selectedType: .color), limit: 20).items
        XCTAssertEqual(colors.map(\.type), [.color])
        let counts = await manager.typeCounts()
        XCTAssertEqual(counts.text, 3)
        XCTAssertEqual(counts.count(for: .link), 1)
        XCTAssertEqual(counts.count(for: .color), 1)
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
        let results = await manager.fetchPage(limit: 200).items
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
        let before = await manager.fetchPage(
            keyword: String(keyword), state: state, limit: 100
        ).items
        XCTAssertFalse(before.contains(where: { $0.hashValue == hash }),
                       "识别前不应被关键字命中")

        // 回写 OCR 文本后,关键字应能命中这张图片
        await manager.updateOCRText("含有关键字 \(keyword) 的内容", forHash: hash)
        let after = await manager.fetchPage(
            keyword: String(keyword), state: state, limit: 100
        ).items
        let hit = after.first(where: { $0.hashValue == hash })
        XCTAssertNotNil(hit, "识别后应能按 OCR 文本搜到图片")
        XCTAssertEqual(hit?.type, .image, "命中项仍是图片类型")

        // 图片筛选仍应包含它
        state.selectedType = .image
        let byImage = await manager.fetchPage(
            keyword: "", state: state, limit: 200
        ).items
        XCTAssertTrue(byImage.contains(where: { $0.hashValue == hash }))
    }

    // MARK: - 图片外置 (ImageBlobStore / ImageThumbnail / 迁移)

    /// 生成一张指定像素尺寸的纯色 PNG，用于图片相关测试
    private func makePNGData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    func testImageBlobStoreSaveLoadDelete() async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pd-blob-\(UUID().uuidString)", isDirectory: true)
        let store = ImageBlobStore(directory: dir)
        let data = makePNGData(width: 8, height: 8)
        let hash = Int.random(in: 1...9_000_000)

        await store.save(data, for: hash)
        let exists = await store.exists(for: hash)
        XCTAssertTrue(exists, "保存后文件应存在")

        let loaded = await store.load(for: hash)
        XCTAssertEqual(loaded, data, "读回的数据应与写入一致")

        await store.delete(for: hash)
        let afterDelete = await store.load(for: hash)
        XCTAssertNil(afterDelete, "删除后应读不到")
    }

    func testImageBlobStoreLoadMissingReturnsNil() async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pd-blob-\(UUID().uuidString)", isDirectory: true)
        let store = ImageBlobStore(directory: dir)
        let missing = await store.load(for: 424242)
        XCTAssertNil(missing, "不存在的 hash 应返回 nil 而非崩溃")
    }

    func testImageThumbnailMakeReturnsSizeAndData() {
        let original = makePNGData(width: 1200, height: 600)
        let result = ImageThumbnail.make(from: original)
        XCTAssertNotNil(result, "应能生成缩略图")
        guard let result else { return }
        // 原图像素尺寸应被正确读出
        XCTAssertEqual(Int(result.pixelSize.width), 1200)
        XCTAssertEqual(Int(result.pixelSize.height), 600)
        // 缩略图应是有效 PNG，且字节数远小于原图
        XCTAssertNotNil(NSImage(data: result.thumbnail))
        XCTAssertLessThan(result.thumbnail.count, original.count)
    }

    func testImageThumbnailPixelSizeOnly() {
        let data = makePNGData(width: 333, height: 222)
        let size = ImageThumbnail.pixelSize(of: data)
        XCTAssertEqual(size?.width, 333)
        XCTAssertEqual(size?.height, 222)
    }

    func testReplacingDataKeepsHashAndFields() {
        let imgData = makePNGData(width: 10, height: 20)
        let image = PasteboardModel(
            pasteboardType: .png, data: imgData, showData: nil,
            hashValue: imgData.hashValue, date: Date(),
            appPath: "/A.app", appName: "A", dataString: "", length: 0,
            imageWidth: 10, imageHeight: 20
        )
        let thumb = Data([0x01, 0x02, 0x03])
        let replaced = image.replacingData(thumb)
        XCTAssertEqual(replaced.data, thumb, "data 应被替换")
        XCTAssertEqual(replaced.hashValue, image.hashValue, "hashValue 不变(仍是原图哈希)")
        XCTAssertEqual(replaced.imageWidth, 10)
        XCTAssertEqual(replaced.imageHeight, 20)
        XCTAssertEqual(replaced, image, "相等性由 hashValue 决定，应相等")
    }

    func testSQLManagerImageSizeColumnRoundTrip() async {
        let manager = await makeTempManager()
        let hash = Int.random(in: 1_000_000...9_000_000)
        let model = PasteboardModel(
            pasteboardType: .png, data: Data([0x89, 0x50]), showData: nil,
            hashValue: hash, date: Date(),
            appPath: "", appName: "", dataString: "", length: 0,
            imageWidth: 800, imageHeight: 450
        )
        await manager.insert(item: model)
        let results = await manager.fetchPage(limit: 200).items
        let fetched = results.first(where: { $0.hashValue == hash })
        XCTAssertEqual(fetched?.imageWidth, 800)
        XCTAssertEqual(fetched?.imageHeight, 450)
    }

    // MARK: - ContentHash (稳定内容哈希)

    func testContentHashDeterministic() {
        let data = "同一段内容".data(using: .utf8)!
        XCTAssertEqual(data.contentHash, data.contentHash)
        let other = "另一段内容".data(using: .utf8)!
        XCTAssertNotEqual(data.contentHash, other.contentHash)
    }

    func testContentHashStableAcrossInstances() {
        // 模拟跨进程:独立构造的相同 Data 必须算出相同哈希(不依赖进程随机种子)
        let a = Data("abc123".utf8).contentHash
        let b = Data("abc123".utf8).contentHash
        XCTAssertEqual(a, b)
    }

    func testContentHashNonNegative() {
        let data = Data((0..<256).map { UInt8($0) })
        XCTAssertGreaterThanOrEqual(data.contentHash, 0)
    }

    func testSQLManagerInsertInheritsPinnedDate() async {
        let manager = await makeTempManager()
        let data = "置顶内容-\(UUID().uuidString)".data(using: .utf8)!
        let hash = data.contentHash

        // 先插入一条并置顶
        let pinned = PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: hash, date: Date(),
            appPath: "", appName: "", dataString: "置顶内容", length: 4
        )
        await manager.insert(item: pinned)
        await manager.updatePinned(Date(), forHash: hash)

        // 重新捕获相同内容(新捕获恒无置顶),去重插入
        let recaptured = PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: hash, date: Date(),
            appPath: "", appName: "", dataString: "置顶内容", length: 4
        )
        await manager.insert(item: recaptured)

        // 去重插入后应仍保持置顶,且只有一行
        let results = await manager.fetchPage(limit: 100).items
        let fetched = results.filter { $0.hashValue == hash }
        XCTAssertEqual(fetched.count, 1, "去重插入后应只有一行")
        XCTAssertNotNil(fetched.first?.pinnedDate, "去重插入应继承旧行的置顶状态")
    }

    // MARK: - 表结构修复（清空数据后仍可写入）

    /// 回归：清空所有数据后新内容仍能写入（曾因重建的表缺 kindCode 列而全部插入失败）。
    func testClearAllDataThenInsertStillWorks() async {
        let manager = await makeTempManager()
        await manager.insert(item: makeTextModel(string: "清空前 \(UUID().uuidString)"))
        let before = await manager.totalCount
        XCTAssertEqual(before, 1)

        await manager.clearAllData()
        let afterClear = await manager.totalCount
        XCTAssertEqual(afterClear, 0)

        let newItem = makeTextModel(string: "#123456")
        let inserted = await manager.insert(item: newItem)
        XCTAssertTrue(inserted, "清空数据后仍应能写入")

        let afterInsert = await manager.totalCount
        XCTAssertEqual(afterInsert, 1)

        let results = await manager.fetchPage(limit: 10).items
        XCTAssertEqual(results.first?.hashValue, newItem.hashValue, "清空后写入的条目应能读回")
        XCTAssertEqual(results.first?.type, .color, "kindCode 应随写入落库")
    }

    /// 回归：清空后重启应用（同一路径重新 setup）仍能写入。
    func testClearAllDataThenRestartStillWorks() async {
        let path = NSTemporaryDirectory().appending("pd-tests-\(UUID().uuidString)/paste.sqlite3")

        let first = PasteSQLManager(dbPath: path)
        await first.setup()
        await first.insert(item: makeTextModel(string: "重启前"))
        await first.clearAllData()

        // 模拟重启：同一路径新建 manager 并 setup
        let second = PasteSQLManager(dbPath: path)
        await second.setup()

        let inserted = await second.insert(item: makeTextModel(string: "重启后"))
        XCTAssertTrue(inserted, "重启后仍应能写入")

        let count = await second.totalCount
        XCTAssertEqual(count, 1)
    }

    /// 幂等：重复 setup 不应因「列已存在 / 索引已存在」而失败。
    func testSetupIsIdempotent() async {
        let manager = await makeTempManager()
        await manager.setup()
        await manager.setup()

        let inserted = await manager.insert(item: makeTextModel(string: "幂等"))
        XCTAssertTrue(inserted)
    }

    /// 自愈：历史 bug 留下「表缺 kindCode、user_version 却已是 2」的库，
    /// setup 应按 PRAGMA 自检补列并回填，之后可正常写入。
    func testSetupRepairsLegacyDatabaseMissingKindCode() async throws {
        let path = NSTemporaryDirectory().appending("pd-tests-\(UUID().uuidString)/paste.sqlite3")
        try makeLegacyBrokenDatabase(at: path, text: "#FF5733")

        let manager = PasteSQLManager(dbPath: path)
        await manager.setup()

        // 补列后应回填旧数据的 kindCode(#FF5733 是颜色)
        let legacyRows = await manager.fetchPage(limit: 10).items
        XCTAssertEqual(legacyRows.count, 1)
        XCTAssertEqual(legacyRows.first?.type, .color, "旧数据应被回填为颜色类型")

        // 新写入不再触发「no such column: kindCode」
        let inserted = await manager.insert(item: makeTextModel(string: "修复后新内容"))
        XCTAssertTrue(inserted)

        let count = await manager.totalCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - 写入事务

    /// 回归：重新捕获相同内容时写入失败，旧行不能丢。
    func testInsertFailureRollsBackAndKeepsOldRow() async throws {
        let path = NSTemporaryDirectory().appending("pd-tests-\(UUID().uuidString)/paste.sqlite3")
        let manager = PasteSQLManager(dbPath: path)
        await manager.setup()

        let hash = 424_242
        let original = PasteboardModel(
            pasteboardType: .string, data: Data("原始内容".utf8), showData: nil,
            hashValue: hash, date: Date(), appPath: "", appName: "Test",
            dataString: "原始内容", length: 4
        )
        let firstInsert = await manager.insert(item: original)
        XCTAssertTrue(firstInsert)

        // 用触发器让后续 INSERT 必然失败，而 DELETE 仍会正常执行：
        // 不包事务时旧行就已被删掉，复现「旧行没了、新行没插上」的净丢失。
        try executeSQL(at: path, """
            CREATE TRIGGER fail_insert BEFORE INSERT ON pasteContent
            BEGIN SELECT RAISE(ABORT, 'insert blocked for test'); END;
            """)
        defer { try? executeSQL(at: path, "DROP TRIGGER IF EXISTS fail_insert;") }

        let recaptured = PasteboardModel(
            pasteboardType: .string, data: Data("新内容".utf8), showData: nil,
            hashValue: hash, date: Date(), appPath: "", appName: "Test",
            dataString: "新内容", length: 3
        )
        let failed = await manager.insert(item: recaptured)
        XCTAssertFalse(failed, "被触发器拦截时应报告写入失败")

        let count = await manager.totalCount
        XCTAssertEqual(count, 1, "事务回滚后应仍有一条")

        let rows = await manager.fetchPage(limit: 10).items
        XCTAssertEqual(rows.first?.dataString, "原始内容", "旧行必须保留，不能被删掉")
    }

    // MARK: - 游标分页 / upsert 去重

    private func makeDatedModel(_ text: String, minutesAgo: Double) -> PasteboardModel {
        let data = Data(text.utf8)
        return PasteboardModel(
            pasteboardType: .string, data: data, showData: nil,
            hashValue: data.contentHash, date: Date(timeIntervalSinceNow: -minutesAgo * 60),
            appPath: "", appName: "Test", dataString: text, length: text.count
        )
    }

    /// 游标翻页：两页之间没有重叠和遗漏，顺序是置顶在前、其余按时间倒序
    func testCursorPaginationCoversAllRowsInOrder() async {
        let manager = await makeTempManager()
        for i in 0..<25 {
            await manager.insert(item: makeDatedModel("item-\(i)", minutesAgo: Double(i)))
        }
        let pinned = makeDatedModel("item-24", minutesAgo: 24)
        await manager.updatePinned(Date(), forHash: pinned.hashValue)

        let first = await manager.fetchPage(limit: 20)
        XCTAssertEqual(first.items.count, 20)
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(first.items.first?.dataString, "item-24", "置顶项应排在最前")

        let second = await manager.fetchPage(after: first.cursor, limit: 20)
        XCTAssertEqual(second.items.count, 5)
        XCTAssertFalse(second.hasMore)

        let all = (first.items + second.items).map(\.dataString)
        XCTAssertEqual(Set(all).count, 25, "两页合起来应正好覆盖全部行，没有重复")
        let unpinned = all.dropFirst()
        XCTAssertEqual(Array(unpinned), (0..<24).map { "item-\($0)" }, "未置顶项应按时间倒序")
    }

    /// 回归：翻页中途有新内容进来，下一页不能跳过或重复（OFFSET 分页会错位）
    func testCursorPaginationStableWhenNewItemInserted() async {
        let manager = await makeTempManager()
        for i in 0..<30 {
            await manager.insert(item: makeDatedModel("item-\(i)", minutesAgo: Double(i + 1)))
        }
        let first = await manager.fetchPage(limit: 20)
        await manager.insert(item: makeDatedModel("新内容", minutesAgo: 0))
        let second = await manager.fetchPage(after: first.cursor, limit: 20)
        XCTAssertEqual(second.items.map(\.dataString), (20..<30).map { "item-\($0)" })
    }

    /// fetchThrough 取到游标（含）为止，用于原地刷新已加载范围
    func testFetchThroughStopsAtCursor() async {
        let manager = await makeTempManager()
        for i in 0..<10 {
            await manager.insert(item: makeDatedModel("item-\(i)", minutesAgo: Double(i + 1)))
        }
        let page = await manager.fetchPage(limit: 4)
        await manager.insert(item: makeDatedModel("新内容", minutesAgo: 0))
        let through = await manager.fetchThrough(keyword: "", state: .empty, cursor: page.cursor)
        XCTAssertEqual(through.map(\.dataString), ["新内容", "item-0", "item-1", "item-2", "item-3"])
    }

    /// upsert：重新捕获相同内容只更新这一行，时间刷新、行数不变
    func testInsertSameContentUpdatesDate() async {
        let manager = await makeTempManager()
        let old = makeDatedModel("重复内容", minutesAgo: 60)
        await manager.insert(item: old)
        await manager.insert(item: makeDatedModel("其他", minutesAgo: 30))
        await manager.insert(item: makeDatedModel("重复内容", minutesAgo: 0))

        let rows = await manager.fetchPage(limit: 10).items
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.dataString, "重复内容", "重新捕获后应排到最前")
    }

    /// 旧库 hashKey 只有普通索引且有重复行：setup 合并重复行（保留置顶）并建唯一索引
    func testSetupDeduplicatesLegacyRows() async throws {
        let path = NSTemporaryDirectory().appending("pd-tests-\(UUID().uuidString)/paste.sqlite3")
        let manager = PasteSQLManager(dbPath: path)
        await manager.setup()
        let stringType = NSPasteboard.PasteboardType.string.rawValue
        try executeSQL(at: path, """
            DROP INDEX index_pastecontent_on_hashkey;
            CREATE INDEX index_pastecontent_on_hashkey ON pasteContent(hashKey);
            INSERT INTO pasteContent(hashKey, type, data, date, appPath, appName, dataString, length, pinnedDate)
            VALUES (777, '\(stringType)', x'00', '2026-11-01T10:00:00.000', '', 'A', '旧', 1, '2026-11-02T10:00:00.000'),
                   (777, '\(stringType)', x'00', '2026-11-03T10:00:00.000', '', 'A', '新', 1, NULL);
            """)

        let reopened = PasteSQLManager(dbPath: path)
        await reopened.setup()
        let rows = await reopened.fetchPage(limit: 10).items
        XCTAssertEqual(rows.count, 1, "重复行应合并为一行")
        XCTAssertEqual(rows.first?.dataString, "新", "应保留最新的一行")
        XCTAssertNotNil(rows.first?.pinnedDate, "合并时应保留置顶状态")

        let inserted = await reopened.insert(item: PasteboardModel(
            pasteboardType: .string, data: Data([0]), showData: nil, hashValue: 777, date: Date(),
            appPath: "", appName: "A", dataString: "再次捕获", length: 4
        ))
        XCTAssertTrue(inserted, "建好唯一索引后 upsert 应能写入")
        let count = await reopened.totalCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - 测试辅助（造坏库 / 直连 SQL）

    /// 造一个「历史 bug 遗留」的坏库：表缺 kindCode 列，但 user_version 已是 2。
    /// 用系统 SQLite C API 直接建库，模拟旧版本 clearAllData 留下的真实状态。
    private func makeLegacyBrokenDatabase(at path: String, text: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let stringType = NSPasteboard.PasteboardType.string.rawValue
        // date / pinnedDate 由 SQLite.swift 以 TEXT 存储(yyyy-MM-dd'T'HH:mm:ss.SSS)，
        // 这里必须写同格式字符串，否则读回时 Date 解码失败、整行被丢弃。
        try executeSQL(at: path, """
            PRAGMA user_version = 2;
            CREATE TABLE pasteContent(
                id INTEGER PRIMARY KEY, hashKey INTEGER, type TEXT, data BLOB, showData BLOB,
                date TEXT, appPath TEXT, appName TEXT, dataString TEXT, length INTEGER,
                ocrText TEXT, imgW INTEGER, imgH INTEGER, pinnedDate TEXT
            );
            INSERT INTO pasteContent(hashKey, type, data, date, appPath, appName, dataString, length)
            VALUES (123456, '\(stringType)', x'00', '2026-11-01T10:00:00.000', '', 'Legacy', '\(text)', 7);
            """)
    }

    /// 直接对库执行 SQL（造触发器、写 PRAGMA 等测试专用操作）。
    private func executeSQL(at path: String, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "PasteDirectTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法打开测试数据库"])
        }
        defer { sqlite3_close(handle) }

        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            if let errorPointer { sqlite3_free(errorPointer) }
            throw NSError(domain: "PasteDirectTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
