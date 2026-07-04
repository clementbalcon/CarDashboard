import Contacts
import ContactsUI
import SwiftUI

struct SavedContact: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let phoneNumber: String

    init(id: UUID = UUID(), name: String, phoneNumber: String) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
    }

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

@MainActor
final class FavoriteContactsStore: ObservableObject {
    @Published private(set) var contacts: [SavedContact] = []

    private let defaultsKey = "favoriteContacts"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([SavedContact].self, from: data) {
            contacts = decoded
        }
    }

    func add(name: String, phoneNumber: String) {
        let normalized = Self.digits(phoneNumber)
        guard !normalized.isEmpty,
              !contacts.contains(where: { Self.digits($0.phoneNumber) == normalized }) else { return }
        contacts.append(SavedContact(name: name, phoneNumber: phoneNumber))
        save()
    }

    func remove(_ contact: SavedContact) {
        contacts.removeAll { $0.id == contact.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func digits(_ number: String) -> String {
        number.filter(\.isNumber)
    }
}

/// Wraps CNContactPickerViewController. The picker runs out-of-process, so it needs no
/// Contacts permission — the app only ever receives the single contact the user taps.
struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (_ name: String, _ phoneNumber: String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (_ name: String, _ phoneNumber: String) -> Void
        init(onPick: @escaping (_ name: String, _ phoneNumber: String) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Contact"
            let number = contact.phoneNumbers.first?.value.stringValue ?? ""
            onPick(name, number)
        }
    }
}
