import SwiflowWeb
import SwiflowQuery
import JavaScriptKit

/// Backend base URL. Point this elsewhere to target another host/port.
let apiBase = "http://localhost:8080"

// MARK: - Model

struct Todo: Decodable, Equatable, Sendable {
    let id: Int
    let title: String
    let done: Bool
}

// MARK: - Query

struct TodoList: Query {
    var queryKey: QueryKey { ["todos"] }
    var tags: Set<QueryTag> { ["todos"] }
    func fetch() async throws -> [Todo] {
        try await Net.get("\(apiBase)/todos", as: [Todo].self)
    }
}

// MARK: - Mutations

struct AddTodo: Mutation {
    /// Monotonic temp-id source for optimistic rows (negative so it never
    /// collides with a real server id). The `["todos"]` refetch replaces it.
    static var tempSeq = -1

    func perform(_ title: String) async throws -> Todo {
        try await Net.send(.POST, "\(apiBase)/todos", json: ["title": .string(title)], as: Todo.self)
    }
    func optimistic(_ title: String) -> [OptimisticEdit] {
        let tmp = AddTodo.tempSeq; AddTodo.tempSeq -= 1
        return [.update(TodoList()) { $0 + [Todo(id: tmp, title: title, done: false)] }]
    }
    func invalidations(input: String, output: Todo) -> [Invalidation] { [.exact(["todos"])] }
}

struct ToggleTodo: Mutation {
    struct Input: Sendable { let id: Int; let done: Bool }
    func perform(_ i: Input) async throws -> Todo {
        try await Net.send(.PUT, "\(apiBase)/todos/\(i.id)", json: ["done": .bool(i.done)], as: Todo.self)
    }
    func optimistic(_ i: Input) -> [OptimisticEdit] {
        [.update(TodoList()) { todos in
            todos.map { $0.id == i.id ? Todo(id: $0.id, title: $0.title, done: i.done) : $0 }
        }]
    }
    func invalidations(input: Input, output: Todo) -> [Invalidation] { [.exact(["todos"])] }
}

struct DeleteTodo: Mutation {
    func perform(_ id: Int) async throws {
        try await Net.send(.DELETE, "\(apiBase)/todos/\(id)")
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
        return div {
            h1("Todo CRUD")
            p("Reads via query(); writes via @MutationState with optimistic updates — against a real Bun + SQLite API.")

            div {
                input(.value($draft), .attr("placeholder", "New todo…"),
                      .on(.input) { self.draft = $0.targetValue ?? "" })
                button("Add", .on(.click) {
                    let t = self.draft
                    guard !t.isEmpty, !t.allSatisfy(\.isWhitespace) else { return }
                    self.$add.mutate(t)
                    self.draft = ""
                }, .attr("disabled", $add.isPending))
                if list.isFetching { span { text(" ⟳ syncing…") } }
            }

            if list.isLoading { p("Loading…") }
            if let e = list.error { p("Failed to load: \(e)") }
            if $add.isError { p("Add failed.") }
            if $toggle.isError { p("Toggle failed.") }
            if $remove.isError { p("Delete failed.") }

            if let todos = list.data {
                ul {
                    for todo in todos {
                        li(.key("todo-\(todo.id)")) {
                            input(.attr("type", "checkbox"),
                                  .checked(Binding(get: { todo.done },
                                                   set: { self.$toggle.mutate(.init(id: todo.id, done: $0)) })))
                            span { text(todo.title) }
                            button("✕", .on(.click) { self.$remove.mutate(todo.id) })
                        }
                    }
                }
            }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { TodoApp() }
    }
}
