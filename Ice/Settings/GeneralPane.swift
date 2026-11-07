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
    let menuBar: MenuBarController

    var paneBody: some View { GeneralPaneView(model: model, menuBar: menuBar) }
}

private struct GeneralPaneView: View {
    @Bindable var model: SettingsModel
    let menuBar: MenuBarController

    var body: some View {
        DragonForm {
            DragonSection(LocalizedStringKey(L("app.general.startup"))) {
                Toggle(L("app.general.launchAtLogin"), isOn: $model.launchAtLogin)
            }
            DragonSection(LocalizedStringKey(L("app.general.items"))) {
                if let message = menuBar.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                if model.listedItems.isEmpty {
                    Text(L("app.general.items.empty"))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.listedItems) { item in
                    ItemRow(item: item, model: model)
                }
            }
            .dragonAnnotation(LocalizedStringKey(L("app.general.items.note")))
        }
    }
}

private struct ItemRow: View {
    let item: MenuBarItem
    let model: SettingsModel

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: item, size: 20)
            Text(ItemAppearance.name(for: item))
            Spacer()
            Picker(ItemAppearance.name(for: item), selection: Binding(
                get: { model.isHidden(item) },
                set: { model.setHidden($0, for: item) }
            )) {
                Text(L("app.general.items.show")).tag(false)
                Text(L("app.general.items.hide")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// An item's icon at a fixed size: the app icon, or a template symbol for a system item.
struct ItemIcon: View {
    let item: MenuBarItem
    let size: CGFloat

    var body: some View {
        let image = ItemAppearance.icon(for: item)
        Image(nsImage: image)
            .resizable()
            .renderingMode(image.isTemplate ? .template : .original)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
