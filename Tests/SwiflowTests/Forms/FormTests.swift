import Testing
@testable import Swiflow

@Suite("Forms")
struct FormTests {

    @Suite("Validator")
    struct ValidatorTests {

        @Test(".required rejects empty string")
        func requiredRejectsEmpty() {
            #expect(Validator.required().validate("") == "Required")
        }

        @Test(".required accepts non-empty string")
        func requiredAcceptsNonEmpty() {
            #expect(Validator.required().validate("a") == nil)
        }

        @Test(".minLength rejects short string")
        func minLengthRejectsShort() {
            #expect(Validator.minLength(3).validate("ab") == "Must be at least 3 characters")
        }

        @Test(".minLength accepts string at or above threshold")
        func minLengthAcceptsAtThreshold() {
            #expect(Validator.minLength(3).validate("abc") == nil)
            #expect(Validator.minLength(3).validate("abcd") == nil)
        }

        @Test(".maxLength rejects long string")
        func maxLengthRejectsLong() {
            #expect(Validator.maxLength(3).validate("abcd") == "Must be at most 3 characters")
        }

        @Test(".maxLength accepts string at or below limit")
        func maxLengthAcceptsAtLimit() {
            #expect(Validator.maxLength(3).validate("abc") == nil)
            #expect(Validator.maxLength(3).validate("ab") == nil)
        }

        @Test(".email accepts valid address")
        func emailAcceptsValid() {
            #expect(Validator<String>.email.validate("a@b.com") == nil)
        }

        @Test(".email rejects invalid addresses")
        func emailRejectsInvalid() {
            #expect(Validator<String>.email.validate("notanemail") != nil)
            #expect(Validator<String>.email.validate("@b.com") != nil)
        }

        @Test(".regex accepts matching string")
        func regexAccepts() {
            let v = Validator<String>.regex(/^\d+$/, message: "Digits only")
            #expect(v.validate("123") == nil)
        }

        @Test(".regex rejects non-matching string")
        func regexRejects() {
            let v = Validator<String>.regex(/^\d+$/, message: "Digits only")
            #expect(v.validate("abc") == "Digits only")
        }

        @Test(".custom rejects when check returns false")
        func customRejects() {
            let v = Validator<String>.custom("Must have a number") { $0.contains { $0.isNumber } }
            #expect(v.validate("hello") == "Must have a number")
        }

        @Test(".custom accepts when check returns true")
        func customAccepts() {
            let v = Validator<String>.custom("Must have a number") { $0.contains { $0.isNumber } }
            #expect(v.validate("hello1") == nil)
        }

        @Test("required before minLength: empty field shows Required not minLength message")
        func validatorOrdering() {
            let v1 = Validator<String>.required()
            let v2 = Validator<String>.minLength(3)
            let validators = [v1, v2]
            let result = validators.lazy.compactMap { $0.validate("") }.first
            #expect(result == "Required")
        }
    }
}
