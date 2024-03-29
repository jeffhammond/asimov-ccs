!> @brief Test the mesh generator creates a closed mesh.
!
!> @description A valid mesh should be "closed" that is the surface integral should be zero. The
!!              same is true of mesh cells.
program test_mesh_closed

  use testing_lib

  use constants

  use meshing, only: set_face_location, get_face_normal, get_face_area
  use mesh_utils, only: build_mesh

  implicit none

  type(ccs_mesh), target :: mesh
  type(face_locator) :: loc_f

  integer(ccs_int) :: n, nx, ny, nz
  real(ccs_real) :: l

  real(ccs_real), dimension(ndim) :: S
  real(ccs_real), dimension(ndim) :: norm
  real(ccs_real) :: A

  integer(ccs_int) :: i, j

  real(ccs_real) :: A_expected

  call init()

  ! XXX: use smaller size than 2D test - 20^3 ~= 100^2
  do n = 1, 20 ! XXX: Should use some named constant, not just "20"

    nx = n
    ny = n
    nz = n

    l = parallel_random(par_env)
    mesh = build_mesh(par_env, nx, nz, ny, l)

    A_expected = (l / n)**2

    ! Loop over cells
    do i = 1, mesh%topo%local_num_cells
      S(:) = 0.0_ccs_real

      ! Loop over neighbours/faces
      do j = 1, mesh%topo%num_nb(i)

        call set_face_location(mesh, i, j, loc_f)
        call get_face_area(loc_f, A)
        call get_face_normal(loc_f, norm)
        S(:) = S(:) + norm(:) * A

        if (abs(A - A_expected) > 1.0e-8) then
          write (message, *) "FAIL: expected face area ", A_expected, " got ", A
          call stop_test(message)
        end if
      end do

      ! Loop over axes
      do j = 1, ndim
        print *, S(j), j
        if (abs(S(j) - 0.0_ccs_real) > eps) then
          write (message, *) "FAIL: expected", 0.0_ccs_real, " got ", S(j)
          call stop_test(message)
        end if
      end do
    end do
  end do

  call fin()

end program test_mesh_closed
