module lms::lms {
    use std::vector;
    use sui::transfer;
    use sui::sui::SUI;
    use std::string::String;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::mutex::{Self, Mutex};

    // Errors
    const EInsufficientBalance: u64 = 1;
    const ENotInstitute: u64 = 2;
    const ENotStudent: u64 = 4;
    const ENotInstituteStudent: u64 = 5;
    const EInsufficientCapacity: u64 = 6;
    const EGrantNotApproved: u64 = 7;
    const EUnauthorized: u64 = 8;
    const EStudentNotFound: u64 = 9;

    // Structs
    struct Institute has key, store {
        id: UID,
        name: String,
        email: String,
        phone: String,
        fees: u64,
        balance: Balance<SUI>,
        courses: Table<ID, Course>,
        enrollments: Table<ID, Enrollment>,
        requests: Table<ID, EnrollmentRequest>,
        grants: Table<ID, GrantRequest>,
        institute: address,
        roles: Table<address, Role>,
    }

    struct Course has key, store {
        id: UID,
        title: String,
        instructor: String,
        capacity: u64,
        enrolledStudents: vector<address>,
    }

    struct Student has key, store {
        id: UID,
        name: String,
        email: String,
        homeAddress: String,
        balance: Balance<SUI>,
        student: address,
    }

    struct Enrollment has key, store {
        id: UID,
        student: address,
        studentName: String,
        courseId: ID,
        date: String,
        time: u64,
    }

    struct EnrollmentRequest has key, store {
        id: UID,
        student: address,
        homeAddress: String,
        created_at: u64,
    }

    struct GrantRequest has key, store {
        id: UID,
        student: address,
        amount_requested: u64,
        reason: String,
        approved: bool,
    }

    struct GrantApproval has key, store {
        id: UID,
        grant_request_id: ID,
        approved_by: address,
        amount_approved: u64,
        reason: String,
    }

    struct Role has key, store {
        id: UID,
        name: String,
        addresses: vector<address>,
    }

    // Functions
    // Create new institute
    public entry fun create_institute(
        name: String,
        email: String,
        phone: String,
        fees: u64,
        ctx: &mut TxContext
    ) {
        let institute_id = object::new(ctx);
        let institute = Institute {
            id: institute_id,
            name,
            email,
            phone,
            fees,
            balance: balance::zero<SUI>(),
            courses: table::new<ID, Course>(ctx),
            enrollments: table::new<ID, Enrollment>(ctx),
            requests: table::new<ID, EnrollmentRequest>(ctx),
            grants: table::new<ID, GrantRequest>(ctx),
            institute: tx_context::sender(ctx),
            roles: table::new<ID, Role>(ctx),
        };
        transfer::share_object(institute);
    }

    // Create new student
    public entry fun create_student(
        name: String,
        email: String,
        homeAddress: String,
        ctx: &mut TxContext
    ) {
        let student_id = object::new(ctx);
        let student = Student {
            id: student_id,
            name,
            email,
            homeAddress,
            balance: balance::zero<SUI>(),
            student: tx_context::sender(ctx),
        };
        transfer::share_object(student);
    }

    // Add course
    public entry fun add_course(
        title: String,
        instructor: String,
        capacity: u64,
        institute: &mut Institute,
        ctx: &mut TxContext
    ) {
        let course_id = object::new(ctx);
        let course = Course {
            id: course_id,
            title,
            instructor,
            capacity,
            enrolledStudents: vector::empty<address>(),
        };
        table::add(&mut institute.courses, object::uid_to_inner(&course.id), course);
        emit_event("Course Added".to_string(), title, ctx);
    }

    // New enrollment request
    public entry fun new_enrollment_request(
        student_id: ID,
        institute: &mut Institute,
        ctx: &mut TxContext
    ) {
        let student = table::borrow(&institute.enrollments, student_id);
        assert!(!option::is_none(&student), EStudentNotFound);

        let student_ref = option::extract(student);
        let request_id = object::new(ctx);
        let request = EnrollmentRequest {
            id: request_id,
            student: student_ref.student,
            homeAddress: student_ref.homeAddress,
            created_at: clock::timestamp_ms(ctx),
        };
        table::add(&mut institute.requests, object::uid_to_inner(&request.id), request);
        emit_event("Enrollment Request Created".to_string(), student_ref.name, ctx);
    }

    // Add enrollment
    public entry fun add_enrollment(
        institute: &mut Institute,
        student_id: ID,
        course_id: ID,
        date: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.institute, ENotInstitute);

        let student = table::borrow(&institute.enrollments, student_id);
        assert!(!option::is_none(&student), EStudentNotFound);
        let student_ref = option::extract(student);

        let course = table::borrow(&institute.courses, course_id);
        assert!(!option::is_none(&course), EStudentNotFound);
        let course_ref = option::extract(course);

        assert!(balance::value(&student_ref.balance) >= institute.fees, EInsufficientBalance);
        assert!(vector::length(&course_ref.enrolledStudents) < course_ref.capacity, EInsufficientCapacity);

        let enrollment_id = object::new(ctx);
        let enrollment = Enrollment {
            id: enrollment_id,
            student: student_ref.student,
            studentName: student_ref.name,
            courseId: course_id,
            date,
            time: clock::timestamp_ms(clock),
        };

        let fees = coin::take(&mut student_ref.balance, institute.fees, ctx);
        transfer::public_transfer(fees, institute.institute);

        vector::push_back(&mut course_ref.enrolledStudents, student_ref.student);
        table::add(&mut institute.enrollments, object::uid_to_inner(&enrollment.id), enrollment);
        emit_event("Student Enrolled".to_string(), student_ref.name, ctx);
    }

    // Fund student account
    public entry fun fund_student_account(
        student_id: ID,
        amount: Coin<SUI>,
        institute: &mut Institute,
        ctx: &mut TxContext
    ) {
        let student = table::borrow_mut(&mut institute.enrollments, student_id);
        assert!(!option::is_none(&student), EStudentNotFound);
        let student_ref = option::extract_mut(student);

        assert!(tx_context::sender(ctx) == student_ref.student, ENotStudent);

        let coin_amount = coin::into_balance(amount);
        balance::join(&mut student_ref.balance, coin_amount);
        emit_event("Student Account Funded".to_string(), student_ref.name, ctx);
    }

    // Check student balance
    public fun student_check_balance(
        student_id: ID,
        institute: &Institute,
        ctx: &mut TxContext
    ): &Balance<SUI> {
        let student = table::borrow(&institute.enrollments, student_id);
        assert!(!option::is_none(&student), EStudentNotFound);
        let student_ref = option::extract(student);

        assert!(tx_context::sender(ctx) == student_ref.student, ENotStudent);
        &student_ref.balance
    }

    // Institute check balance
    public fun institute_check_balance(
        institute: &Institute,
        ctx: &mut TxContext
    ): &Balance<SUI> {
        assert!(tx_context::sender(ctx) == institute.institute, ENotInstitute);
        &institute.balance
    }

    // Withdraw institute balance
    public entry fun withdraw_institute_balance(
        institute: &mut Institute,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.institute, ENotInstitute);
        assert!(balance::value(&institute.balance) >= amount, EInsufficientBalance);
        let payment = coin::take(&mut institute.balance, amount, ctx);
        transfer::public_transfer(payment, institute.institute);
        emit_event("Institute Balance Withdrawn".to_string(), amount.to_string(), ctx);
    }

    // Create new grant request
    public entry fun create_grant_request(
        student_id: ID,
        amount_requested: u64,
        reason: String,
        institute: &mut Institute,
        ctx: &mut TxContext
    ) {
        let student = table::borrow(&institute.enrollments, student_id);
        assert!(!option::is_none(&student), EStudentNotFound);
        let student_ref = option::extract(student);

        let grant_request_id = object::new(ctx);
        let grant_request = GrantRequest {
            id: grant_request_id,
            student: student_ref.student,
            amount_requested,
            reason,
            approved: false,
        };
        table::add(&mut institute.grants, object::uid_to_inner(&grant_request.id), grant_request);
        emit_event("Grant Request Created".to_string(), student_ref.name, ctx);
    }

    // Approve grant request with role-based authorization
    public entry fun approve_grant_request(
        grant_request_id: ID,
        amount_approved: u64,
        reason: String,
        institute: &mut Institute,
        ctx: &mut TxContext
    ) {
        let grant_request = table::borrow_mut(&mut institute.grants, grant_request_id);
        assert!(!option::is_none(&grant_request), EGrantNotApproved);
        let grant_request_ref = option::extract_mut(grant_request);

        let sender = tx_context::sender(ctx);
        assert!(has_role(institute, sender, "admin") || has_role(institute, sender, "financial_advisor"), EUnauthorized);

        assert!(!grant_request_ref.approved, EGrantNotApproved);
        grant_request_ref.approved = true;

        let grant_approval_id = object::new(ctx);
        let grant_approval = GrantApproval {
            id: grant_approval_id,
            grant_request_id,
            approved_by: sender,
            amount_approved,
            reason,
        };
        transfer::share_object(grant_approval);
        emit_event("Grant Approved".to_string(), grant_request_ref.student, ctx);
    }

    // Add role to institute
    public entry fun add_role(
        institute: &mut Institute,
        role_name: String,
        address: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.institute, ENotInstitute);

        let role_id = object::new(ctx);
        let mut role = match table::borrow(&institute.roles, role_id) {
            Some(role) => role,
            None => Role {
                id: role_id,
                name: role_name,
                addresses: vector::empty<address>(),
            },
        };

        vector::push_back(&mut role.addresses, address);
        table::add(&mut institute.roles, object::uid_to_inner(&role.id), role);
        emit_event("Role Added".to_string(), role_name, ctx);
    }

    // Check if an address has a specific role
    public fun has_role(
        institute: &Institute,
        address: address,
        role_name: String
    ): bool {
        let role_ids = table::keys(&institute.roles);
        for role_id in role_ids {
            let role = table::borrow(&institute.roles, role_id);
            if option::is_some(&role) {
                let role_ref = option::extract(role);
                if role_ref.name == role_name && vector::contains(&role_ref.addresses, &address) {
                    return true;
                }
            }
        }
        false
    }

    // Event logging
    public entry fun emit_event(
        event_type: String,
        description: String,
        ctx: &mut TxContext
    ) {
        tx_context::emit_event(ctx, (event_type, description));
    }

    // Update course information
    public entry fun update_course(
        course_id: ID,
        title: String,
        instructor: String,
        capacity: u64,
        institute: &mut Institute,
        ctx: &mut TxContext
    ) {
        let course = table::borrow_mut(&mut institute.courses, course_id);
        assert!(!option::is_none(&course), EStudentNotFound);
        let course_ref = option::extract_mut(course);

        course_ref.title = title;
        course_ref.instructor = instructor;
        course_ref.capacity = capacity;
        emit_event("Course Updated".to_string(), title, ctx);
    }

    // Update student information
    public entry fun update_student(
        student_id: ID,
        name: String,
        email: String,
        homeAddress: String,
        institute: &mut Institute,
        ctx: &mut TxContext
    ) {
        let student = table::borrow_mut(&mut institute.enrollments, student_id);
        assert!(!option::is_none(&student), EStudentNotFound);
        let student_ref = option::extract_mut(student);

        student_ref.name = name;
        student_ref.email = email;
        student_ref.homeAddress = homeAddress;
        emit_event("Student Updated".to_string(), name, ctx);
    }
}
