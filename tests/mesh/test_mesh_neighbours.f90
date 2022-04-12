!> @brief Test that cells have correct numbers of neighbours
!
!> @description for any mesh with >1 cell, every cell must have at least 1 neighbour.
program test_mesh_neighbours

  use testing_lib

  use meshing, only : set_cell_location, set_neighbour_location, count_neighbours, get_boundary_status
  use mesh_utils, only : build_square_mesh

  implicit none
  
  type(ccs_mesh), target :: mesh
  type(cell_locator) :: cell_location

  integer(ccs_int) :: n
  real(ccs_real) :: l

  integer(ccs_int) :: i

  integer(ccs_int) :: nnb
  integer(ccs_int) :: j

  type(neighbour_locator) :: loc_nb
  logical :: is_boundary
  integer(ccs_int) :: boundary_ctr
  integer(ccs_int) :: global_boundary_ctr
  integer(ccs_int) :: expected_boundary_ctr

  call init()
  
  do n = 1, 100 ! XXX: Need a test-wide variable nmax
    l = parallel_random(par_env)
    mesh = build_square_mesh(par_env, n, l)

    boundary_ctr = 0
    do i = 1, mesh%nlocal

      call set_cell_location(mesh, i, cell_location)
      call count_neighbours(cell_location, nnb)

      if (nnb < 2) then
        ! In the case of a cell at the end of a chain of cells it should have 1 interior neighbour
        ! and 1 boundary/external neighbour - c.f. 1D boundary cell.
        ! Even in the limit of single 1D cell should have 2 boundary neighbours.
        write(message, *) "FAIL: cell should have 2 or more neighbours, got ", nnb
        call stop_test(message)
      else if (nnb > 4) then
        ! XXX: specific to 2D Cartesian mesh
        write(message, *) "FAIL: cell should have at most ", 4, " neighbours, got ", nnb
        call stop_test(message)
      end if

      ! Loop over neighbours
      do j = 1, nnb
        call set_neighbour_location(cell_location, j, loc_nb)
        call get_boundary_status(loc_nb, is_boundary)
        if (is_boundary) then
          ! Boundary neighbour/face
          boundary_ctr = boundary_ctr + 1
        else
          call test_mesh_internal_neighbours(loc_nb)
        end if
      end do

    end do

    ! Check total boundary neighbours
    select type(par_env)
    type is (parallel_environment_mpi)
      call MPI_Allreduce(boundary_ctr, global_boundary_ctr, 1, MPI_INT, MPI_SUM, par_env%comm, ierr)
    class default
      write(message, *) "ERROR: Unknown parallel environment!"
      call stop_test(message)
    end select

    expected_boundary_ctr = 4 * n ! XXX: specific to 2D Cartesian mesh (square mesh has 2^d sides
                                  !      of length n)
    if (global_boundary_ctr /= expected_boundary_ctr) then
      write(message, *) "FAIL: mesh boundary count is incorrect, expected ", &
           expected_boundary_ctr, " got ", global_boundary_ctr
      call stop_test(message)
    end if
  end do

  call fin()

contains

  subroutine test_mesh_internal_neighbours(loc_nb)

    use meshing, only : count_neighbours, get_local_index, get_boundary_status, get_local_status
    
    type(neighbour_locator), intent(in) :: loc_nb

    integer(ccs_int) :: index_nb
    type(cell_locator) :: cell_loc_nb
    integer(ccs_int) :: nnb
    logical :: found_parent
    integer(ccs_int) :: j
    type(neighbour_locator) :: loc_nb_nb
    logical :: is_boundary
    logical :: is_local
    
    associate(mesh => loc_nb%mesh, &
         parent_idx => loc_nb%cell_idx)
      call get_local_index(loc_nb, index_nb)
            
      ! Neighbour index should not be its parents
      if (index_nb == parent_idx) then
        write(message, *) "FAIL: Neighbour has same index ", index_nb, " as parent cell ", parent_idx
        call stop_test(message)
      end if

      call get_local_status(loc_nb, is_local)
      if (is_local) then
        ! Parent should be in neighbour's neighbour list
        call set_cell_location(mesh, index_nb, cell_loc_nb)
        call count_neighbours(cell_loc_nb, nnb)
        found_parent = .false.
        do j = 1, nnb
          call set_neighbour_location(cell_loc_nb, j, loc_nb_nb)
          call get_boundary_status(loc_nb_nb, is_boundary)
          if (.not. is_boundary) then ! We are looking for parent cell - by definition not a boundary!
            call get_local_index(loc_nb_nb, index_nb)
            if (index_nb == parent_idx) then
              found_parent = .true.
              exit
            end if
          end if
        end do
        if (.not. found_parent) then
          write(message, *) "FAIL: Couldn't find cell in neighbour's neighbour list!"
          call stop_test(message)
        end if
      end if
      
    end associate
    
  end subroutine test_mesh_internal_neighbours
  
end program test_mesh_neighbours