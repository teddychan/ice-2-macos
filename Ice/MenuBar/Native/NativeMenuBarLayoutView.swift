//
//  NativeMenuBarLayoutView.swift
//  Ice
//

import DragonKit
import SwiftUI
import UniformTypeIdentifiers

/// A private payload prevents unrelated text or files from changing assignments.
enum NativeMenuBarDrag {
    static let type = UTType(exportedAs: "com.dragonapp.ice.section-assignment", conformingTo: .data)
}

struct NativeMenuBarLayoutView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager: NativeMenuBarManager
    @State private var targetedSection: MenuBarSection.Name?
    @State private var feedback = ""

    var body: some View {
        DragonSection {
            Text(L("app.native.editor.title"))
        } content: {
            Text(L("app.native.editor.instructions"))
            Text(L("app.native.editor.grouping"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(L("app.native.editor.refresh")) {
                    Task { await manager.refresh() }
                }
                .disabled(manager.isRefreshing)
                if manager.isRefreshing { ProgressView().controlSize(.small) }
            }
        }
        VStack(spacing: 12) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                sectionEditor(section)
            }
            if !feedback.isEmpty {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("native-layout-feedback")
            }
        }
        visibilityControls
        if manager.items.contains(where: { !$0.canAssign }) {
            DragonSection {
                Text(L("app.native.systemManaged"))
            } content: {
                Text(manager.items.filter { !$0.canAssign }.map(\.name).joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionEditor(_ section: MenuBarSection.Name) -> some View {
        let items = manager.items.filter { $0.canAssign && (manager.assignments[$0.id] ?? .visible) == section }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(section.localized).font(.headline)
                Text("\(items.count)").foregroundStyle(.secondary)
                Spacer()
            }
            Text(L("app.native.editor.\(section.rawValue)"))
                .font(.callout)
                .foregroundStyle(.secondary)
            if items.isEmpty {
                Text(L("app.native.editor.dropHere"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)], spacing: 8) {
                    ForEach(items) { item in
                        itemCard(item)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(targetedSection == section ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targetedSection == section ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: targetedSection == section ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onDrop(of: [NativeMenuBarDrag.type], delegate: NativeMenuBarSectionDropDelegate(
            move: { move($0, to: section) },
            target: { targeted in
                if targeted { targetedSection = section } else if targetedSection == section { targetedSection = nil }
            }
        ))
        .accessibilityIdentifier("native-section-\(section.rawValue)")
    }

    private func itemCard(_ item: NativeMenuBarItem) -> some View {
        HStack(spacing: 9) {
            if let icon = manager.appIcons[item.id] {
                Image(nsImage: icon)
                    .resizable().scaledToFit()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: item.fallbackSymbol)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.displayName(for: item))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(L(manager.appIcons[item.id] != nil ? "app.native.editor.appIcon" : "app.native.editor.noPreview"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                moveActions(for: item)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .accessibilityLabel(String(format: L("app.native.editor.moveApp"), manager.displayName(for: item)))
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            NativeMenuBarDragSource(id: item.id, name: manager.displayName(for: item), icon: manager.appIcons[item.id])
                .padding(.trailing, 36)
                .accessibilityHidden(true)
        }
        .help(manager.displayName(for: item) + "\n" + L("app.native.editor.cardHelp"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(manager.displayName(for: item))
        .accessibilityHint(L("app.native.editor.cardHelp"))
        .accessibilityIdentifier("native-item-\(item.id)")
    }

    @ViewBuilder
    private func moveActions(for item: NativeMenuBarItem) -> some View {
        ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
            Button(String(format: L("app.native.editor.moveTo"), section.localized)) {
                _ = move(item.id, to: section)
            }
            .disabled((manager.assignments[item.id] ?? .visible) == section)
        }
    }

    @discardableResult
    private func move(_ id: String, to section: MenuBarSection.Name) -> Bool {
        guard let item = manager.items.first(where: { $0.id == id }), manager.moveItem(id: id, to: section) else { return false }
        feedback = String(format: L("app.native.editor.moved"), manager.displayName(for: item), section.localized)
        NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [
            .announcement: feedback,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
        return true
    }

    private var visibilityControls: some View {
        DragonSection {
            Text(L("app.native.editor.visibility"))
        } content: {
            Text(L("app.native.editor.visibilityNote"))
                .font(.callout)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { revealButtons }
                VStack(alignment: .leading) { revealButtons }
            }
            Button(L("app.native.editor.hideBoth")) {
                // Set both explicitly, including when Hidden was already concealed.
                for section in appState.menuBarManager.sections {
                    section.controlItem.state = .hideSection
                }
                manager.synchronizeVisibility()
            }
            Text(L("app.native.limitations"))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let message = manager.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            if let notice = manager.profileNotice {
                Text(notice).font(.callout)
            }
        }
    }

    @ViewBuilder
    private var revealButtons: some View {
        Button(L("app.native.editor.showHidden")) {
            appState.menuBarManager.section(withName: .hidden)?.show()
        }
        Button(L("app.native.editor.showAll")) {
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .showSection
            }
            manager.synchronizeVisibility()
        }
    }
}

private struct NativeMenuBarSectionDropDelegate: DropDelegate {
    let move: (String) -> Bool
    let target: (Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [NativeMenuBarDrag.type])
    }

    func dropEntered(info: DropInfo) { target(true) }
    func dropExited(info: DropInfo) { target(false) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        target(false)
        let providers = info.itemProviders(for: [NativeMenuBarDrag.type])
        guard providers.count == 1, let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: NativeMenuBarDrag.type.identifier) { data, _ in
            guard let data, let id = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in _ = move(id) }
        }
        return true
    }
}
