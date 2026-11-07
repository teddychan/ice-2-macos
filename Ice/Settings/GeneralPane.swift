//
//  GeneralPane.swift
//  Ice
//

import DragonKit
import SwiftUI

/// The General pane: Startup, then the menu bar items.
struct GeneralPane: SettingsPane {
    static let paneID = "general"

    let id = GeneralPane.paneID
    let title = "app.nav.general"
    let systemImage = "gearshape"
    let model: SettingsModel

    var paneBody: some View { GeneralPaneView(model: model) }
}

private struct GeneralPaneView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        DragonForm {
            DragonSection(LocalizedStringKey(L("app.general.startup"))) {
                Toggle(L("app.general.launchAtLogin"), isOn: $model.launchAtLogin)
            }
        }
    }
}
