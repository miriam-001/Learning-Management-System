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
    const ENotInstituteStudent: u64 = 5;
    const EInsufficientCapacity: u64 = 6;
    const EGrantNotApproved: u64 = 7;
    const ENotOwner: u64 = 8;

    // Structs
    struct Institute has key, store {
        id: UID,
        name: String,
        email: String,
        phone: String,
        fees: u64,
        balance: Balance<SUI>,
        courses: Table<String, Course>,
        enrollments: Table<ID, Enrollment>,
        institute: address,
    }

    struct InstituteCap has key {
        id: UID,
        to: ID
    }

    struct Course has store {
        title: String,
        description: String,
        instructor: String,
        capacity: u64,
        duration: u64,  // Duration in days
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
        course: String,
        date: String,
        time: u64,
        grade: Option<u8>,
        completed: bool,
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

    struct Certificate has key, store {
        id: UID,
        student: address,
        course: String,
        issue_date: String,
        grade: u8,
    }

    // Functions
    // Create a new institute
    public fun create_institute(
        name: String,
        email: String,
        phone: String,
        fees: u64,
        ctx: &mut TxContext
    ) : InstituteCap {
        let institute_id = object::new(ctx);
        let inner_ = object::uid_to_inner(&institute_id);
        let institute = Institute {
            id: institute_id,
            name,
            email,
            phone,
            fees,
            balance: balance::zero<SUI>(),
            courses: table::new<String, Course>(ctx),
            enrollments: table::new<ID, Enrollment>(ctx),
            institute: tx_context::sender(ctx),
        };

        let cap = InstituteCap {
            id: object::new(ctx),
            to: inner_
        };
        transfer::share_object(institute);
        cap
    }

    // Create a new student
    public fun create_student(
        name: String,
        email: String,
        homeAddress: String,
        ctx: &mut TxContext
    ) : Student {
        let student_id = object::new(ctx);
        Student {
            id: student_id,
            name,
            email,
            homeAddress,
            balance: balance::zero<SUI>(),
            student: tx_context::sender(ctx),
        }
    }

    // Add a course
    public entry fun add_course(
        cap: &InstituteCap,
        self: &mut Institute,
        title: String,
        description: String,
        instructor: String,
        capacity: u64,
        duration: u64
    ) {
        assert!(cap.to == object::id(self), ENotOwner);
        let course = Course {
            title,
            description,
            instructor,
            capacity,
            duration,
            enrolledStudents: vector::empty<address>(),
        };
        table::add(&mut self.courses, title, course);
    }

    // Add enrollment
    public entry fun add_enrollment(
        institute: &mut Institute,
        student: &mut Student,
        course: String,
        date: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(student.student == tx_context::sender(ctx), ENotInstituteStudent);
        let enrollment_id = object::new(ctx);
        let enrollment = Enrollment {
            id: enrollment_id,
            student: student.student,
            studentName: student.name,
            course: course,
            date,
            time: clock::timestamp_ms(clock),
            grade: none(),
            completed: false,
        };
        let course_ = table::borrow_mut(&mut institute.courses, course);
        // Deduct fees from student balance
        assert!(balance::value(&student.balance) >= institute.fees, EInsufficientBalance);
        assert!(vector::length(&course_.enrolledStudents) < course_.capacity, EInsufficientCapacity);

        let fees = balance::split(&mut student.balance, institute.fees);
        balance::join(&mut institute.balance, fees);

        // Enroll student in course
        vector::push_back(&mut course_.enrolledStudents, student.student);

        table::add<ID, Enrollment>(&mut institute.enrollments, object::uid_to_inner(&enrollment.id), enrollment);
    }

    // Fund student account
    public entry fun deposit_student_account(
        student: &mut Student,
        amount: Coin<SUI>,
    ) {
        coin::put(&mut student.balance, amount);
    }

    // Check student balance
    public fun student_check_balance(
        student: &Student,
    ) : u64  {
        balance::value(&student.balance)
    }

    // Institute check balance
    public fun institute_check_balance(
        self: &Institute,
    ) : u64 {
        balance::value(&self.balance)
    }

    // Withdraw institute balance
    public fun withdraw_institute_balance(
        cap: &InstituteCap,
        self: &mut Institute,
        amount: u64,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        assert!(cap.to == object::id(self), ENotOwner);
        let payment = coin::take(&mut self.balance, amount, ctx);
        payment
    }

    // Create new grant request
    public entry fun create_grant_request(
        student: &mut Student,
        amount_requested: u64,
        reason: String,
        ctx: &mut TxContext
    ) {
        let grant_request_id = object::new(ctx);
        let grant_request = GrantRequest {
            id: grant_request_id,
            student: student.student,
            amount_requested,
            reason,
            approved: false,
        };
        transfer::share_object(grant_request);
    }

    // Approve grant request
    public entry fun approve_grant_request(
        grant_request: &mut GrantRequest,
        approved_by: address,
        amount_approved: u64,
        reason: String,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == approved_by, ENotInstitute);
        assert!(!grant_request.approved, EGrantNotApproved);

        grant_request.approved = true;

        let grant_approval_id = object::new(ctx);
        let grant_approval = GrantApproval {
            id: grant_approval_id,
            grant_request_id: object::uid_to_inner(&grant_request.id),
            approved_by,
            amount_approved,
            reason,
        };
        transfer::share_object(grant_approval);
    }

    // Issue certificate upon course completion
    public entry fun issue_certificate(
        enrollment: &mut Enrollment,
        grade: u8,
        issue_date: String,
        ctx: &mut TxContext
    ) {
        assert!(enrollment.completed, EGrantNotApproved);  // Ensure course is completed before issuing certificate
        let certificate_id = object::new(ctx);
        let certificate = Certificate {
            id: certificate_id,
            student: enrollment.student,
            course: enrollment.course.clone(),
            issue_date,
            grade,
        };
        transfer::share_object(certificate);
    }

    // Update course information
    public fun update_course(
        course: &mut Course,
        title: String,
        description: String,
        instructor: String,
        capacity: u64,
        duration: u64
    ) {
        course.title = title;
        course.description = description;
        course.instructor = instructor;
        course.capacity = capacity;
        course.duration = duration;
    }

    // Update student information
    public entry fun update_student(
        student: &mut Student,
        name: String,
        email: String,
        homeAddress: String,
    ) {
        student.name = name;
        student.email = email;
        student.homeAddress = homeAddress;
    }

    // Generate report for student
    public fun generate_student_report(
        student: &Student,
    ) : String {
        String::from_utf8(vector::concat(vec![
            String::to_utf8(student.name.clone()),
            String::from_utf8(" - ".to_utf8()),
            String::to_utf8(student.email.clone()),
            String::from_utf8(" - ".to_utf8()),
            String::to_utf8(student.homeAddress.clone()),
        ]))
    }

    // Generate report for course
    public fun generate_course_report(
        course: &Course,
    ) : String {
        String::from_utf8(vector::concat(vec![
            String::to_utf8(course.title.clone()),
            String::from_utf8(" - ".to_utf8()),
            String::to_utf8(course.description.clone()),
            String::from_utf8(" - ".to_utf8()),
            String::to_utf8(course.instructor.clone()),
        ]))
    }

    // Generate financial report for institute
    public fun generate_financial_report(
        self: &Institute,
    ) : String {
        String::from_utf8(vector::concat(vec![
            String::to_utf8(self.name.clone()),
            String::from_utf8(" - Balance: ".to_utf8()),
            String::from_utf8(balance::value(&self.balance).to_string().to_utf8()),
        ]))
    }
}
