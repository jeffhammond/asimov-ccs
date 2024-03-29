!v Module file adios2_types.f90
!
!  Provides the types neesded for ADIOS2-based IO.
!
!  @build mpi adios2
module adios2_types

  use adios2
  use types, only: io_environment, io_process

  implicit none

  private

  !> ADIOS2 environment
  type, public, extends(io_environment) :: adios2_env
    type(adios2_adios) :: adios
  end type

  !> ADIOS2 process, incluidng the IO task and engine
  type, public, extends(io_process) :: adios2_io_process
    type(adios2_io) :: io_task
    type(adios2_engine) :: engine
  end type

end module
