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

    // Errors
    const EInsufficientBalance: u64 = 1;
    const ENotInstitute: u64 = 2;
    const ENotStudent: u64 = 4;
    const ENotInstituteStudent: u64 = 5;
    const EInsufficientCapacity: u64 = 6;
    const EGrantNotApproved: u64 = 7;
    const EUnauthorizedAccess: u64 = 8;
    const EInvalidInput: u64 = 9;

    // Roles
    const ROLE_ADMIN: u8 = 0;
    const ROLE_INSTITUTE: u8 = 1;
    const ROLE_STUDENT: u8 = 2;
    const ROLE_INSTRUCTOR: u8 = 3;

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
        institute: address,
        admin: address,
    }

    struct Course has key, store {
        id: UID,
        title: String,
        instructor: address,
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

    // Helper Functions
    fun validate_non_negative(value: u64) {
        assert!(value >= 0, EInvalidInput);
    }

    fun validate_capacity(value: u64) {
        assert!(value > 0, EInvalidInput);
    }

    fun log_event(event: String) {
        // Placeholder for event logging logic
    }

    // Create new institute
    public entry fun create_institute(
        name: String,
        email: String,
        phone: String,
        fees: u64,
        admin: address,
        ctx: &mut TxContext
    ) {
        validate_non_negative(fees);
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
            institute: tx_context::sender(ctx),
            admin,
        };
        transfer::share_object(institute);
        log_event("Institute created".to_string());
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
        log_event("Student created".to_string());
    }

    // Add course
    public entry fun add_course(
        institute: &mut Institute,
        title: String,
        instructor: address,
        capacity: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.admin, EUnauthorizedAccess);
        validate_capacity(capacity);
        let course_id = object::new(ctx);
        let course = Course {
            id: course_id,
            title,
            instructor,
            capacity,
            enrolledStudents: vector::empty<address>(),
        };
        table::add<ID, Course>(&mut institute.courses, object::uid_to_inner(&course.id), course);
        log_event("Course added".to_string());
    }

    // New enrollment request
    public entry fun new_enrollment_request(
        student: &Student,
        institute: &mut Institute,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let request_id = object::new(ctx);
        let request = EnrollmentRequest {
            id: request_id,
            student: student.student,
            homeAddress: student.homeAddress,
            created_at: clock::timestamp_ms(clock),
        };
        table::add<ID, EnrollmentRequest>(&mut institute.requests, object::uid_to_inner(&request.id), request);
        log_event("Enrollment request created".to_string());
    }

    // Add enrollment
    public entry fun add_enrollment(
        institute: &mut Institute,
        student: &mut Student,
        course_id: &ID,
        date: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.institute, ENotInstitute);
        assert!(student.student == object::uid_to_address(&student.id), ENotInstituteStudent);

        let course = table::borrow_mut<ID, Course>(&mut institute.courses, *course_id);

        assert!(balance::value(&student.balance) >= institute.fees, EInsufficientBalance);
        assert!(vector::length(&course.enrolledStudents) < course.capacity, EInsufficientCapacity);

        let fees = coin::take(&mut student.balance, institute.fees, ctx);
        transfer::public_transfer(fees, institute.institute);

        vector::push_back(&mut course.enrolledStudents, student.student);

        let enrollment_id = object::new(ctx);
        let enrollment = Enrollment {
            id: enrollment_id,
            student: student.student,
            studentName: student.name,
            courseId: *course_id,
            date,
            time: clock::timestamp_ms(clock),
        };

        table::add<ID, Enrollment>(&mut institute.enrollments, object::uid_to_inner(&enrollment.id), enrollment);
        log_event("Enrollment added".to_string());
    }

    // Fund student account
    public entry fun fund_student_account(
        student: &mut Student,
        amount: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == student.student, ENotStudent);
        let coin_amount = coin::into_balance(amount);
        balance::join(&mut student.balance, coin_amount);
        log_event("Student account funded".to_string());
    }

    // Check student balance
    public fun student_check_balance(
        student: &Student,
        ctx: &mut TxContext
    ): &Balance<SUI> {
        assert!(tx_context::sender(ctx) == student.student, ENotStudent);
        &student.balance
    }

    // Check institute balance
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
        assert!(tx_context::sender(ctx) == institute.admin, EUnauthorizedAccess);
        assert!(balance::value(&institute.balance) >= amount, EInsufficientBalance);
        let payment = coin::take(&mut institute.balance, amount, ctx);
        transfer::public_transfer(payment, institute.institute);
        log_event("Institute balance withdrawn".to_string());
    }

    // Create new grant request
    public entry fun create_grant_request(
        student: &mut Student,
        amount_requested: u64,
        reason: String,
        ctx: &mut TxContext
    ) {
        validate_non_negative(amount_requested);
        let grant_request_id = object::new(ctx);
        let grant_request = GrantRequest {
            id: grant_request_id,
            student: student.student,
            amount_requested,
            reason,
            approved: false,
        };
        transfer::share_object(grant_request);
        log_event("Grant request created".to_string());
    }

        // Approve grant request
    public entry fun approve_grant_request(
        institute: &mut Institute,
        grant_request: &mut GrantRequest,
        amount_approved: u64,
        reason: String,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.admin, EUnauthorizedAccess);
        assert!(!grant_request.approved, EGrantNotApproved);
        assert!(balance::value(&institute.balance) >= amount_approved, EInsufficientBalance);
        validate_non_negative(amount_approved);

        // Update the grant request
        grant_request.approved = true;

        // Create a grant approval record
        let grant_approval_id = object::new(ctx);
        let grant_approval = GrantApproval {
            id: grant_approval_id,
            grant_request_id: object::uid_to_inner(&grant_request.id),
            approved_by: institute.admin,
            amount_approved,
            reason,
        };
        transfer::share_object(grant_approval);

        // Transfer funds to the student
        let approved_amount = coin::take(&mut institute.balance, amount_approved, ctx);
        let student_address = grant_request.student;
        transfer::public_transfer(approved_amount, student_address);

        log_event("Grant request approved and funded".to_string());
    }

    // Update course information
    public entry fun update_course(
        institute: &mut Institute,
        course_id: &ID,
        title: String,
        instructor: address,
        capacity: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.admin, EUnauthorizedAccess);
        validate_capacity(capacity);

        let course = table::borrow_mut<ID, Course>(&mut institute.courses, *course_id);
        course.title = title;
        course.instructor = instructor;
        course.capacity = capacity;

        log_event("Course information updated".to_string());
    }

    // Update student information
    public entry fun update_student(
        student: &mut Student,
        name: String,
        email: String,
        homeAddress: String,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == student.student, ENotStudent);

        student.name = name;
        student.email = email;
        student.homeAddress = homeAddress;

        log_event("Student information updated".to_string());
    }
    
    // Remove course
    public entry fun remove_course(
        institute: &mut Institute,
        course_id: &ID,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.admin, EUnauthorizedAccess);
        
        let course = table::remove<ID, Course>(&mut institute.courses, *course_id);
        transfer::burn(course);

        log_event("Course removed".to_string());
    }

    // Manage waitlists
    // This function can be expanded to include actual waitlist management
    public entry fun manage_waitlist(
        institute: &mut Institute,
        course_id: &ID,
        student: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == institute.admin, EUnauthorizedAccess);

        // Placeholder logic for waitlist management
        // Implement actual waitlist management here

        log_event("Waitlist managed".to_string());
    }
}
