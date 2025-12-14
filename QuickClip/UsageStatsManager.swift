//
//  用户统计管理器
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import Foundation
import CloudKit
import CryptoKit

/// 用户统计管理器
/// 负责上传匿名使用统计数据到 CloudKit Public Database
@MainActor
final class UsageStatsManager {

    // MARK: - 属性

    private let container: CKContainer
    private let publicDatabase: CKDatabase

    /// UserDefaults 键
    private let recordNameKey = "userStatsRecordName"

    // MARK: - 初始化

    init() {
        self.container = CKContainer(identifier: "iCloud.io.0os.QuickClip")
        self.publicDatabase = container.publicCloudDatabase
    }

    // MARK: - 公开接口

    /// 上传或更新统计数据
    func uploadOrUpdateStats() async throws {
        // 检查是否已有记录
        if let recordName = UserDefaults.standard.string(forKey: recordNameKey) {
            // 已有记录，执行更新
            do {
                try await updateExistingRecord(recordName: recordName)
                print("✅ 用户统计数据已更新")
            } catch let error as CKError where error.code == .unknownItem {
                // 记录不存在（被删除），清除缓存并重新创建
                print("⚠️ 统计记录不存在，重新创建")
                UserDefaults.standard.removeObject(forKey: recordNameKey)
                try await createNewRecord()
            }
        } else {
            // 首次启动，创建新记录
            try await createNewRecord()
            print("✅ 用户统计数据已创建")
        }
    }

    // MARK: - 私有方法

    /// 创建新的统计记录（首次启动）
    private func createNewRecord() async throws {
        // 1. 获取 userRecordID
        let userRecordID = try await container.userRecordID()
        let recordName = userRecordID.recordName

        // 2. 计算 MD5 作为 uid
        let uid = md5(recordName)

        // 3. 获取系统和 App 信息
        let osVersion = getOSVersion()
        let appVersion = getAppVersion()
        let now = Date()

        // 4. 创建 CloudKit 记录
        let record = CKRecord(recordType: "UsingUsers")
        record["uid"] = uid
        record["os"] = osVersion
        record["sv"] = appVersion
        record["firstSendDate"] = now
        record["sendDate"] = now

        // 5. 保存到 CloudKit Public Database
        let savedRecord = try await publicDatabase.save(record)

        // 6. 保存 recordName 到 UserDefaults
        UserDefaults.standard.set(savedRecord.recordID.recordName, forKey: recordNameKey)

        print("📊 统计数据已创建: uid=\(uid), os=\(osVersion), sv=\(appVersion)")
    }

    /// 更新已有的统计记录（后续启动）
    private func updateExistingRecord(recordName: String) async throws {
        // 1. 获取已有记录
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await publicDatabase.record(for: recordID)

        // 2. 更新字段（uid 和 firstSendDate 保持不变）
        record["os"] = getOSVersion()
        record["sv"] = getAppVersion()
        record["sendDate"] = Date()

        // 3. 保存到 CloudKit
        _ = try await publicDatabase.save(record)

        print("📊 统计数据已更新: os=\(getOSVersion()), sv=\(getAppVersion())")
    }

    /// 获取系统版本
    private func getOSVersion() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return osVersion
    }

    /// 获取 App 版本号
    private func getAppVersion() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return appVersion
    }

    /// 计算字符串的 MD5 哈希值
    private func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
