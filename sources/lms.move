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

  //   errors
  const EInsufficientBalance: u64 = 1;
  const ENotInstitute: u64 = 2;
  const ENotInstituteStudent: u64 = 5;
  const EInsufficientCapacity: u64 = 6;
  const EGrantNotApproved: u64 = 7;
  const ENotOwner: u64 = 8;

  //   structs
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
    course: String,
    date: String,
    time: u64,
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

  //   functions
  // create new institute
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

  // create new student
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

  //  add course
  public entry fun add_course(
    cap: &InstituteCap,
    self: &mut Institute,
    title: String,
    instructor: String,
    capacity: u64
  ) {
    assert!(cap.to == object::id(self), ENotOwner);
    let course = Course {
      title,
      instructor,
      capacity,
      enrolledStudents: vector::empty<address>(),
    };
    table::add(&mut self.courses, title, course);
  }

  //add enrollment
  public entry fun add_enrollment(
    institute: &mut Institute,
    student: &mut Student,
    course: String,
    date: String,
    clock: &Clock,
    ctx: &mut TxContext
  ){
    assert!(student.student == object::uid_to_address(&student.id), ENotInstituteStudent);
    let enrollment_id = object::new(ctx);
    let enrollment = Enrollment {
      id: enrollment_id,
      student: student.student,
      studentName: student.name,
      course: course,
      date,
      time: clock::timestamp_ms(clock),
    };
    let course_ = table::borrow_mut(&mut institute.courses, course);
    // deduct fees from student balance
    assert!(balance::value(&student.balance) >= institute.fees, EInsufficientBalance);
    assert!(vector::length(&course_.enrolledStudents) < course_.capacity, EInsufficientCapacity);

    let fees = balance::split(&mut student.balance, institute.fees);
    balance::join(&mut institute.balance, fees);

    // enroll student in course
    vector::push_back(&mut course_.enrolledStudents, student.student);

    table::add<ID, Enrollment>(&mut institute.enrollments, object::uid_to_inner(&enrollment.id), enrollment);
  }

  // fund student account
  public entry fun deposit_student_account(
    student: &mut Student,
    amount: Coin<SUI>,
  ) {
    coin::put(&mut student.balance, amount);
  }

  // check student balance
  public fun student_check_balance(
    student: &Student,
  ) : u64  {
    balance::value(&student.balance)
  }

  // institute check balance
  public fun institute_check_balance(
    self: &Institute,
  ) : u64 {
    balance::value(&self.balance)

  }
  // withdraw institute balance
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
// create new grant request
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

// approve grant request
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
    // update course information
    public fun update_course(
        course: &mut Course,
        title: String,
        instructor: String,
        capacity: u64
    ) {
        course.title = title;
        course.instructor = instructor;
        course.capacity = capacity;
    }
    // update student information
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
}
