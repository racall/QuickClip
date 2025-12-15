//
//  设置项通用行组件
//  快速剪贴
//
//  用途：统一设置项的布局结构，便于复用与扩展
//

import SwiftUI

/// 设置项通用行组件（左侧图标 + 标题，右侧自定义控件）
struct SettingsItemRow<Accessory: View>: View {
    let systemImageName: String
    let title: String
    @ViewBuilder let accessory: () -> Accessory

    init(systemImageName: String, title: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.systemImageName = systemImageName
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 4) {
                Image(systemName: systemImageName)
                Text(title)
                    .foregroundColor(.primary)
            }
            Spacer()
            accessory()
        }
        .padding(12)
    }
}

