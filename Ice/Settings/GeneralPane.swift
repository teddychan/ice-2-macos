//
//  GeneralPane.swift
//  Ice
//

import DragonKit
import SwiftUI

/// The General pane: Startup, Language, the Ice icon, then the menu bar items.
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
            DragonSection {
                Text(L("app.general.startup"))
            } content: {
                Toggle(L("app.general.launchAtLogin"), isOn: $model.launchAtLogin)
            } footer: {
                EmptyView()
            }
            // DragonKit's picker, called bare: Ice ships every language the kit does, and
            // CONFORMANCE §R13 requires the offered set to equal the shipped set.
            DragonSection {
                Text(L("app.general.language"))
            } content: {
                LanguagePicker(onChange: { model.languageChanged(to: $0) })
            } footer: {
                EmptyView()
            }
            DragonSection {
                Text(L("app.general.menuBar"))
            } content: {
                Toggle(L("app.general.showInMenuBar"), isOn: $model.showInMenuBar)
            } footer: {
                Text(L("app.general.showInMenuBarHint"))
            }
            // The note is the section's footer: wrapping the section in a modifier hides it from
            // the Form, which then draws the header inside the box.
            DragonSection {
                Text(L("app.general.items"))
            } content: {
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
                .onMove { model.moveListed(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text(L("app.general.items.note"))
            }
        }
    }
}

private struct ItemRow: View {
    let item: MenuBarItem
    let model: SettingsModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
        .contextMenu {
            if item.bundleIdentifier != nil {
                Button(L("app.general.items.remove"), role: .destructive) {
                    model.remove(item)
                }
            }
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
