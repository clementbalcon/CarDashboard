import SwiftUI
import UIKit

struct ContactsWidgetView: DashboardWidget {
    static let widgetTitle = "Appels rapides"
    static let widgetSystemImage = "phone"

    @StateObject private var store = FavoriteContactsStore()
    @State private var isPickerPresented = false

    var body: some View {
        WidgetCard(title: Self.widgetTitle, systemImage: Self.widgetSystemImage) {
            GeometryReader { proxy in
                let columns = max(2, min(5, Int(proxy.size.width / 96)))
                let grid = Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
                ScrollView {
                    LazyVGrid(columns: grid, spacing: 12) {
                        ForEach(store.contacts) { contact in
                            contactButton(contact)
                        }
                        addButton
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            ContactPicker { name, number in
                store.add(name: name, phoneNumber: number)
            }
            .ignoresSafeArea()
        }
    }

    private func contactButton(_ contact: SavedContact) -> some View {
        Button {
            call(contact)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.25))
                    Text(contact.initials)
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .frame(width: 52, height: 52)
                Text(contact.firstName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.remove(contact)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private var addButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 52, height: 52)
                Text("Ajouter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func call(_ contact: SavedContact) {
        let sanitized = contact.phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(sanitized)") else { return }
        UIApplication.shared.open(url)
    }
}
