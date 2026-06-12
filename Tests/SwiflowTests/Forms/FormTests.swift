import Testing
@testable import Swiflow

@Suite("Forms")
struct FormTests {

    @Suite("Validator")
    struct ValidatorTests {

        @Test(".required rejects only the empty string", arguments: [
            ("", "Required"),
            ("a", nil),
        ] as [(String, String?)])
        func required(input: String, expected: String?) {
            #expect(Validator.required().validate(input) == expected)
        }

        @Test(".minLength rejects below threshold, accepts at or above", arguments: [
            ("ab", "Must be at least 3 characters"),
            ("abc", nil),
            ("abcd", nil),
        ] as [(String, String?)])
        func minLength(input: String, expected: String?) {
            #expect(Validator.minLength(3).validate(input) == expected)
        }

        @Test(".maxLength rejects above limit, accepts at or below", arguments: [
            ("abcd", "Must be at most 3 characters"),
            ("abc", nil),
            ("ab", nil),
        ] as [(String, String?)])
        func maxLength(input: String, expected: String?) {
            #expect(Validator.maxLength(3).validate(input) == expected)
        }

        @Test(".email accepts valid addresses and rejects malformed ones", arguments: [
            ("a@b.com", true),
            ("notanemail", false),
            ("@b.com", false),
        ])
        func email(input: String, isValid: Bool) {
            #expect((Validator<String>.email.validate(input) == nil) == isValid)
        }

        @Test(".regex validates against the pattern", arguments: [
            ("123", nil),
            ("abc", "Digits only"),
        ] as [(String, String?)])
        func regex(input: String, expected: String?) {
            let v = Validator<String>.regex(/^\d+$/, message: "Digits only")
            #expect(v.validate(input) == expected)
        }

        @Test(".custom returns the message exactly when the check fails", arguments: [
            ("hello", "Must have a number"),
            ("hello1", nil),
        ] as [(String, String?)])
        func custom(input: String, expected: String?) {
            let v = Validator<String>.custom("Must have a number") { $0.contains { $0.isNumber } }
            #expect(v.validate(input) == expected)
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

    @Suite("Field")
    struct FieldTests {

        private func makeField(
            key: String = "pw",
            value: String = "",
            touched: Bool = false,
            validators: Validator<String>...
        ) -> (field: Field<String>, getValue: () -> String, getCtrl: () -> FormController) {
            var v = value
            var ctrl = FormController()
            if touched { ctrl.touched.insert(key) }
            let binding = Binding<String>(get: { v }, set: { v = $0 })
            let ctrlBinding = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
            let field = Field(key, binding, ctrlBinding, Array(validators))
            return (field, { v }, { ctrl })
        }

        @Test("error is nil when untouched even if invalid")
        func errorNilWhenUntouched() {
            let (field, _, _) = makeField(value: "", validators: .required())
            #expect(field.error == nil)
            #expect(field.isValid == false)
        }

        @Test("error is non-nil when touched and invalid")
        func errorNonNilWhenTouchedAndInvalid() {
            let (field, _, _) = makeField(value: "", touched: true, validators: .required())
            #expect(field.error == "Required")
        }

        @Test("error is nil when touched and valid")
        func errorNilWhenTouchedAndValid() {
            let (field, _, _) = makeField(value: "hello", touched: true, validators: .required())
            #expect(field.error == nil)
        }

        @Test("isValid is false regardless of touched when invalid")
        func isValidFalseWhenInvalid() {
            let (field, _, _) = makeField(value: "", validators: .required())
            #expect(field.isValid == false)
        }

        @Test("markTouched inserts key into ctrl.touched")
        func markTouchedInsertsKey() {
            let (field, _, getCtrl) = makeField(key: "pw", value: "x", validators: .required())
            field.markTouched()
            #expect(getCtrl().touched.contains("pw"))
        }

        @Test("isDirty is false when value matches initial")
        func isDirtyFalseOnInit() {
            let (field, _, _) = makeField(value: "hello", validators: .required())
            #expect(field.isDirty == false)
        }

        @Test("isDirty is true after mutation")
        func isDirtyTrueAfterMutation() {
            var v = "hello"
            var ctrl = FormController()
            let binding = Binding<String>(get: { v }, set: { v = $0 })
            let ctrlBinding = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
            let field = Field("pw", binding, ctrlBinding, [])
            binding.set("world")
            #expect(field.isDirty == true)
        }
    }

    @Suite("Form")
    struct FormSuite {

        private func makeForm() -> (
            form: Form,
            pwBinding: Binding<String>,
            emBinding: Binding<String>,
            getCtrl: () -> FormController
        ) {
            var pw = ""
            var em = ""
            var ctrl = FormController()
            let pwBinding = Binding<String>(get: { pw }, set: { pw = $0 })
            let emBinding = Binding<String>(get: { em }, set: { em = $0 })
            let ctrlBinding = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
            let pwField = Field("pw", pwBinding, ctrlBinding, [.required(), .minLength(3)])
            let emField = Field("em", emBinding, ctrlBinding, [.required(), .email])
            let form = Form(ctrlBinding) { pwField; emField }
            return (form, pwBinding, emBinding, { ctrl })
        }

        @Test("isValid is false when any field is invalid")
        func isValidFalseWhenInvalid() {
            let (form, _, _, _) = makeForm()
            #expect(form.isValid == false)
        }

        @Test("isValid is true when all fields are valid")
        func isValidTrueWhenAllValid() {
            let (form, pwBinding, emBinding, _) = makeForm()
            pwBinding.set("hello")
            emBinding.set("a@b.com")
            #expect(form.isValid == true)
        }

        @Test("isDirty is false before any mutation")
        func isDirtyFalseBeforeMutation() {
            let (form, _, _, _) = makeForm()
            #expect(form.isDirty == false)
        }

        @Test("isDirty is true after one field changes")
        func isDirtyTrueAfterMutation() {
            let (form, pwBinding, _, _) = makeForm()
            pwBinding.set("hello")
            #expect(form.isDirty == true)
        }

        @Test("touchAll marks all fields as touched")
        func touchAllMarksAllTouched() {
            let (form, _, _, getCtrl) = makeForm()
            form.touchAll()
            #expect(getCtrl().touched.contains("pw"))
            #expect(getCtrl().touched.contains("em"))
        }

        @Test("reset restores all values to initial and clears touched")
        func resetRestoresAndClearsTouched() {
            let (form, pwBinding, emBinding, getCtrl) = makeForm()
            pwBinding.set("hello")
            emBinding.set("a@b.com")
            form.touchAll()
            form.reset()
            #expect(pwBinding.get() == "")
            #expect(emBinding.get() == "")
            #expect(getCtrl().touched.isEmpty)
        }

        @Test("isDirty is false after reset")
        func isDirtyFalseAfterReset() {
            let (form, pwBinding, _, _) = makeForm()
            pwBinding.set("hello")
            form.reset()
            #expect(form.isDirty == false)
        }
    }
}
