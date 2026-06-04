import Foundation
import IOKit

// SMC 鍵資料協定常數(SMCKit / stats / iStat Menus 通用)。
private let kSMCHandleYPCEvent: UInt32 = 2   // IOConnectCallStructMethod selector
private let kSMCReadKey: UInt8 = 5           // data8:讀鍵值
private let kSMCGetKeyInfo: UInt8 = 9        // data8:查鍵的大小/型別
private let kSMCSuccess: UInt8 = 0           // result 成功碼

// SMC dataType FourCC(以 4-char 打包後比對)。
private let kSMCTypeFlt: UInt32 = fourCC("flt ")
private let kSMCTypeFpe2: UInt32 = fourCC("fpe2")

// 佈局守門(一次性):結構須與 C `SMCKeyData_t` 二進位相容(80 bytes)。
// assert 於 release 編譯移除,僅在 debug 攔截意外的佈局變動。
private let _smcLayoutCheck: Void = {
    assert(MemoryLayout<SMCKeyData>.stride == 80, "SMCKeyData layout drift")
}()

/// 把 4 字元字串打包成 SMC 用的大端 FourCC(b0<<24 | b1<<16 | b2<<8 | b3)。
/// 不足 4 字元以 0 補尾、超過則只取前 4。非 ASCII 字元位元組以 0 視之。
private func fourCC(_ s: String) -> UInt32 {
    let bytes = Array(s.utf8.prefix(4))
    var v: UInt32 = 0
    for i in 0..<4 {
        let b = i < bytes.count ? UInt32(bytes[i]) : 0
        v = (v << 8) | b
    }
    return v
}

// C `SMCKeyData_vers_t`(major/minor/build/reserved: UInt8 + release: UInt16)。
// 欄位與 SMCKit `SMCVersion` 完全一致;外層結構對齊使其後出現 2-byte 填補。
private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

// C `SMCKeyData_pLimitData_t`(16 bytes)。
private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

// C `SMCKeyData_keyInfo_t`(dataSize/dataType: UInt32 + dataAttributes: UInt8,
// 含尾端填補)。欄位與 SMCKit `SMCKeyInfoData` 完全一致。
private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

/// C `SMCKeyData_t`(= SMCKit `SMCParamStruct`):IOConnectCallStructMethod 的輸入/輸出結構。
///
/// - Important: 必須與 C `SMCKeyData_t` **二進位相容**,stride 恆為 **80 bytes**。
///   欄位順序/大小須與核心驅動逐一對齊,否則 `data8`/`result`/`keyInfo`/`bytes`
///   會落在錯誤偏移——在無風扇機型恰好回 [](看不出),卻會在「有風扇」機型讀出垃圾。
///   `keyInfo` 與 `result` 之間有 SMCKit 明定的 `padding: UInt16`;`read()` 入口以
///   `assert(stride == 80)` 守門,避免未來意外更動佈局。
private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// 透過 AppleSMC 讀風扇轉速。無風扇(如 MacBook Air)回 []。
///
/// 使用經典 SMC 鍵資料協定:先以 `kSMCGetKeyInfo` 查鍵的大小/型別,
/// 再以 `kSMCReadKey` 讀位元組,依 dataType(`flt` 小端 / `fpe2` 大端定點)解碼。
///
/// - Important: AppleSMC 為公開 IOService,但鍵語意/型別屬非正式約定;
///   新機型上市時應重新驗證鍵與型別。
/// - Warning: 非執行緒安全(持有 io_connect_t),須由單一串行佇列驅動
///   (MetricsStore 計時器)。請勿並發呼叫 read()。
public final class SMCFanSource: FanSource {
    private var conn: io_connect_t = 0

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        // 開啟連線;失敗則 conn 維持 0,read() 直接回 []。
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        if result != kIOReturnSuccess { conn = 0 }
        _ = _smcLayoutCheck   // 觸發一次性佈局守門。
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    public func read() -> [Int] {
        guard conn != 0 else { return [] }
        guard let count = readFanCount(), count > 0, count < 64 else { return [] }

        var rpms: [Int] = []
        for i in 0..<count {
            guard let rpm = readFanRPM(index: i) else { continue }
            // 過濾無效/停轉讀數。
            guard rpm.isFinite, rpm > 0 else { continue }
            rpms.append(Int(rpm.rounded()))
        }
        return rpms
    }

    // MARK: - SMC 讀取原語

    /// 讀 `FNum`(風扇數,ui8/ui16,大端)。讀不到回 nil。
    private func readFanCount() -> Int? {
        guard let (data, info) = readKeyBytes(fourCC("FNum")) else { return nil }
        return Int(decodeUInt(data, size: Int(info.dataSize)))
    }

    /// 讀第 i 個風扇的實際轉速 `F{i}Ac`,依 dataType 解碼為 RPM。
    private func readFanRPM(index: Int) -> Double? {
        guard let (data, info) = readKeyBytes(fourCC("F\(index)Ac")) else { return nil }
        return decodeRPM(data, type: info.dataType)
    }

    /// SMC 讀鍵完整流程:GetKeyInfo 取大小/型別 → ReadKey 取位元組。
    /// 任一步失敗(IOKit 錯誤或 SMC result 非 0)回 nil。
    private func readKeyBytes(_ key: UInt32) -> (bytes: [UInt8], info: SMCKeyInfoData)? {
        // 第一步:查鍵資訊。
        var infoIn = SMCKeyData()
        infoIn.key = key
        infoIn.data8 = kSMCGetKeyInfo
        guard let infoOut = callSMC(infoIn), infoOut.result == kSMCSuccess else { return nil }
        let info = infoOut.keyInfo
        guard info.dataSize > 0, info.dataSize <= 32 else { return nil }

        // 第二步:讀鍵值。
        var readIn = SMCKeyData()
        readIn.key = key
        readIn.data8 = kSMCReadKey
        readIn.keyInfo.dataSize = info.dataSize
        guard let readOut = callSMC(readIn), readOut.result == kSMCSuccess else { return nil }

        let bytes = bytesArray(readOut.bytes, count: Int(info.dataSize))
        return (bytes, info)
    }

    /// 實際發出 IOConnectCallStructMethod。輸入/輸出皆為 SMCKeyData。
    private func callSMC(_ input: SMCKeyData) -> SMCKeyData? {
        var inputStruct = input
        var outputStruct = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            conn, kSMCHandleYPCEvent,
            &inputStruct, MemoryLayout<SMCKeyData>.stride,
            &outputStruct, &outputSize)
        guard result == kIOReturnSuccess else { return nil }
        return outputStruct
    }

    // MARK: - 解碼輔助

    /// 把 32-byte tuple 的前 count 個位元組轉成陣列。
    private func bytesArray(_ tuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
                            count: Int) -> [UInt8] {
        withUnsafeBytes(of: tuple) { Array($0.prefix(count)) }
    }

    /// 解無號整數(大端,1–4 bytes)。
    private func decodeUInt(_ bytes: [UInt8], size: Int) -> UInt32 {
        var v: UInt32 = 0
        for b in bytes.prefix(min(size, 4)) { v = (v << 8) | UInt32(b) }
        return v
    }

    /// 依 SMC dataType 把位元組解成 RPM 浮點:
    /// - `flt`:4-byte Float32,**小端**。
    /// - `fpe2`:2-byte 大端定點,value = (b0<<8|b1)/4。
    /// 未知型別回 nil。
    private func decodeRPM(_ bytes: [UInt8], type: UInt32) -> Double? {
        switch type {
        case kSMCTypeFlt:
            guard bytes.count >= 4 else { return nil }
            // flt 為小端:直接以原序載入 Float32。
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        case kSMCTypeFpe2:
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt32(bytes[0]) << 8) | UInt32(bytes[1])
            return Double(raw) / 4.0
        default:
            return nil
        }
    }
}
