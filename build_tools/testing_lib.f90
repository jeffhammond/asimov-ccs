!>  Testing library
module testing_lib
#include "ccs_macros.inc"

  use MPI

  use kinds
  use types
  use parallel
  use parallel_types
  use parallel_types_mpi
  use utils, only : str

  implicit none

  public :: assert_eq, assert_neq, assert_lt, assert_gt, assert_bool

  interface assert_eq
    procedure assert_eq_integer_rank0
    procedure assert_eq_integer_rank1
    procedure assert_eq_real_rank0
    procedure assert_eq_real_rank1
    procedure assert_eq_string
  end interface

  interface assert_lt
    procedure assert_lt_integer
    procedure assert_lt_real
  end interface

  interface assert_gt
    procedure assert_gt_integer
    procedure assert_gt_real
  end interface

  interface assert_bool
    procedure assert_bool_rank0
    procedure assert_bool_rank1
  end interface

  interface assert_neq
    procedure assert_neq_integer
    procedure assert_neq_real
    procedure assert_neq_string
  end interface
  
  interface a_eq
    procedure a_eq_integer
    procedure a_eq_real
  end interface

  interface print_failed
    procedure print_failed_integer
    procedure print_failed_real
    procedure print_failed_bool
  end interface

  
  class(parallel_environment), allocatable, target :: par_env
  integer(ccs_err) :: ierr
  integer :: real_type
  character(1024) :: message

  real(ccs_real), parameter :: eps = epsilon(0.0_ccs_real)

contains

  !>  Test initialisation
  !
  !> @description Performs initialisation for the test (setting up parallel environment, etc.)
  subroutine init()

    integer, allocatable :: seed(:)
    integer :: n

    if (kind(0.0_ccs_real) == kind(0.0d0)) then
      real_type = MPI_DOUBLE
    else
      real_type = MPI_FLOAT
    end if

    call initialise_parallel_environment(par_env)

    ! XXX: This would be a good candidate for a testing library
    call random_seed(size=n)
    allocate(seed(n))
    call random_seed(get=seed)
    if (par_env%proc_id == par_env%root) then
      print *, "Using seed: ", seed
      print *, "----------------------------------"
    end if
    deallocate(seed)

    select type(par_env)
    type is(parallel_environment_mpi)
      call MPI_Barrier(par_env%comm, ierr)
    class default
      print *, "ERROR: Unknown parallel environment!"
      stop 1
    end select
    
  end subroutine init

  !>  Test finalisation
  !
  !> @description Performs finalisation for the test (tearing down parallel environment, etc.)
  subroutine fin()

    call cleanup_parallel_environment(par_env)

  end subroutine fin

  !>  Helper function to get a random number in parallel
  !
  !> @description Generates a random number and broadcasts the value on the root of the parallel
  !! environment, ensuring a uniform value is used.
  !
  !> @note Does this belong in the parallel module?
  real(ccs_real) function parallel_random(par_env)

    class(parallel_environment), intent(in) :: par_env

    call random_number(parallel_random)

    select type(par_env)
    type is(parallel_environment_mpi)
      call MPI_Bcast(parallel_random, 1, real_type, par_env%root, par_env%comm, ierr)
    class default
      print *, "ERROR: Unknown parallel environment!"
      stop 1
    end select
    
  end function parallel_random

  !>  Test failure stop
  !
  !> @description Stop a test, provide an error message, do cleanup etc.
  subroutine stop_test(message)

    character(*), intent(in) :: message
    character(len=32) :: id_str

    write (id_str, "(I0)") par_env%proc_id
    print *, "("//trim(id_str)//") ", trim(message)

    ! other PEs might not have encountered a test failure
    ! fin()

    stop 1
  end subroutine stop_test
 


  subroutine return_or_stop(res, message, outval)

    logical, intent(in) :: res !< Evaluation result
    character(*), intent(in) :: message              !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    if (present(outval)) then
      outval = res
    else
      if (.not. res) then 
        call stop_test(message)
      end if
    end if

  end subroutine return_or_stop


!==========================Integers
  subroutine assert_eq_integer_rank0(received, expected, message, outval)

    integer(ccs_int), intent(in) :: received       !< Test value
    integer(ccs_int), intent(in) :: expected  !< Reference value
    character(*), intent(in) :: message              !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    call return_or_stop(a_eq(received, expected), &
                        message // " Expected: " // str(expected) // " Received: " // str(received), &
                        outval)

  end subroutine assert_eq_integer_rank0

  subroutine assert_eq_integer_rank1(received, expected, message, outval)

    integer(ccs_int), dimension(:), intent(in) :: received       !< Test value
    integer(ccs_int), dimension(:), intent(in) :: expected  !< reference value
    character(*), intent(in) :: message              !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 
    
    logical :: res

    res = all(a_eq(received, expected))
    call return_or_stop(res, message // print_failed(received, expected), outval)

  end subroutine assert_eq_integer_rank1
!==========================
 


!==========================Reals
  subroutine assert_eq_real_rank0(received, expected, message, outval)

    real(ccs_real), intent(in) :: received      !< Test value
    real(ccs_real), intent(in) :: expected !< reference value
    character(*), intent(in) :: message              !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 
    
    logical :: res

    res = a_eq(received, expected)
    call return_or_stop(res, message // " Expected: " // str(expected) // " Received: " // str(received), outval)

  end subroutine assert_eq_real_rank0

  subroutine assert_eq_real_rank1(received, expected, message, outval)

    real(ccs_real), dimension(:), intent(in) :: received      !< Test value
    real(ccs_real), dimension(:), intent(in) :: expected !< reference value
    character(*), intent(in) :: message              !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = all(a_eq(received, expected))
    call return_or_stop(res, message // print_failed(received, expected), outval)

  end subroutine assert_eq_real_rank1
!==========================
 


!==========================Strings
  subroutine assert_eq_string(received, expected, message, outval)

    character(*), intent(in) :: received      !< Test value
    character(*), intent(in) :: expected !< reference value
    character(*), intent(in) :: message         !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = received == expected
    call return_or_stop(res, message // " Expected: " // expected // " Received: " // received, outval)

  end subroutine assert_eq_string
!==========================
 



!==========================Printing funcs
  function print_failed_integer(received, expected) result(msg)
    integer(ccs_int), dimension(:), intent(in) :: expected 
    integer(ccs_int), dimension(:), intent(in) :: received
    character(len=:), allocatable :: msg

    integer :: i
    logical, dimension(:), allocatable :: mask
    allocate(mask(size(received)))
    mask = a_eq(received, expected)

    msg = new_line('a') // "Index Expected Received" // new_line('a')
    do i = 1, size(mask)
      if (.not. mask(i)) then
        msg = msg // str(i) // achar(9) // str(expected(i)) // achar(9) // str(received(i)) // new_line('a')
      end if
    end do
  end function print_failed_integer
  
  function print_failed_real(received, expected) result(msg)
    real(ccs_real), dimension(:), intent(in) :: expected 
    real(ccs_real), dimension(:), intent(in) :: received
    character(len=:), allocatable :: msg

    integer :: i
    logical, dimension(:), allocatable :: mask
    allocate(mask(size(received)))
    mask = a_eq(received, expected)

    msg = new_line('a') // "Index Expected Received" // new_line('a')
    do i = 1, size(mask)
      if (.not. mask(i)) then
        msg = msg // str(i) // achar(9) // str(expected(i)) // achar(9) // str(received(i)) // new_line('a')
      end if
    end do
  end function print_failed_real
  
  function print_failed_bool(received) result(msg)
    logical, dimension(:), intent(in) :: received
    character(len=:), allocatable :: msg

    integer :: i

    msg = new_line('a') // "Index Received" // new_line('a')
    do i = 1, size(received)
      if (.not. received(i)) then
        msg = msg // str(i) // achar(9) // "FALSE" // new_line('a')
      end if
    end do
  end function print_failed_bool
!==========================

  

!==========================Comparison operators
  elemental logical function a_eq_integer(a, b) result(comparison)
    integer(ccs_int), intent(in) :: a 
    integer(ccs_int), intent(in) :: b 

    comparison = a == b
  end function a_eq_integer
  
  elemental logical function a_eq_real(a, b) result(comparison)
    real(ccs_real), intent(in) :: a 
    real(ccs_real), intent(in) :: b 

    comparison = (abs(a - b) < epsilon(b) * abs(b))
  end function a_eq_real
!==========================



!==========================Others
  subroutine assert_lt_integer(received, upper_limit, message, outval)
    integer(ccs_int), intent(in) :: received    !< Test value
    integer(ccs_int), intent(in) :: upper_limit !< Reference value
    character(*), intent(in) :: message         !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = received < upper_limit
    call return_or_stop(res, message // "Upper limit allowed: " // str(upper_limit) // " Received: " // str(received), outval)
  end subroutine assert_lt_integer
  
  subroutine assert_lt_real(received, upper_limit, message, outval)
    real(ccs_real), intent(in) :: received    !< Test value
    real(ccs_real), intent(in) :: upper_limit !< Reference value
    character(*), intent(in) :: message          !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = received < upper_limit
    call return_or_stop(res, message // "Upper limit allowed: " // str(upper_limit) // " Received: " // str(received), outval)
  end subroutine assert_lt_real


  subroutine assert_gt_integer(received, lower_limit, message, outval)
    integer(ccs_int), intent(in) :: received    !< Test value
    integer(ccs_int), intent(in) :: lower_limit !< Reference value
    character(*), intent(in) :: message         !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = received > lower_limit
    call return_or_stop(res, message // "Lower limit allowed: " // str(lower_limit) // " Received: " // str(received), outval)
  end subroutine assert_gt_integer
  
  subroutine assert_gt_real(received, lower_limit, message, outval)
    real(ccs_real), intent(in) :: received    !< Test value
    real(ccs_real), intent(in) :: lower_limit !< Reference value
    character(*), intent(in) :: message          !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = received > lower_limit
    call return_or_stop(res, message // "Lower limit allowed: " // str(lower_limit) // " Received: " // str(received), outval)
  end subroutine assert_gt_real


  subroutine assert_bool_rank0(received, message, outval)
    logical, intent(in) :: received     !< Test value
    character(*), intent(in) :: message !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = received
    call return_or_stop(res, message // " Expected: TRUE Received: FALSE", outval)
  end subroutine assert_bool_rank0
  
  subroutine assert_bool_rank1(received, message, outval)
    logical, dimension(:), intent(in) :: received !< Test values
    character(*), intent(in) :: message           !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = all(received)
    call return_or_stop(res, message // print_failed(received), outval)
  end subroutine assert_bool_rank1


  subroutine assert_neq_integer(received, notexpected, message, outval)
    integer(ccs_int), intent(in) :: received    !< Test value
    integer(ccs_int), intent(in) :: notexpected !< Reference value
    character(*), intent(in) :: message         !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    logical :: res

    res = .not. a_eq(received, notexpected)
    call return_or_stop(res, message // " Not Expected: " // str(notexpected) // " Received: " // str(received), outval)
  end subroutine assert_neq_integer
  
  subroutine assert_neq_real(received, notexpected, message, outval)
    real(ccs_real), intent(in) :: received    !< Test value
    real(ccs_real), intent(in) :: notexpected !< Reference value
    character(*), intent(in) :: message          !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    call return_or_stop(.not. a_eq(received, notexpected), &
                        message // " Not Expected: " // str(notexpected) // " Received: " // str(received), &
                        outval)
  end subroutine assert_neq_real
  
  subroutine assert_neq_string(received, notexpected, message, outval)
    character(*), intent(in) :: received    !< Test value
    character(*), intent(in) :: notexpected !< Reference value
    character(*), intent(in) :: message     !< Error message 
    logical, optional, intent(out) :: outval  !< Output value to replace stopping the test 

    call return_or_stop(.not. received == notexpected, &
                        message // " Not Expected: " // notexpected // " Received: " // received, &
                        outval)
  end subroutine assert_neq_string
!==========================


end module testing_lib
