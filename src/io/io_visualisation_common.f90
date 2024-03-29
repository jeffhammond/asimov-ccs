!v Submodule file io_visualisation_common.smod
!
!  An implementation of the visualisation-related IO routines

submodule(io_visualisation) io_visualisation_common
#include "ccs_macros.inc"

  use constants, only: ndim

  implicit none

contains

  !> Write the flow solution for the current time-step to file
  module subroutine write_solution(par_env, case_name, mesh, output_list, step, maxstep, dt)

    ! Arguments
    class(parallel_environment), allocatable, target, intent(in) :: par_env  !< The parallel environment
    character(len=:), allocatable, intent(in) :: case_name                   !< The case name
    type(ccs_mesh), intent(in) :: mesh                                       !< The mesh
    type(field_ptr), dimension(:), intent(inout) :: output_list              !< List of fields to output
    integer(ccs_int), optional, intent(in) :: step                           !< The current time-step count
    integer(ccs_int), optional, intent(in) :: maxstep                        !< The maximum time-step count
    real(ccs_real), optional, intent(in) :: dt                               !< The time-step size

    ! Write the required fields ('heavy' data)
    if (present(step) .and. present(maxstep)) then
      ! Unsteady case
      call write_fields(par_env, case_name, mesh, output_list, step, maxstep)
    else
      ! Steady case
      call write_fields(par_env, case_name, mesh, output_list)
    end if

    ! Write the XML descriptor ('light' data)
    if (present(step) .and. present(maxstep) .and. present(dt)) then
      ! Unsteady case
      call write_xdmf(par_env, case_name, mesh, output_list, step, maxstep, dt)
    else
      ! Steady case
      call write_xdmf(par_env, case_name, mesh, output_list)
    end if

  end subroutine

  !> Write the XML descriptor file, which describes the grid and flow data in the 'heavy' data files
  module subroutine write_xdmf(par_env, case_name, mesh, output_list, step, maxstep, dt)

    use case_config, only: write_gradients

    ! Arguments
    class(parallel_environment), allocatable, target, intent(in) :: par_env  !< The parallel environment
    character(len=:), allocatable, intent(in) :: case_name                   !< The case name
    type(ccs_mesh), intent(in) :: mesh                                       !< The mesh
    type(field_ptr), dimension(:), intent(inout) :: output_list              !< List of fields to output
    integer(ccs_int), optional, intent(in) :: step                           !< The current time-step count
    integer(ccs_int), optional, intent(in) :: maxstep                        !< The maximum time-step count
    real(ccs_real), optional, intent(in) :: dt                               !< The time-step size

    ! Local variables
    character(len=:), allocatable :: xdmf_file   ! Name of the XDMF (XML) file
    character(len=:), allocatable :: sol_file    ! Name of the solution file
    character(len=:), allocatable :: geo_file    ! Name of the mesh file
    character(len=50) :: fmt                     ! Format string
    integer(ccs_int), save :: ioxdmf             ! IO unit of the XDMF file
    integer(ccs_int), save :: step_counter = 0   ! ADIOS2 step counter
    integer(ccs_int) :: num_vel_cmp             ! Number of velocity components in output field list
    integer(ccs_int) :: i                       ! Loop counter

    character(len=2), parameter :: l1 = '  '           ! Indentation level 1
    character(len=4), parameter :: l2 = '    '         ! Indentation level 2
    character(len=6), parameter :: l3 = '      '       ! Indentation level 3
    character(len=8), parameter :: l4 = '        '     ! Indentation level 4
    character(len=10), parameter :: l5 = '          '   ! Indentation level 5
    character(len=12), parameter :: l6 = '            ' ! Indentation level 6

    xdmf_file = case_name // '.sol.xmf'
    sol_file = case_name // '.sol.h5'
    geo_file = case_name // '.geo'

    ! On first call, write the header of the XML file
    if (par_env%proc_id == par_env%root) then
      if (present(step)) then
        ! Unsteady case
        if (step == 1) then
          ! Open file
          open (newunit=ioxdmf, file=xdmf_file, status='unknown')

          ! Write file contents
          write (ioxdmf, '(a)') '<?xml version = "1.0"?>'
          write (ioxdmf, '(a)') '<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd">'
          write (ioxdmf, '(a)') '<Xdmf Version = "2.0">'
          write (ioxdmf, '(a,a)') l1, '<Domain>'
          write (ioxdmf, '(a,a)') l2, '<Grid Name = "Unsteady" GridType = "Collection" CollectionType = "Temporal">'
        end if
      else
        ! Steady case
        ! Open file
        open (newunit=ioxdmf, file=xdmf_file, status='unknown')

        ! Write file contents
        write (ioxdmf, '(a)') '<?xml version = "1.0"?>'
        write (ioxdmf, '(a)') '<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd">'
        write (ioxdmf, '(a)') '<Xdmf Version = "2.0">'
        write (ioxdmf, '(a,a)') l1, '<Domain>'
      end if

      associate (ncel => mesh%topo%global_num_cells, &
                 nvrt => mesh%topo%global_num_vertices)

        write (ioxdmf, '(a,a)') l3, '<Grid Name = "Mesh">'

        if (present(step)) then
          write (ioxdmf, '(a,a,f10.7,a)') l4, '<Time Value = "', step * dt, '" />'
        end if

        ! Topology
        if (mesh%topo%vert_per_cell == 4) then
          write (ioxdmf, '(a,a,i0,a)') l4, '<Topology Type = "Quadrilateral" NumberOfElements = "', ncel, '" BaseOffset = "1">'
        else
          write (ioxdmf, '(a,a,i0,a)') l4, '<Topology Type = "Hexahedron" NumberOfElements = "', ncel, '" BaseOffset = "1">'
        end if

        fmt = '(a,a,i0,1x,i0,3(a))'
        write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, mesh%topo%vert_per_cell, '" Format = "HDF">', &
          trim(geo_file), ':/Step0/cell/vertices</DataItem>'
        write (ioxdmf, '(a,a)') l4, '</Topology>'

        ! Geometry
        write (ioxdmf, '(a,a)') l4, '<Geometry Type = "XYZ">'
        write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', nvrt, ndim, '" Format = "HDF">', trim(geo_file), &
          ':/Step0/vert</DataItem>'
        write (ioxdmf, '(a,a)') l4, '</Geometry>'

        ! Velocity vector
        ! Count number of velocity components in list of fields to be written out
        num_vel_cmp = 0
        do i = 1, size(output_list)
          if (trim(output_list(i)%name) == 'u') then
            num_vel_cmp = num_vel_cmp + 1
          else if (trim(output_list(i)%name) == 'v') then
            num_vel_cmp = num_vel_cmp + 1
          else if (trim(output_list(i)%name) == 'w') then
            num_vel_cmp = num_vel_cmp + 1
          end if
        end do

        if (num_vel_cmp > 0) then
          write (ioxdmf, '(a,a)') l4, '<Attribute Name = "velocity" AttributeType = "Vector" Center = "Cell">'

          fmt = '(a,a,i0,1x,i0,a)'
          if (num_vel_cmp == 1) then
            write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, 1, '" ItemType = "Function" Function = "JOIN($0)">'
          else if (num_vel_cmp == 2) then
            write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, 2, '" ItemType = "Function" Function = "JOIN($0, $1)">'
          else if (num_vel_cmp == 3) then
            write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, 3, '" ItemType = "Function" Function = "JOIN($0, $1, $2)">'
          end if

          fmt = '(a,a,i0,3(a),i0,a)'

          do i = 1, size(output_list)
            if (trim(output_list(i)%name) == 'u') then
              write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
                step_counter, '/u</DataItem>'
            else if (trim(output_list(i)%name) == 'v') then
              write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
                step_counter, '/v</DataItem>'
            else if (trim(output_list(i)%name) == 'w') then
              write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
                step_counter, '/w</DataItem>'
            end if
          end do
          write (ioxdmf, '(a,a)') l5, '</DataItem>'
          write (ioxdmf, '(a,a)') l4, '</Attribute>'
        end if

        ! Pressure
        do i = 1, size(output_list)
          if (trim(output_list(i)%name) == 'p') then
            write (ioxdmf, '(a,a)') l4, '<Attribute Name = "pressure" AttributeType = "Scalar" Center = "Cell">'
            write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, '" Format = "HDF">', trim(sol_file), ':/Step', &
              step_counter, '/p</DataItem>'
            write (ioxdmf, '(a,a)') l4, '</Attribute>'
          end if
        end do

        ! Kinetic Energy
        if (num_vel_cmp > 0) then
          write (ioxdmf, '(a,a)') l4, '<Attribute Name = "kinetic energy" AttributeType = "Scalar" Center = "Cell">'

          fmt = '(a,a,i0,a,a)'

          if (num_vel_cmp == 1) then
            write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, '" ItemType = "Function"', &
              ' Function = "0.5 * ($0*$0)">'
          else if (num_vel_cmp == 2) then
            write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, '" ItemType = "Function"', &
              ' Function = "0.5 * ($0*$0 + $1*$1)">'
          else if (num_vel_cmp == 3) then
            write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, '" ItemType = "Function"', &
              ' Function = "0.5 * ($0*$0 + $1*$1 + $2*$2)">'
          end if

          fmt = '(a,a,i0,3(a),i0,a)'

          do i = 1, size(output_list)
            if (trim(output_list(i)%name) == 'u') then
              write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
                step_counter, '/u</DataItem>'
            else if (trim(output_list(i)%name) == 'v') then
              write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
                step_counter, '/v</DataItem>'
            else if (trim(output_list(i)%name) == 'w') then
              write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
                step_counter, '/w</DataItem>'
            end if
          end do
          write (ioxdmf, '(a,a)') l5, '</DataItem>'
          write (ioxdmf, '(a,a)') l4, '</Attribute>'
        end if

        ! Enstrophy
        if (write_gradients .and. (num_vel_cmp == 3)) then
          write (ioxdmf, '(a,a)') l4, '<Attribute Name = "enstrophy" AttributeType = "Scalar" Center = "Cell">'

          fmt = '(a,a,i0,a,a)'
          write (ioxdmf, fmt) l5, '<DataItem Dimensions = "', ncel, '" ItemType = "Function"', &
            ' Function = "0.5 * (($5-$3)*($5-$3) + ($1-$4)*($1-$4) + ($2-$0)*($2-$0))">'

          fmt = '(a,a,i0,3(a),i0,a)'
          write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
            step_counter, '/dudy</DataItem>'
          write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
            step_counter, '/dudz</DataItem>'
          write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
            step_counter, '/dvdx</DataItem>'
          write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
            step_counter, '/dvdz</DataItem>'
          write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
            step_counter, '/dwdx</DataItem>'
          write (ioxdmf, fmt) l6, '<DataItem Format = "HDF" Dimensions = "', ncel, '">', trim(sol_file), ':/Step', &
            step_counter, '/dwdy</DataItem>'
          write (ioxdmf, '(a,a)') l5, '</DataItem>'
          write (ioxdmf, '(a,a)') l4, '</Attribute>'
        end if

        write (ioxdmf, '(a,a)') l3, '</Grid>'

      end associate

      flush (ioxdmf)

      ! On final call, write the closing tags and close the XML file
      if (present(step)) then
        ! Unsteady case
        if (step == maxstep) then
          write (ioxdmf, '(a,a)') l2, '</Grid>'
          write (ioxdmf, '(a,a)') l1, '</Domain>'
          write (ioxdmf, '(a)') '</Xdmf>'
          close (ioxdmf)
        end if
      else
        ! Steady case
        write (ioxdmf, '(a,a)') l1, '</Domain>'
        write (ioxdmf, '(a)') '</Xdmf>'
        close (ioxdmf)
      end if
    end if ! root

    ! Increment ADIOS2 step counter
    step_counter = step_counter + 1

  end subroutine write_xdmf

end submodule
