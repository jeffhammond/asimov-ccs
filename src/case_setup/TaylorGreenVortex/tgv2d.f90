!v Program file for 2D TaylorGreenVortex case
!
!  @build mpi+petsc

program tgv2d
#include "ccs_macros.inc"

  use petscvec
  use petscsys

  use case_config, only: num_steps, velocity_relax, pressure_relax, res_target
  use constants, only: cell, face, ccsconfig, ccs_string_len
  use kinds, only: ccs_real, ccs_int
  use types, only: field, upwind_field, central_field, face_field, ccs_mesh, &
                   vector_spec, ccs_vector
  use yaml, only: parse, error_length
  use parallel, only: initialise_parallel_environment, &
                      cleanup_parallel_environment, timer, &
                      read_command_line_arguments, sync
  use parallel_types, only: parallel_environment
  use mesh_utils, only: build_square_mesh
  use vec, only: create_vector, set_vector_location
  use petsctypes, only: vector_petsc
  use pv_coupling, only: solve_nonlinear
  use utils, only: set_size, initialise, update, exit_print
  use boundary_conditions, only: read_bc_config, allocate_bc_arrays
  use read_config, only: get_bc_variables, get_boundary_count

  implicit none

  class(parallel_environment), allocatable :: par_env
  character(len=:), allocatable :: case_name       ! Case name
  character(len=:), allocatable :: ccs_config_file ! Config file for CCS
  character(len=ccs_string_len), dimension(:), allocatable :: variable_names  ! variable names for BC reading

  type(ccs_mesh) :: mesh
  type(vector_spec) :: vec_properties

  class(field), allocatable :: u, v, w, p, p_prime, mf

  integer(ccs_int) :: n_boundaries
  integer(ccs_int) :: cps = 50 ! Default value for cells per side

  integer(ccs_int) :: it_start, it_end
  integer(ccs_int) :: irank ! MPI rank ID
  integer(ccs_int) :: isize ! Size of MPI world

  double precision :: start_time
  double precision :: end_time

  logical :: u_sol = .true.  ! Default equations to solve for LDC case
  logical :: v_sol = .true.
  logical :: w_sol = .false.
  logical :: p_sol = .true.

#ifndef EXCLUDE_MISSING_INTERFACE
  integer(ccs_int) :: ierr
  type(tPetscViewer) :: viewer
#endif

  ! Launch MPI
  call initialise_parallel_environment(par_env)

  irank = par_env%proc_id
  isize = par_env%num_procs

  call read_command_line_arguments(par_env, cps, case_name=case_name)

  if (irank == par_env%root) print *, "Starting ", case_name, " case!"
  ccs_config_file = case_name // ccsconfig

  call timer(start_time)

  ! Read case name from configuration file
  call read_configuration(ccs_config_file)

  if (irank == par_env%root) then
    call print_configuration()
  end if

  ! Set start and end iteration numbers (eventually will be read from input file)
  it_start = 1
  it_end = num_steps

  ! Create a square mesh
  if (irank == par_env%root) print *, "Building mesh"
  mesh = build_square_mesh(par_env, cps, 1.0_ccs_real)

  ! Initialise fields
  if (irank == par_env%root) print *, "Initialise fields"
  allocate (upwind_field :: u)
  allocate (upwind_field :: v)
  allocate (upwind_field :: w)
  allocate (central_field :: p)
  allocate (central_field :: p_prime)
  allocate (face_field :: mf)

  ! Read boundary conditions
  call get_boundary_count(ccs_config_file, n_boundaries)
  call get_bc_variables(ccs_config_file, variable_names)
  call allocate_bc_arrays(n_boundaries, u%bcs)
  call allocate_bc_arrays(n_boundaries, v%bcs)
  call allocate_bc_arrays(n_boundaries, w%bcs)
  call allocate_bc_arrays(n_boundaries, p%bcs)
  call allocate_bc_arrays(n_boundaries, p_prime%bcs)
  call read_bc_config(ccs_config_file, "u", u)
  call read_bc_config(ccs_config_file, "v", v)
  call read_bc_config(ccs_config_file, "w", w)
  call read_bc_config(ccs_config_file, "p", p)
  call read_bc_config(ccs_config_file, "p", p_prime)

  ! Create and initialise field vectors
  call initialise(vec_properties)

  call set_vector_location(cell, vec_properties)
  call set_size(par_env, mesh, vec_properties)
  call create_vector(vec_properties, u%values)
  call create_vector(vec_properties, v%values)
  call create_vector(vec_properties, w%values)
  call create_vector(vec_properties, p%values)
  call create_vector(vec_properties, p%x_gradients)
  call create_vector(vec_properties, p%y_gradients)
  call create_vector(vec_properties, p%z_gradients)
  call create_vector(vec_properties, p_prime%values)
  call create_vector(vec_properties, p_prime%x_gradients)
  call create_vector(vec_properties, p_prime%y_gradients)
  call create_vector(vec_properties, p_prime%z_gradients)
  call update(u%values)
  call update(v%values)
  call update(w%values)
  call update(p%values)
  call update(p%x_gradients)
  call update(p%y_gradients)
  call update(p%z_gradients)
  call update(p_prime%values)
  call update(p_prime%x_gradients)
  call update(p_prime%y_gradients)
  call update(p_prime%z_gradients)

  call set_vector_location(face, vec_properties)
  call set_size(par_env, mesh, vec_properties)
  call create_vector(vec_properties, mf%values)
  call update(mf%values)

  ! Initialise velocity field
  if (irank == par_env%root) print *, "Initialise velocity field"
  call initialise_velocity(mesh, u, v, w, mf)
  call update(u%values)
  call update(v%values)
  call update(w%values)
  call update(mf%values)

  ! Solve using SIMPLE algorithm
  if (irank == par_env%root) print *, "Start SIMPLE"
  call solve_nonlinear(par_env, mesh, it_start, it_end, res_target, &
                       u_sol, v_sol, w_sol, p_sol, u, v, w, p, p_prime, mf)

#ifndef EXCLUDE_MISSING_INTERFACE
  call PetscViewerBinaryOpen(PETSC_COMM_WORLD, "u", FILE_MODE_WRITE, viewer, ierr)

  associate (vec => u%values)
    select type (vec)
    type is (vector_petsc)
      call VecView(vec%v, viewer, ierr)
    end select
  end associate

  call PetscViewerBinaryOpen(PETSC_COMM_WORLD, "v", FILE_MODE_WRITE, viewer, ierr)

  associate (vec => v%values)
    select type (vec)
    type is (vector_petsc)
      call VecView(vec%v, viewer, ierr)
    end select
  end associate

  call PetscViewerBinaryOpen(PETSC_COMM_WORLD, "w", FILE_MODE_WRITE, viewer, ierr)

  associate (vec => w%values)
    select type (vec)
    type is (vector_petsc)
      call VecView(vec%v, viewer, ierr)
    end select
  end associate

  call PetscViewerBinaryOpen(PETSC_COMM_WORLD, "p", FILE_MODE_WRITE, viewer, ierr)

  associate (vec => p%values)
    select type (vec)
    type is (vector_petsc)
      call VecView(vec%v, viewer, ierr)
    end select
  end associate

  call PetscViewerDestroy(viewer, ierr)
#endif

  ! Clean-up
  deallocate (u)
  deallocate (v)
  deallocate (w)
  deallocate (p)
  deallocate (p_prime)

  call timer(end_time)

  if (irank == par_env%root) then
    print *, "Elapsed time: ", end_time - start_time
  end if

  ! Finalise MPI
  call cleanup_parallel_environment(par_env)

contains

  ! Read YAML configuration file
  subroutine read_configuration(config_filename)

    use read_config, only: get_reference_number, get_steps, &
                           get_convection_scheme, get_relaxation_factor, &
                           get_target_residual

    character(len=*), intent(in) :: config_filename

    class(*), pointer :: config_file_pointer  !< Pointer to CCS config file
    character(len=error_length) :: error

    config_file_pointer => parse(config_filename, error=error)
    if (error /= '') then
      call error_abort(trim(error))
    end if

    call get_steps(config_file_pointer, num_steps)
    if (num_steps == huge(0)) then
      call error_abort("No value assigned to num-steps.")
    end if

    call get_relaxation_factor(config_file_pointer, u_relax=velocity_relax, p_relax=pressure_relax)
    if (velocity_relax == huge(0.0) .and. pressure_relax == huge(0.0)) then
      call error_abort("No values assigned to velocity and pressure underrelaxation.")
    end if

    call get_target_residual(config_file_pointer, res_target)
    if (res_target == huge(0.0)) then
      call error_abort("No value assigned to target residual.")
    end if

  end subroutine

  ! Print test case configuration
  subroutine print_configuration()

    print *, "Solving ", case_name, " case"

    print *, "++++"
    print *, "SIMULATION LENGTH"
    print *, "Running for ", num_steps, "iterations"
    print *, "++++"
    print *, "MESH"
    print *, "Size is ", cps
    print *, "++++"
    print *, "RELAXATION FACTORS"
    write (*, '(1x,a,e10.3)') "velocity: ", velocity_relax
    write (*, '(1x,a,e10.3)') "pressure: ", pressure_relax

  end subroutine

  subroutine initialise_velocity(mesh, u, v, w, mf)

    use constants, only: insert_mode, ndim
    use types, only: vector_values, cell_locator, face_locator, neighbour_locator
    use meshing, only: set_cell_location, get_global_index, count_neighbours, set_neighbour_location, &
         get_local_index, set_face_location, get_local_index, get_face_normal, get_centre
    use fv, only: calc_cell_coords
    use utils, only: clear_entries, set_mode, set_row, set_entry, set_values
    use vec, only: get_vector_data, restore_vector_data, create_vector_values

    ! Arguments
    class(ccs_mesh), intent(in) :: mesh
    class(field), intent(inout) :: u, v, w, mf

    ! Local variables
    integer(ccs_int) :: row, col, n, count
    integer(ccs_int) :: index_p, global_index_p, index_f, index_nb
    real(ccs_real) :: u_val, v_val, w_val
    type(cell_locator) :: loc_p
    type(face_locator) :: loc_f
    type(neighbour_locator) :: loc_nb
    type(vector_values) :: u_vals, v_vals, w_vals
    real(ccs_real), dimension(:), pointer :: mf_data

    real(ccs_real), dimension(ndim) :: x_p, x_f
    real(ccs_real), dimension(ndim) :: face_normal

    integer(ccs_int) :: nnb
    integer(ccs_int) :: j
    
    ! Set alias
    associate (n_local => mesh%topo%local_num_cells)
      call create_vector_values(n_local, u_vals)
      call create_vector_values(n_local, v_vals)
      call create_vector_values(n_local, w_vals)
      call set_mode(insert_mode, u_vals)
      call set_mode(insert_mode, v_vals)
      call set_mode(insert_mode, w_vals)

      ! Set initial values for velocity fields
      do index_p = 1, n_local
        call set_cell_location(mesh, index_p, loc_p)
        call get_global_index(loc_p, global_index_p)

        call get_centre(loc_p, x_p)

        u_val = sin(x_p(1)) * cos(x_p(2))
        v_val = -cos(x_p(1)) * sin(x_p(2))
        w_val = 0.0_ccs_real

        call set_row(global_index_p, u_vals)
        call set_entry(u_val, u_vals)
        call set_row(global_index_p, v_vals)
        call set_entry(v_val, v_vals)
        call set_row(global_index_p, w_vals)
        call set_entry(w_val, w_vals)
      end do

      call set_values(u_vals, u%values)
      call set_values(v_vals, v%values)
      call set_values(w_vals, w%values)

      deallocate (u_vals%global_indices)
      deallocate (v_vals%global_indices)
      deallocate (w_vals%global_indices)
      deallocate (u_vals%values)
      deallocate (v_vals%values)
      deallocate (w_vals%values)
    end associate

    call get_vector_data(mf%values, mf_data)

    count = 0
    n = 0

    ! Loop over local cells and faces
    do index_p = 1, mesh%topo%local_num_cells

      call set_cell_location(mesh, index_p, loc_p)
      call count_neighbours(loc_p, nnb)
      do j = 1, nnb

        call set_neighbour_location(loc_p, j, loc_nb)
        call get_local_index(loc_nb, index_nb)
        
        ! if neighbour index is greater than previous face index
        if(index_nb > index_p) then ! XXX: abstract this test

          call set_face_location(mesh, index_p, j, loc_f)
          call get_local_index(loc_f, index_f)
          call get_face_normal(loc_f, face_normal)
          call get_centre(loc_f, x_f)

          ! compute initial value based on current face coordinates
          mf_data(index_f) = sin(x_f(1)) * cos(x_f(2)) * face_normal(1) &
               - cos(x_f(1)) * sin(x_f(2)) * face_normal(2)
        end if

      end do
    end do

    call restore_vector_data(mf%values, mf_data)

  end subroutine initialise_velocity

end program tgv2d