module mesh_utils

  use constants, only : ndim
  
  use kinds, only: accs_int, accs_real
  use types, only: mesh, face_locator, cell_locator, neighbour_locator
  use parallel_types, only: parallel_environment
  use parallel_types_mpi, only: parallel_environment_mpi
  use meshing, only: get_global_index, get_local_index, count_neighbours, &
                     set_cell_location, set_neighbour_location, set_face_location, &
                     set_face_index, get_boundary_status, get_local_status

  
  implicit none

  !> @note Named constants for faces of hexahedral cells follow the convention that the lower
  !!       boundary on a given axis is numbered first, i.e.
  !!
  !!           4
  !!     +----------+
  !!     |          |
  !!     |          |
  !!   1 |          | 2
  !!     |          |
  !!     +----------+
  !!           3
  !!
  integer, parameter :: left = 1_accs_int
  integer, parameter :: right = 2_accs_int
  integer, parameter :: down = 3_accs_int
  integer, parameter :: up = 4_accs_int
  
  private
  public :: build_square_mesh
  public :: count_mesh_faces
  
contains

  !> @brief Utility constructor to build a square mesh.
  !
  !> @description Builds a Cartesian grid of NxN cells on the domain LxL.
  !
  !> @param[in] integer(accs_int)    nps         - Number of cells per side of the mesh.
  !> @param[in] real(accs_real)      l           - The length of each side
  !> @param[in] parallel_environment par_env     - The parallel environment to construct the mesh.
  !
  !> @returns   mesh                 square_mesh - The mesh
  function build_square_mesh(par_env, nps, l) result(square_mesh)

    class(parallel_environment), intent(in) :: par_env
    integer(accs_int), intent(in) :: nps
    real(accs_real), intent(in) :: l

    type(mesh) :: square_mesh

    integer(accs_int) :: istart    !> The (global) starting index of a partition
    integer(accs_int) :: iend      !> The (global) last index of a partition
    integer(accs_int) :: i         !> Loop counter
    integer(accs_int) :: ii        !> Zero-indexed loop counter (simplifies some operations)
    integer(accs_int) :: ictr      !> Local index counter
    integer(accs_int) :: fctr      !> Cell-local face counter
    integer(accs_int) :: comm_rank !> The process ID within the parallel environment
    integer(accs_int) :: comm_size !> The size of the parallel environment

    integer(accs_int) :: nbidx     !> The local index of a neighbour cell
    integer(accs_int) :: nbidxg    !> The global index of a neighbour cell

    select type(par_env)
      type is (parallel_environment_mpi)

        ! Set the global mesh parameters
        square_mesh%nglobal = nps**2            
        square_mesh%h = l / real(nps, accs_real)

        ! Associate aliases to make code easier to read
        associate(nglobal=>square_mesh%nglobal, &
                  h=>square_mesh%h)
          
          ! Determine ownership range (based on PETSc ex3.c)
          comm_rank = par_env%proc_id
          comm_size = par_env%num_procs
          istart = comm_rank * (nglobal / comm_size)
          if (modulo(nglobal, comm_size) < comm_rank) then
            istart = istart + modulo(nglobal, comm_size)
          else
            istart = istart + comm_rank
          end if
          iend = istart + nglobal / comm_size
          if (modulo(nglobal, comm_size) > comm_rank) then
            iend = iend + 1_accs_int
          end if

          ! Fix indexing and determine size of local partition
          istart = istart + 1_accs_int
          square_mesh%nlocal = (iend - (istart - 1_accs_int))

          ! Allocate mesh arrays
          allocate(square_mesh%idx_global(square_mesh%nlocal))
          allocate(square_mesh%nnb(square_mesh%nlocal))
          allocate(square_mesh%nbidx(4, square_mesh%nlocal))
          allocate(square_mesh%faceidx(4, square_mesh%nlocal))

          ! Initialise mesh arrays
          square_mesh%nnb(:) = 4_accs_int ! All cells have 4 neighbours (possibly ghost/boundary cells)

          ! First set the global index of local cells
          ictr = 1_accs_int
          do i = istart, iend
            square_mesh%idx_global(ictr) = i
            ictr = ictr + 1
          end do
          
          ! Assemble cells and faces
          ! XXX: Negative neighbour indices are used to indicate boundaries using the same numbering
          !      as cell-relative neighbour indexing, i.e.
          !        -1 = left boundary
          !        -2 = right boundary
          !        -3 = down boundary
          !        -4 = up boundary
          ictr = 1_accs_int ! Set local indexing starting from 1...n
          do i = istart, iend 
            ii = i - 1_accs_int

            ! Construct left (1) face/neighbour
            fctr = left
            if (modulo(ii, nps) == 0_accs_int) then
              nbidx = -left
              nbidxg = -left
            else
              nbidx = ictr - 1_accs_int
              nbidxg = i - 1_accs_int
            end if
            call build_local_mesh_add_neighbour(ictr, fctr, nbidx, nbidxg, square_mesh)

            ! Construct right (2) face/neighbour
            fctr = right
            if (modulo(ii, nps) == (nps - 1_accs_int)) then
              nbidx = -right
              nbidxg = -right
            else
              nbidx = ictr + 1_accs_int
              nbidxg = i + 1_accs_int
            end if
            call build_local_mesh_add_neighbour(ictr, fctr, nbidx, nbidxg, square_mesh)

            ! Construct down (3) face/neighbour
            fctr = down
            if ((ii / nps) == 0_accs_int) then
              nbidx = -down
              nbidxg = -down
            else
              nbidx = ictr - nps
              nbidxg = i - nps
            end if
            call build_local_mesh_add_neighbour(ictr, fctr, nbidx, nbidxg, square_mesh)

            ! Construct up (4) face/neighbour
            fctr = up
            if ((ii / nps) == (nps - 1_accs_int)) then
              nbidx = -up
              nbidxg = -up
            else
              nbidx = ictr + nps
              nbidxg = i + nps
            end if
            call build_local_mesh_add_neighbour(ictr, fctr, nbidx, nbidxg, square_mesh)

            ictr = ictr + 1_accs_int
          end do
        end associate

        square_mesh%ntotal = size(square_mesh%idx_global)
        square_mesh%nhalo = square_mesh%ntotal - square_mesh%nlocal

        allocate(square_mesh%xc(ndim, square_mesh%ntotal))    
        allocate(square_mesh%xf(ndim, 4, square_mesh%nlocal)) !> @note Currently hardcoded as a 2D mesh!
        allocate(square_mesh%vol(square_mesh%ntotal))
        allocate(square_mesh%Af(4, square_mesh%nlocal))    
        allocate(square_mesh%nf(ndim, 4, square_mesh%nlocal)) !> @note Currently hardcoded as a 2D mesh!

        square_mesh%vol(:) = square_mesh%h**2 !> @note Mesh is square and 2D
        square_mesh%nf(:, :, :) = 0.0_accs_real
        square_mesh%xc(:, :) = 0.0_accs_real
        square_mesh%xf(:, :, :) = 0.0_accs_real
        square_mesh%Af(:, :) = square_mesh%h  !> @note Mesh is square and 2D

        associate(h => square_mesh%h)
          do i = 1_accs_int, square_mesh%ntotal
            ii = square_mesh%idx_global(i)

            associate(xc => square_mesh%xc(:, i))
              ! Set cell centre
              xc(1) = (modulo(ii-1, nps) + 0.5_accs_real) * h
              xc(2) = ((ii - 1) / nps + 0.5_accs_real) * h
            end associate
          end do

          do i = 1_accs_int, square_mesh%nlocal
            associate(xc => square_mesh%xc(:, i), &
                 xf => square_mesh%xf(:, :, i), &
                 nrm => square_mesh%nf(:, :, i))

              fctr = left
              xf(1, fctr) = xc(1) - 0.5_accs_real * h
              xf(2, fctr) = xc(2)
              nrm(1, fctr) = -1.0_accs_real
              nrm(2, fctr) = 0.0_accs_real

              fctr = right
              xf(1, fctr) = xc(1) + 0.5_accs_real * h
              xf(2, fctr) = xc(2)
              nrm(1, fctr) = 1.0_accs_real
              nrm(2, fctr) = 0.0_accs_real
              
              fctr = down
              xf(1, fctr) = xc(1)
              xf(2, fctr) = xc(2) - 0.5_accs_real * h
              nrm(1, fctr) = 0.0_accs_real
              nrm(2, fctr) = -1.0_accs_real

              fctr = up
              xf(1, fctr) = xc(1)
              xf(2, fctr) = xc(2) + 0.5_accs_real * h
              nrm(1, fctr) = 0.0_accs_real
              nrm(2, fctr) = 1.0_accs_real
            end associate
          end do
        end associate

        square_mesh%nfaces_local = count_mesh_faces(square_mesh)

        call set_cell_face_indices(square_mesh)

      class default
        print *, "Unknown parallel environment type!"
        stop

    end select    
  end function build_square_mesh

  !> @brief Helper subroutine to add a neighbour to a cell's neighbour list.
  !
  !> @description Given a local and global index for a neighbour there are 3 possibilities:
  !!              1) the local and the neighbour is added immediately
  !!              2) the global index is negative indicating it is a boundary and the "neighbour" is
  !!                 added immediately
  !!              3) the index is not local:
  !!                 a) the global index is already in the off-process list (halos), the neighbour
  !!                    is added immediately
  !!                 b) this is a new halo cell, the list of global indices must be grown to
  !!                    accomodate before adding the neighbour.
  !
  !> @param[in]    integer(accs_int) cellidx - the index of the cell whose neighbours we are assembling
  !> @param[in]    integer(accs_int) nbctr   - the cell-relative neighbour index
  !> @param[in]    integer(accs_int) nbidx   - the local index of the neighbour cell
  !> @param[in]    integer(accs_int) nbidxg  - the global index of the neighbour cell
  !> @param[inout] mesh meshobj - the mesh we are assembling neighbours on
  subroutine build_local_mesh_add_neighbour(cellidx, nbctr, nbidx, nbidxg, meshobj)

    integer(accs_int), intent(in) :: cellidx
    integer(accs_int), intent(in) :: nbctr
    integer(accs_int), intent(in) :: nbidx
    integer(accs_int), intent(in) :: nbidxg
    type(mesh), intent(inout) :: meshobj

    integer(accs_int) :: ng !> The current number of cells (total = local + halos)
    logical :: found        !> Indicates whether a halo cell was already present
    integer(accs_int) :: i  !> Cell iteration counter
    
    if ((nbidx >= 1_accs_int) .and. (nbidx <= meshobj%nlocal)) then
      ! Neighbour is local
      meshobj%nbidx(nbctr, cellidx) = nbidx
    else if (nbidxg < 0_accs_int) then
      ! Boundary "neighbour" - local index should also be -ve
      if (.not. (nbidx < 0_accs_int)) then
        print *, "ERROR: boundary neighbours should have -ve indices!"
        stop
      end if
      meshobj%nbidx(nbctr, cellidx) = nbidx
    else
      ! Neighbour is in a halo

      ! First check if neighbour is already present in halo
      ng = size(meshobj%idx_global)
      found = .false.
      do i = meshobj%nlocal + 1, ng
        if (meshobj%idx_global(i) == nbidxg) then
          found = .true.
          meshobj%nbidx(nbctr, cellidx) = i
          exit
        end if
      end do

      ! If neighbour was not present append to global index list (the end of the global index list
      ! becoming its local index).
      ! XXX: Note this currently copies into an n+1 temporary, reallocates and then copies back to
      !      the (extended) original array.
      if (.not. found) then
        if ((ng + 1) > meshobj%nglobal) then
          print *, "ERROR: Trying to create halo that exceeds global mesh size!"
          stop
        end if
        
        call append_to_arr(nbidxg, meshobj%idx_global)
        ng = size(meshobj%idx_global)
        meshobj%nbidx(nbctr, cellidx) = ng
      end if
    end if
    
  end subroutine build_local_mesh_add_neighbour

  subroutine append_to_arr(i, arr)

    integer(accs_int), intent(in) :: i
    integer(accs_int), dimension(:), allocatable, intent(inout) :: arr ! XXX: Allocatable here be
                                                                       !      dragons! If this were
                                                                       !      intent(out) it would
                                                                       !      be deallocated on entry!

    integer(accs_int) :: n
    integer(accs_int), dimension(:), allocatable :: tmp

    n = size(arr)

    allocate(tmp(n + 1))

    tmp(1:n) = arr(1:n)

    n = n + 1
    tmp(n) = i

    deallocate(arr)
    allocate(arr(n))
    arr(:) = tmp(:)
    deallocate(tmp)
    
  end subroutine append_to_arr

  !> @brief Count the number of faces in the mesh
  !
  !> @param[in]  cell_mesh - the mesh
  !> @param[out] nfaces    - number of cell faces
  function count_mesh_faces(cell_mesh) result(nfaces)

    ! Arguments
    type(mesh), intent(in) :: cell_mesh

    ! Result
    integer(accs_int) :: nfaces

    ! Local variables
    type(cell_locator) :: self_loc
    type(neighbour_locator) :: ngb_loc
    integer(accs_int) :: self_idx, local_idx
    integer(accs_int) :: j
    integer(accs_int) :: n_ngb
    integer(accs_int) :: nfaces_int       !> Internal face count
    integer(accs_int) :: nfaces_bnd       !> Boundary face count
    integer(accs_int) :: nfaces_interface !> Process interface face count
    logical :: is_boundary
    logical :: is_local

    ! Initialise
    nfaces_int = 0
    nfaces_bnd = 0
    nfaces_interface = 0

    ! Loop over cells
    do local_idx = 1, cell_mesh%nlocal
      call set_cell_location(cell_mesh, local_idx, self_loc)
      call get_global_index(self_loc, self_idx)
      call count_neighbours(self_loc, n_ngb)

      do j = 1, n_ngb
        call set_neighbour_location(self_loc, j, ngb_loc)
        call get_boundary_status(ngb_loc, is_boundary)

        if (.not. is_boundary) then
          call get_local_status(ngb_loc, is_local)
          
          if (is_local) then
            ! Interior face
            nfaces_int = nfaces_int + 1
          else
            ! Process boundary face
            nfaces_interface = nfaces_interface + 1
          end if
        else
          ! Boundary face
          nfaces_bnd = nfaces_bnd + 1
        endif
      end do
    end do

    ! Interior faces will be counted twice
    nfaces = (nfaces_int / 2) + nfaces_interface + nfaces_bnd

  end function count_mesh_faces

  subroutine set_cell_face_indices(cell_mesh)

    ! Arguments
    type(mesh), intent(inout) :: cell_mesh

    ! Local variables
    type(cell_locator) :: self_loc !> Current cell
    type(cell_locator) :: ngb_cell_loc !> Neighbour of current cell
    type(neighbour_locator) :: ngb_loc !> Neighbour
    type(neighbour_locator) :: ngb_ngb_loc !> Neighbour of neighbour
    type(face_locator) :: face_loc
    integer(accs_int) :: ngb_idx, local_idx
    integer(accs_int) :: ngb_ngb_idx, face_idx
    integer(accs_int) :: n_ngb, n_ngb_ngb
    integer(accs_int) :: j,k
    integer(accs_int) :: icnt  !> Face index counter
    logical :: is_boundary

    icnt = 0

    ! Loop over cells
    do local_idx = 1, cell_mesh%nlocal
      call set_cell_location(cell_mesh, local_idx, self_loc)
      call count_neighbours(self_loc, n_ngb)

      do j = 1, n_ngb
        call set_neighbour_location(self_loc, j, ngb_loc)
        call get_local_index(ngb_loc, ngb_idx)
        call get_boundary_status(ngb_loc, is_boundary)

        if (.not. is_boundary) then
          ! Cell with lowest local index assigns an index to the face
          if (local_idx < ngb_idx) then
            icnt = icnt + 1
            call set_face_index(local_idx, j, icnt, cell_mesh)
          else
            ! Find corresponding face in neighbour cell
            ! (To be improved, this seems inefficient!)
            call set_cell_location(cell_mesh, ngb_idx, ngb_cell_loc)
            call count_neighbours(ngb_cell_loc, n_ngb_ngb)
            do k = 1, n_ngb_ngb
              call set_neighbour_location(ngb_cell_loc, k, ngb_ngb_loc)
              call get_local_index(ngb_ngb_loc, ngb_ngb_idx)
              if (ngb_ngb_idx == local_idx) then
                call set_face_location(cell_mesh, ngb_idx, k, face_loc)
                call get_local_index(face_loc, face_idx)
                call set_face_index(local_idx, j, face_idx, cell_mesh)
                exit ! Exit the loop, as found shared face
              else if (k == n_ngb_ngb) then
                print *, "ERROR: Failed to find face in owning cell"
                stop 1
              endif
            end do
          endif
        else
          icnt = icnt + 1
          call set_face_index(local_idx, j, icnt, cell_mesh)
        endif
      end do  ! End loop over current cell's neighbours
    end do    ! End loop over local cells

  end subroutine set_cell_face_indices
  
end module mesh_utils
