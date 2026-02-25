import SwiftUI
import CoreData

struct KnowledgeBrowserView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var selectedCategory: KnowledgeCategory?
    @State private var atoms: [KnowledgeAtomMO] = []

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search knowledge base...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performSearch() }
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(Optional<KnowledgeCategory>.none)
                    ForEach(KnowledgeCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(Optional(cat))
                    }
                }
                .frame(width: 150)
            }
            .padding()

            if atoms.isEmpty {
                ContentUnavailableView("No Knowledge Yet", systemImage: "brain", description: Text("Record a meeting to start extracting knowledge"))
            } else {
                List(filteredAtoms, id: \.id) { atom in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(atom.content).font(.body)
                        HStack {
                            Text(atom.category)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1))
                                .cornerRadius(4)
                            Text(atom.confidence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let speaker = atom.speaker {
                                Text("- \(speaker)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(atom.timestamp, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let quote = atom.sourceQuote, !quote.isEmpty {
                            Text("\"\(quote)\"")
                                .font(.caption).italic()
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Knowledge Base")
        .onAppear { loadAtoms() }
    }

    private var filteredAtoms: [KnowledgeAtomMO] {
        atoms.filter { atom in
            let matchesSearch = searchText.isEmpty ||
                atom.content.localizedCaseInsensitiveContains(searchText) ||
                (atom.sourceQuote?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesCategory = selectedCategory == nil ||
                atom.category == selectedCategory?.rawValue
            return matchesSearch && matchesCategory
        }
    }

    private func loadAtoms() {
        let store = DataStore(context: viewContext)
        atoms = (try? store.fetchKnowledgeAtoms()) ?? []
    }

    private func performSearch() {
        if searchText.isEmpty {
            loadAtoms()
        } else {
            let store = DataStore(context: viewContext)
            atoms = (try? store.searchKnowledgeAtoms(query: searchText)) ?? []
        }
    }
}
