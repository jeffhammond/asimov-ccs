!v Test the cell/face centres of a square mesh.
!
!  The cell/face centres of a mesh should all fall within the meshed domain, for a
!  square mesh \f$x\in[0,1]^d\f$.
program test_square_mesh_centres

  use testing_lib

  use constants, only: ndim
  use meshing, only: set_cell_location, set_face_location, get_centre
  use mesh_utils, only: build_square_mesh

  implicit none

  type(ccs_mesh) :: mesh

  real(ccs_real) :: l
  integer(ccs_int) :: n

  integer(ccs_int) :: i
  integer(ccs_int) :: j

  type(cell_locator) :: loc_p
  real(ccs_real), dimension(ndim) :: cc
  type(face_locator) :: loc_f
  real(ccs_real), dimension(ndim) :: fc

  call init()

  do n = 1, 100
    l = parallel_random(par_env)
    mesh = build_square_mesh(par_env, n, l)

    do i = 1, mesh%topo%local_num_cells
      call set_cell_location(mesh, i, loc_p)
      call get_centre(loc_p, cc)
      associate (x => cc(1), y => cc(2))
        if ((x > l) .or. (x < 0_ccs_real) &
            .or. (y > l) .or. (y < 0_ccs_real)) then
          write (message, *) "FAIL: expected cell centre 0 <= x,y <= ", l, " got ", x, " ", y
          call stop_test(message)
        end if
      end associate

      associate (nnb => mesh%topo%num_nb(i))
        do j = 1, nnb
          call set_face_location(mesh, i, j, loc_f)
          call get_centre(loc_f, fc)
          associate (x => fc(1), y => fc(2))
            if ((x > (l + eps)) .or. (x < (0.0_ccs_real - eps)) &
                .or. (y > (l + eps)) .or. (y < (0.0_ccs_real - eps))) then
              write (message, *) "FAIL: expected face centre 0 <= x,y <= ", l, " got ", x, " ", y
              call stop_test(message)
            end if
          end associate
        end do
      end associate
    end do

  end do

  call fin()

end program test_square_mesh_centres
