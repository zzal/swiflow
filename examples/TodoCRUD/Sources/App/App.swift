import SwiflowDOM
import SwiflowUI
import SwiflowQuery
import SwiflowFetcher

/// The CRUD API, configured once. Point `baseURL` elsewhere to target another
/// host/port; queries and mutations call it with relative paths.
let api = HTTPClient(baseURL: "http://localhost:8080")

// MARK: - Model

struct Todo: Decodable, Equatable, Sendable {
    let id: Int
    let title: String
    let done: Bool
}

// MARK: - Query

@QueryType(prefix: "todos") struct TodoList: Query {
    var tags: Set<QueryTag> { ["todos"] }
    var refetchInterval: Duration? { .seconds(5) }   // live polling against the real API
    func fetch() async throws -> [Todo] {
        try await api.get("/todos", as: [Todo].self)
    }
}

// MARK: - Mutations

@MutationType struct AddTodo: Mutation {
    /// Monotonic temp-id source for optimistic rows (negative so it never
    /// collides with a real server id). The `["todos"]` refetch replaces it.
    static var tempSeq = -1

    func perform(_ title: String) async throws -> Todo {
        try await api.post("/todos", json: ["title": .string(title)], as: Todo.self)
    }
    func optimistic(_ title: String) -> [OptimisticEdit] {
        let tmp = AddTodo.tempSeq; AddTodo.tempSeq -= 1
        return [.update(TodoList()) { $0 + [Todo(id: tmp, title: title, done: false)] }]
    }
    func invalidations(input: String, output: Todo) -> [Invalidation] { [.exact(["todos"])] }
}

@MutationType struct ToggleTodo: Mutation {
    struct Input: Sendable { let id: Int; let done: Bool }
    func perform(_ i: Input) async throws -> Todo {
        try await api.put("/todos/\(i.id)", json: ["done": .bool(i.done)], as: Todo.self)
    }
    func optimistic(_ i: Input) -> [OptimisticEdit] {
        [.update(TodoList()) { todos in
            todos.map { $0.id == i.id ? Todo(id: $0.id, title: $0.title, done: i.done) : $0 }
        }]
    }
    func invalidations(input: Input, output: Todo) -> [Invalidation] { [.exact(["todos"])] }
}

@MutationType struct DeleteTodo: Mutation {
    func perform(_ id: Int) async throws {
        try await api.delete("/todos/\(id)")
    }
    func optimistic(_ id: Int) -> [OptimisticEdit] {
        [.update(TodoList()) { $0.filter { $0.id != id } }]
    }
    func invalidations(input: Int, output: Void) -> [Invalidation] { [.exact(["todos"])] }
}

// MARK: - Component

@MainActor @Component
final class TodoApp {
    @State var draft: String = ""
    @MutationState var add: AddTodo
    @MutationState var toggle: ToggleTodo
    @MutationState var remove: DeleteTodo

    init() {
        self.add = AddTodo()
        self.toggle = ToggleTodo()
        self.remove = DeleteTodo()
    }

    var body: VNode {
        let list = query(TodoList())
        return VStack(spacing: .lg, align: .stretch) {
            h1("Todo CRUD")
            p("Reads via query(); writes via @MutationState with optimistic updates — against a real Bun + SQLite API.")

            // Add bar: a SwiflowUI TextField + Button; `align: .end` bottom-aligns
            // the button with the input (the field's label sits above it).
            HStack(spacing: .sm, align: .end) {
                TextField("New todo", text: $draft, placeholder: "What needs doing?")
                    .style("flex", "1")
                Button("Add", disabled: $add.isPending) {
                    let t = self.draft
                    guard !t.isEmpty, !t.allSatisfy(\.isWhitespace) else { return }
                    self.$add.mutate(t)
                    self.draft = ""
                }
                if list.isFetching { Spinner(size: .sm, label: "Syncing") }
            }

            if list.isLoading { p("Loading…") }
            if let e = list.error { p("Failed to load: \(e)") }
            if $add.isError { p("Add failed.") }
            if $toggle.isError { p("Toggle failed.") }
            if $remove.isError { p("Delete failed.") }

            if let todos = list.data {
                VStack(spacing: .sm, align: .stretch) {
                    for todo in todos {
                        // Keyed row: the checkbox carries the title as its label
                        // (toggling either toggles done); ✕ deletes.
                        HStack(spacing: .sm, align: .center, justify: .between, .key("todo-\(todo.id)")) {
                            Checkbox(todo.title, isOn: Binding(get: { todo.done },
                                                              set: { self.$toggle.mutate(.init(id: todo.id, done: $0)) }))
                            Button("✕", variant: .ghost, size: .sm,
                                   .attr("aria-label", "Delete \(todo.title)")) { self.$remove.mutate(todo.id) }
                        }
                    }
                }
            }
        }
        .padding(.xl)
        .style("max-width", "40rem")
        .style("margin", "0 auto")
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { TodoApp() }
    }
}
