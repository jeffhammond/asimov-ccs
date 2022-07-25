!>  Program file for scalar advection case
!
!

program bc_test
#include "ccs_macros.inc"

  !! ASiMoV-CCS uses
  use testing_lib
  use kinds, only : ccs_real, ccs_int
  use types, only : field, central_field
  use utils, only : debug_print, exit_print, str
  use boundary_conditions, only : read_bc_config, allocate_bc_arrays
  use read_config, only: get_bc_variables, get_n_boundaries
  use bc_constants

  implicit none

  class(field), allocatable :: u, v, w, p
  type(central_field), dimension(:), allocatable :: phi
  integer(ccs_int) :: i
  integer(ccs_int) :: n_boundaries
  character(len=*), parameter :: config_file = "test_read_bc_config.in"
  character(len=6), dimension(:), allocatable :: variable_names
  character(len=6) :: variable_name
  integer(ccs_int), dimension(:), allocatable :: bc_names, bc_ids, bc_types
  real(ccs_real), dimension(:), allocatable :: bc_values

  call init()

  ! Init velocities and scalar
  allocate(central_field :: u)
  allocate(central_field :: v)
  allocate(central_field :: w)
  allocate(central_field :: p)

  ! Read bc configuration
  ! First get the number of boundaries and variables
  call get_n_boundaries(config_file, n_boundaries)
  call get_bc_variables(config_file, variable_names)
  allocate(phi(size(variable_names) - 4))
  
  ! Check that the number of boundaries and the variables are read in correctly 
  call assert_equal(n_boundaries, 4, "n_boundaries doesn't match expected value")
  call assert_equal(variable_names(1), "u", "variable name doesn't match expected value")
  call assert_equal(variable_names(2), "v", "variable name doesn't match expected value")
  call assert_equal(variable_names(3), "w", "variable name doesn't match expected value")
  call assert_equal(variable_names(4), "p", "variable name doesn't match expected value")
  do i = 5, size(variable_names)
    write(variable_name, "(A, I0)") "phi_", i-4
    call assert_equal(variable_names(i), variable_name, "variable name doesn't match expected value")
  end do

  ! Allocate arrays for the BCs on a per-variable basis
  call allocate_bc_arrays(n_boundaries, u%bcs)
  call allocate_bc_arrays(n_boundaries, v%bcs)
  call allocate_bc_arrays(n_boundaries, w%bcs)
  call allocate_bc_arrays(n_boundaries, p%bcs)
  do i = 1, size(variable_names) - 4
    call allocate_bc_arrays(n_boundaries, phi(i)%bcs)
  end do

  ! Finally read in the BCs
  call read_bc_config(config_file, "u", u)
  call read_bc_config(config_file, "v", v)
  call read_bc_config(config_file, "w", w)
  call read_bc_config(config_file, "p", p)
  do i = 1, size(variable_names) - 4
    write(variable_name, "(A, I0)") "phi_", i
    call read_bc_config(config_file, trim(variable_name), phi(i))
  end do

  ! Check that they're read in correctly
  allocate(bc_names(n_boundaries))
  allocate(bc_ids(n_boundaries))
  allocate(bc_types(n_boundaries))
  allocate(bc_values(n_boundaries))
  bc_names = (/ bc_region_left, bc_region_right, bc_region_top, bc_region_bottom /)
  bc_ids = (/ 92749, 0, 17648, 1 /)
  bc_types = bc_type_dirichlet
  bc_values = 1
  call check_bcs(u%bcs, bc_names, bc_ids, bc_types, bc_values)
  call dprint("finished checking u")
  bc_types = bc_type_neumann
  bc_values = 0
  call check_bcs(v%bcs, bc_names, bc_ids, bc_types, bc_values)
  call dprint("finished checking v")
  bc_types = bc_type_extrapolate
  call check_bcs(p%bcs, bc_names, bc_ids, bc_types)
  call dprint("finished checking p")

  call fin()

  contains

  subroutine check_bcs(bcs, names, ids, types, values)
    type(bc_config), intent(in) :: bcs
    integer(ccs_int), dimension(:), intent(in) :: names
    integer(ccs_int), dimension(:), intent(in) :: ids
    integer(ccs_int), dimension(:), intent(in) :: types
    real(ccs_real), dimension(:), intent(in), optional :: values

    do i = 1, size(bcs%names)
      call assert_equal(bcs%names(i), names(i), "bc name does not match")
      call assert_equal(bcs%ids(i), ids(i), "bc id does not match")
      call assert_equal(bcs%bc_types(i), types(i), "bc type does not match")
      if (present(values)) then
        call assert_equal(bcs%values(i), values(i), "bc value does not match")
      end if 
    end do
  end subroutine check_bcs
end program bc_test
