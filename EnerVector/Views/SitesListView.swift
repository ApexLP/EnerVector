import PhotosUI
import SwiftData
import SwiftUI

struct SitesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Site.name) private var sites: [Site]
    @State private var search = ""
    @State private var filter: Discipline?
    @State private var showNewSite = false

    private var filtered: [Site] {
        sites.filter { site in
            (filter == nil || site.discipline == filter)
                && (search.isEmpty || site.name.localizedCaseInsensitiveContains(search)
                    || site.address.localizedCaseInsensitiveContains(search)
                    || site.client.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { site in
                NavigationLink(value: site) {
                    HStack(spacing: 12) {
                        DisciplineThumbnail(site: site)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.name).font(.headline)
                            Text([site.client, site.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            LinearProgress(value: site.progress, color: site.discipline.color, height: 4)
                        }
                        Text(Units.percent(site.progress)).font(.subheadline.bold()).monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(filtered[i]) }
                try? context.save()
            }
        }
        .overlay {
            if sites.isEmpty {
                ContentUnavailableView("No sites", systemImage: "building.2", description: Text("Tap + to add your first site."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search sites, clients, addresses")
        .navigationTitle("Sites")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewSite = true } label: { Label("New Site", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Picker("Discipline", selection: $filter) {
                    Text("All disciplines").tag(Discipline?.none)
                    ForEach(Discipline.allCases) { Text($0.rawValue).tag(Discipline?.some($0)) }
                }
            }
        }
        .sheet(isPresented: $showNewSite) { SiteEditorView() }
    }
}

struct SiteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var site: Site?

    @State private var name = ""
    @State private var client = ""
    @State private var address = ""
    @State private var discipline: Discipline = .electrical
    @State private var notes = ""
    @State private var photo: Data?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Site") {
                    TextField("Site name", text: $name)
                    TextField("Client", text: $client)
                    TextField("Address or city", text: $address)
                    Picker("Discipline", selection: $discipline) {
                        ForEach(Discipline.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("Cover photo") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        if let photo, let image = UIImage(data: photo) {
                            Image(uiImage: image).resizable().scaledToFill().frame(height: 140).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Label("Choose photo", systemImage: "photo")
                        }
                    }
                }
                Section("Notes") {
                    TextField("Scope, contacts, access notes…", text: $notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle(site == nil ? "New Site" : "Edit Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let site else { return }
                name = site.name; client = site.client; address = site.address
                discipline = site.discipline; notes = site.notes; photo = site.coverPhoto
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photo = image.storageJPEG()
                    }
                }
            }
        }
    }

    private func save() {
        let target = site ?? Site(name: name, discipline: discipline)
        if site == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.client = client
        target.address = address
        target.discipline = discipline
        target.notes = notes
        target.coverPhoto = photo
        try? context.save()
        dismiss()
    }
}
