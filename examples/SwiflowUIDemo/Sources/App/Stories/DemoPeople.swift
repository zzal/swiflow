// Shared sample data for the DataTable stories (paged + virtualized).
import Swiflow

struct DemoPerson: Identifiable {
    let id: Int
    let name: String
    let age: Int
    let role: String
}

let samplePeople: [DemoPerson] = [
    DemoPerson(id: 1,  name: "Ada Lovelace",      age: 36, role: "Engineer"),
    DemoPerson(id: 2,  name: "Grace Hopper",       age: 85, role: "Admiral"),
    DemoPerson(id: 3,  name: "Alan Turing",        age: 41, role: "Researcher"),
    DemoPerson(id: 4,  name: "Margaret Hamilton",  age: 87, role: "Engineer"),
    DemoPerson(id: 5,  name: "Linus Torvalds",     age: 55, role: "Maintainer"),
    DemoPerson(id: 6,  name: "Vint Cerf",          age: 81, role: "Architect"),
    DemoPerson(id: 7,  name: "Tim Berners-Lee",    age: 70, role: "Inventor"),
    DemoPerson(id: 8,  name: "Guido van Rossum",   age: 69, role: "Designer"),
    DemoPerson(id: 9,  name: "Brendan Eich",       age: 63, role: "Engineer"),
    DemoPerson(id: 10, name: "Barbara Liskov",     age: 83, role: "Researcher"),
    DemoPerson(id: 11, name: "Katherine Johnson",  age: 101, role: "Mathematician"),
    DemoPerson(id: 12, name: "Dennis Ritchie",     age: 70, role: "Inventor"),
    DemoPerson(id: 13, name: "Ken Thompson",       age: 82, role: "Inventor"),
    DemoPerson(id: 14, name: "Bjarne Stroustrup",  age: 74, role: "Designer"),
]

let bigPeople: [DemoPerson] = (0..<2000).map { i in
    DemoPerson(id: 1000 + i, name: "Person \(i)", age: 18 + (i % 70),
               role: ["Engineer", "Researcher", "Inventor", "Designer"][i % 4])
}
