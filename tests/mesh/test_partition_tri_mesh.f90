!v Test that partitions a tri mesh generated by CCS
!
!  The tri mesh has a simple partition and is already connected, computing the connectivity
!  should not change the connectivity.

program test_partition_tri_mesh
#include "ccs_macros.inc"

  use mpi

  use testing_lib
  use partitioning, only: compute_partitioner_input, &
                          partition_kway, compute_connectivity
  use kinds, only: ccs_int, ccs_long
  ! use types, only: topology
  use mesh_utils, only: build_square_mesh

  use utils, only: debug_print

  implicit none

  ! type(topology) :: topo
  type(ccs_mesh), target :: mesh
  integer :: i

  integer, parameter :: topo_idx_type = kind(mesh%topo%adjncy(1))
  integer(topo_idx_type) :: current, previous

  ! Topology grid size
  integer, parameter :: nrows = 3
  integer, parameter :: ncols = 5

  call init()
  call initialise_test()

  !n = count(mesh%topo%nb_indices > 0)
  !print*,"Number of positive value neighbour indices: ", n
  print *, "Adjacency arrays: ", mesh%topo%adjncy
  print *, "Adjacency index array: ", mesh%topo%xadj

  call compute_connectivity(par_env, mesh)
  call check_topology("mid")

  call partition_kway(par_env, mesh)

  if (par_env%proc_id == 0) then
    print *, "Global partition after partitioning:"
    do i = 1, mesh%topo%global_num_cells
      print *, mesh%topo%global_partition(i)
    end do
  end if

  ! Compute new connectivity after partitioning
  call compute_connectivity(par_env, mesh)

  call check_topology("post")

  call clean_test()
  call fin()

contains

  subroutine check_topology(stage)

    character(len=*), intent(in) :: stage

    !if (size(topo%nb_indices, 2) /= size(mesh%topo%nb_indices, 2) .or. &
    !     size(topo%nb_indices, 1) /= size(mesh%topo%nb_indices, 1)) then
    !  print *, "TOPO local_num_cells: ", topo%local_num_cells
    !  print *, "TOPO nb_indices: ", size(topo%nb_indices, 1), size(topo%nb_indices, 2)
    !  print *, "TOPO partition: ", topo%global_partition
    !  print *, "MESH nlocal: ", mesh%topo%local_num_cells
    !  print *, "MESH nb_indices: ", size(mesh%topo%nb_indices, 1), size(mesh%topo%nb_indices, 2)
    !  write(message, *) "ERROR: topology size is wrong!"
    !  call stop_test(message)
    !end if

    call check_distribution(stage)

    if ((maxval(mesh%topo%xadj(1:size(mesh%topo%xadj) - 1)) >= size(mesh%topo%adjncy)) &
        .or. (mesh%topo%xadj(size(mesh%topo%xadj) - 1) > size(mesh%topo%adjncy))) then
      print *, mesh%topo%xadj
      print *, size(mesh%topo%adjncy)
      write (message, *) "ERROR: xadj array is wrong."
      call stop_test(message)
    end if

    if ((maxval(mesh%topo%global_indices) > 16) .or. (minval(mesh%topo%global_indices) < 1)) then
      write (message, *) "ERROR: global indices min/max: ", &
        minval(mesh%topo%global_indices), maxval(mesh%topo%global_indices), &
        " outside expected range: ", 1, 16
      call stop_test(message)
    end if

    call check_self_loops(stage)
    call check_connectivity(stage)

  end subroutine

  subroutine check_distribution(stage)

    character(len=*), intent(in) :: stage

    integer :: i
    integer :: ctr

    ! Do some basic verification

    if (size(mesh%topo%vtxdist) /= (par_env%num_procs + 1)) then
      write (message, *) "ERROR: global vertex distribution is wrong size " // stage // "- partitioning."
      call stop_test(message)
    end if

    ctr = 0
    do i = 2, size(mesh%topo%vtxdist)
      if (mesh%topo%vtxdist(i) < mesh%topo%vtxdist(i - 1)) then
        write (message, *) "ERROR: global vertex distribution ordering is wrong " // stage // "- partitioning."
        call stop_test(message)
      end if

      ctr = ctr + int(mesh%topo%vtxdist(i) - mesh%topo%vtxdist(i - 1), ccs_int)
    end do

    if (ctr /= mesh%topo%global_num_cells) then
      write (message, *) "ERROR: global vertex distribution count is wrong " // stage // "- partitioning."
      call stop_test(message)
    end if

  end subroutine

  subroutine check_self_loops(stage)

    character(len=*), intent(in) :: stage

    integer :: i, j

    do i = 1, mesh%topo%local_num_cells
      do j = int(mesh%topo%xadj(i), ccs_int), int(mesh%topo%xadj(i + 1), ccs_int) - 1
        if (mesh%topo%adjncy(j) == mesh%topo%global_indices(i)) then
          print *, "TOPO neighbours @ global idx ", mesh%topo%global_indices(i), ": ", mesh%topo%adjncy(mesh%topo%xadj(i):mesh%topo%xadj(i+1) - 1)
          write (message, *) "ERROR: found self-loop " // stage // "- partitioning."
          call stop_test(message)
        end if
      end do
    end do

  end subroutine

  subroutine check_connectivity(stage)

    character(len=*), intent(in) :: stage

    integer :: i, j
    integer :: nadj
    integer, dimension(:), allocatable :: adjncy_global_expected

    do i = 1, mesh%topo%local_num_cells ! Loop over local cells

      nadj = int(mesh%topo%xadj(i + 1) - mesh%topo%xadj(i), ccs_int)
      allocate (adjncy_global_expected(nadj))

      call compute_expected_global_adjncy(i, adjncy_global_expected)

      do j = int(mesh%topo%xadj(i), ccs_int), int(mesh%topo%xadj(i + 1), ccs_int) - 1
        if (.not. any(adjncy_global_expected == mesh%topo%adjncy(j))) then
          print *, "TOPO neighbours @ global idx ", mesh%topo%global_indices(i), ": ", mesh%topo%adjncy(mesh%topo%xadj(i):mesh%topo%xadj(i+1) - 1)
          print *, "Expected neighbours @ global idx ", mesh%topo%global_indices(i), ": ", adjncy_global_expected
          write (message, *) "ERROR: neighbours are wrong " // stage // "- partitioning."
          call stop_test(message)
        end if
      end do

      do j = 1, size(adjncy_global_expected)
        if (.not. any(mesh%topo%adjncy == adjncy_global_expected(j))) then
          print *, "TOPO neighbours @ global idx ", mesh%topo%global_indices(i), ": ", mesh%topo%adjncy(mesh%topo%xadj(i):mesh%topo%xadj(i+1) - 1)
          print *, "Expected neighbours @ global idx ", mesh%topo%global_indices(i), ": ", adjncy_global_expected
          write (message, *) "ERROR: neighbours are missing " // stage // "- partitioning."
          call stop_test(message)
        end if
      end do

      deallocate (adjncy_global_expected)
    end do

  end subroutine

  subroutine compute_expected_global_adjncy(i, adjncy_global_expected)

    integer, intent(in) :: i
    integer, dimension(:), intent(inout) :: adjncy_global_expected

    integer :: interior_ctr

    logical :: left_boundary, right_boundary

    adjncy_global_expected(:) = 0
    interior_ctr = 1

    left_boundary = .false.
    right_boundary = .false.

    associate (idx_global => mesh%topo%global_indices(i), &
               cidx_global => (mesh%topo%global_indices(i) - 1))
      if ((modulo(cidx_global, ncols) /= 0) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ left boundary
        adjncy_global_expected(interior_ctr) = idx_global - 1
        interior_ctr = interior_ctr + 1
      else
        left_boundary = .true.
      end if

      if ((modulo(cidx_global, ncols) /= (ncols - 1)) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ right boundary
        adjncy_global_expected(interior_ctr) = idx_global + 1
        interior_ctr = interior_ctr + 1
      else
        right_boundary = .true.
      end if

      if (((cidx_global / ncols) /= 0) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ bottom boundary
        adjncy_global_expected(interior_ctr) = idx_global - ncols
        interior_ctr = interior_ctr + 1
        if (.not. left_boundary) then
          ! There is a down, left neighbour
          adjncy_global_expected(interior_ctr) = idx_global - ncols - 1
          interior_ctr = interior_ctr + 1
        end if
      end if

      if (((cidx_global / ncols) /= (nrows - 1)) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ top boundary
        adjncy_global_expected(interior_ctr) = idx_global + ncols
        interior_ctr = interior_ctr + 1
        if (.not. right_boundary) then
          ! There is an up, right neighbour
          adjncy_global_expected(interior_ctr) = idx_global + ncols + 1
          interior_ctr = interior_ctr + 1
        end if
      end if
    end associate

  end subroutine

  subroutine initialise_test

    integer :: ctr
    integer :: i, j

    ! Create a tri mesh
    !
    ! Sample graph - adapted from ParMETIS manual to use 1-indexing with added triangular connections.
    !
    !  1 - 2 - 3 - 4 - 5
    !  | \ | \ | \ | \ |
    !  6 - 7 - 8 - 9 -10
    !  | \ | \ | \ | \ |
    ! 11 -12 -13 -14 -15
    !
    ! N.B. in terms of "top"/"bottom" boundaries this graph should be reflected about the horizontal axis.

    ! --- read_topology() ---
    mesh%topo%global_num_cells = nrows * ncols
    mesh%topo%global_num_faces = 46 ! Hardcoded for now (check face array counts)
    mesh%topo%max_faces = 6 ! mesh%topo%num_nb(1)
    allocate (mesh%topo%face_cell1(mesh%topo%global_num_faces))
    allocate (mesh%topo%face_cell2(mesh%topo%global_num_faces))
    allocate (mesh%topo%global_face_indices(mesh%topo%max_faces, mesh%topo%global_num_cells))

    ! Hardcode for now
    mesh%topo%face_cell1 = (/1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, &   ! 20 count
                                 6, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10, &                ! 15 count
                                 11, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15/)                   ! 11 count = 46
    mesh%topo%face_cell2 = (/0, 0, 2, 7, 6, 0, 3, 8, 7, 0, 4, 9, 8, 0, 5, 10, 9, 0, 0, 10, & ! 20 count
                                 0, 7, 12, 11, 8, 13, 12, 9, 14, 13, 10, 15, 14, 0, 15, &        ! 15 count
                                 0, 12, 0, 13, 0, 14, 0, 15, 0, 0, 0/)                          ! 11 count = 46

    ! <MISSING> set topo%global_face_indices

    ! --- read_topology() --- end

    ! --- compute_partitioner_input() ---
    allocate (mesh%topo%vtxdist(par_env%num_procs + 1))
    allocate (mesh%topo%global_partition(mesh%topo%global_num_cells))

    ! Hardcode vtxdist for now
    mesh%topo%vtxdist = (/1, 6, 11, 16/)

    ! <MISSING> set topo%global_partition array?
    ! FAKE partition array based on initial mesh decomposition
    ctr = 1
    do i = 1, mesh%topo%global_num_cells
      if (i == mesh%topo%vtxdist(ctr + 1)) then
        ctr = ctr + 1
      end if
      mesh%topo%global_partition(i) = (ctr - 1) ! Partitions/ranks are zero-indexed
    end do

    !select type(par_env)
    !type is (parallel_environment_mpi)
    !  allocate(tmp_partition, source=topo%global_partition)
    !  write(message, *) "Initial partition: ", tmp_partition
    !  call dprint(message)
    !  call MPI_Allreduce(tmp_partition, topo%global_partition, topo%global_num_cells, &
    !          MPI_LONG, MPI_SUM, &
    !          par_env%comm, ierr)
    !  deallocate(tmp_partition)
    !  write(message, *) "Using partition: ", topo%global_partition
    !  call dprint(message)
    !class default
    !  write(message, *) "ERROR: This test only works for MPI!"
    !  call stop_test(message)
    !end select

    mesh%topo%local_num_cells = int(mesh%topo%vtxdist(par_env%proc_id + 2) - mesh%topo%vtxdist(par_env%proc_id + 1), ccs_int)
    allocate (mesh%topo%xadj(mesh%topo%local_num_cells + 1))

    ! <MISSING> allocate topo%global_boundaries
    ! <MISSING> allocate topo%adjncy

    allocate (mesh%topo%local_partition(mesh%topo%local_num_cells))
    mesh%topo%halo_num_cells = 0

    select type (par_env)
    type is (parallel_environment_mpi)

      ! Also hardcode the adjncy arrays
      if (par_env%num_procs == 3) then

        if (par_env%proc_id == 0) then
          mesh%topo%adjncy = (/2, 6, 7, &
                                   1, 3, 7, 8, &
                                   2, 4, 8, 9, &
                                   3, 5, 9, 10, &
                                   4, 10/)
        else if (par_env%proc_id == 1) then
          mesh%topo%adjncy = (/1, 7, 11, 12, &
                                   1, 2, 6, 8, 12, 13, &
                                   2, 3, 7, 9, 13, 14, &
                                   3, 4, 8, 10, 14, 15, &
                                   4, 5, 9, 15/)
        else
          mesh%topo%adjncy = (/6, 12, &
                                   6, 7, 11, 13, &
                                   7, 8, 12, 14, &
                                   8, 9, 13, 15, &
                                   9, 10, 14/)
        end if

      else
        write (message, *) "Test must be run on 3 MPI ranks"
        call stop_test(message)
      end if

    class default
      write (message, *) "ERROR: Unknown parallel environment."
      call stop_test(message)
    end select

    ! Now compute the adjacency index array
    ! XXX: this relies on adjacency being sorted within each cell
    !      in ascending order.
    j = 1
    mesh%topo%xadj(j) = 1
    previous = mesh%topo%adjncy(1)

    do i = 2, size(mesh%topo%adjncy)
      current = mesh%topo%adjncy(i)
      if (current < previous) then
        j = j + 1
        mesh%topo%xadj(j) = i
      end if
      previous = current
    end do

    mesh%topo%xadj(j + 1) = size(mesh%topo%adjncy) + 1

    allocate (mesh%topo%adjwgt(size(mesh%topo%adjncy)))
    allocate (mesh%topo%vwgt(mesh%topo%local_num_cells))

    ! --- compute_partitioner_input() --- end

    ! Assign corresponding mesh values to the topology object
    ! mesh%topo%total_num_cells = mesh%topo%total_num_cells
    ! mesh%topo%num_faces = mesh%topo%num_faces

    allocate (mesh%topo%global_indices(mesh%topo%local_num_cells))
    do i = 1, mesh%topo%local_num_cells
      mesh%topo%global_indices(i) = int(mesh%topo%vtxdist(par_env%proc_id + 1), ccs_int) + (i - 1)
    end do

    ! These need to be set to 1 for them to do nothing
    if (allocated(mesh%topo%adjwgt) .and. allocated(mesh%topo%vwgt)) then
      mesh%topo%adjwgt = 1
      mesh%topo%vwgt = 1
    else
      call stop_test("Not allocated.")
    end if

    ! Run test to check we agree
    call check_topology("pre")

  end subroutine

  subroutine clean_test
    if (allocated(mesh%topo%xadj)) then
      deallocate (mesh%topo%xadj)
    end if

    if (allocated(mesh%topo%adjncy)) then
      deallocate (mesh%topo%adjncy)
    end if

    if (allocated(mesh%topo%adjwgt)) then
      deallocate (mesh%topo%adjwgt)
    end if

    if (allocated(mesh%topo%vwgt)) then
      deallocate (mesh%topo%vwgt)
    end if

    if (allocated(mesh%topo%vtxdist)) then
      deallocate (mesh%topo%vtxdist)
    end if
  end subroutine

end program
