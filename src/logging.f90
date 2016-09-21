module logging

! Module to contain functions handling logging outputs.

contains

    subroutine init_logging(logging_in, logging)
        use qmc_data, only: logging_t, logging_in_t

        type(logging_t), intent(inout) :: logging
        type(logging_in_t), intent(in) :: logging_in

        if (logging_in%calc > 0) call init_logging_calc(logging_in, logging)
        if (logging_in%spawn > 0) call init_logging_spawn(logging_in, logging)
        if (logging_in%death > 0) call init_logging_death(logging_in, logging)
        !if (logging_in%annihilation > 0) call init_logging_calc(logging_in, logging)

    end subroutine init_logging

    subroutine prep_logging_mc_cycle(iter, logging_in, logging_info)

        ! Subroutine to
        !   - check if within the range of iterations where logging is required.
        !   - print updates for iteration number in all active logs.

        use qmc_data, only: logging_t, logging_in_t

        integer, intent(in) :: iter
        type(logging_t), intent(inout) :: logging_info
        type(logging_in_t), intent(in) :: logging_in

        logging_info%write_logging = (logging_in%start_iter <= iter .and. &
                                    iter <= logging_in%end_iter)

        if (logging_info%write_logging) then
            if (logging_info%calc_unit /= huge(1)) call write_iter_to_log(iter, logging_info%calc_unit)
            if (logging_info%spawn_unit /= huge(1)) call write_iter_to_log(iter, logging_info%spawn_unit)
            if (logging_info%death_unit /= huge(1)) call write_iter_to_log(iter, logging_info%death_unit)
        end if

    end subroutine prep_logging_mc_cycle

    subroutine write_iter_to_log(iter, iunit)
        ! Writes iteration number to given io unit for logging.
        integer :: iter, iunit

        write(iunit, '(1X,20("="))')
        write(iunit, '(1X,"Iteration",1X,i10)') iter
        write(iunit, '(1X,20("="))')

    end subroutine write_iter_to_log

    subroutine end_logging(logging_info)
        use qmc_data, only: logging_t

        type(logging_t), intent(in) :: logging_info

        if (logging_info%calc_unit /= huge(1)) close(logging_info%calc_unit, status='keep')
        if (logging_info%spawn_unit /= huge(1)) close(logging_info%spawn_unit, status='keep')
        if (logging_info%death_unit /= huge(1)) close(logging_info%death_unit, status='keep')

    end subroutine end_logging

    subroutine init_logging_calc(logging_in, logging)

        use qmc_data, only: logging_t, logging_in_t
        use utils, only: get_free_unit
        use calc, only: calc_type, fciqmc_calc, ccmc_calc

        type(logging_t), intent(inout) :: logging
        type(logging_in_t), intent(in) :: logging_in
        integer :: iunit

        print *, 'Opening file ', logging_in%calc_filename
        open(newunit=logging%calc_unit, file=logging_in%calc_filename, status='unknown')

        if (logging_in%calc > 0) logging%write_highlevel_values = .true.
        if (logging_in%calc > 1) logging%write_highlevel_calculations = .true.

        call write_logging_calc_header(logging)

    end subroutine init_logging_calc

    subroutine init_logging_spawn(logging_in, logging)

        use qmc_data, only: logging_t, logging_in_t
        use utils, only: get_free_unit
        use calc, only: calc_type, fciqmc_calc, ccmc_calc

        type(logging_t), intent(inout) :: logging
        type(logging_in_t), intent(in) :: logging_in
        integer :: iunit

        !logging%spawn_unit = get_free_unit()

        print *, 'Opening file ', logging_in%spawn_filename
        open(newunit=logging%spawn_unit, file=logging_in%spawn_filename, status='unknown')

        if (logging_in%spawn > 0) logging%write_successful_spawn = .true.
        if (logging_in%spawn > 1) logging%write_spawn_dets = .true.
        if (logging_in%spawn > 2) logging%write_failed_spawn = .true.

        call write_logging_spawn_header(logging)

    end subroutine init_logging_spawn

    subroutine init_logging_death(logging_in, logging)

        use qmc_data, only: logging_t, logging_in_t
        use utils, only: get_free_unit
        use calc, only: calc_type, fciqmc_calc, ccmc_calc

        type(logging_t), intent(inout) :: logging
        type(logging_in_t), intent(in) :: logging_in
        integer :: iunit

        !logging%death_unit = get_free_unit()

        print *, 'Opening file ', logging_in%death_filename
        open(newunit=logging%death_unit, file=logging_in%death_filename, status='unknown')

        if (logging_in%death > 0) logging%write_successful_death = .true.
        if (logging_in%death > 1) logging%write_death_det = .true.
        if (logging_in%death > 2) logging%write_failed_death = .true.

        call write_logging_death_header(logging)

    end subroutine init_logging_death

    subroutine write_logging_calc_header(logging)
        use calc, only: calc_type, fciqmc_calc, ccmc_calc
        use qmc_data, only: logging_t
        type(logging_t), intent(in) :: logging

        select case (calc_type)
        case(fciqmc_calc)
            write (logging%calc_unit, '(1X,"HANDE QMC Calculation Log File")')
            write (logging%calc_unit, '(1X,"==============================")')
            write (logging%calc_unit, '(1X,"Calculation type: FCIQMC")')
            write (logging%calc_unit, '(1X,"Verbosity Settings:")')
        case(ccmc_calc)
            write (logging%calc_unit, *) 'dsfgsg'
        end select
    end subroutine write_logging_calc_header

    subroutine write_logging_spawn_header(logging)
        use calc, only: calc_type, fciqmc_calc, ccmc_calc
        use qmc_data, only: logging_t
        type(logging_t), intent(in) :: logging

        select case (calc_type)
        case(fciqmc_calc)
            write (logging%spawn_unit, '(1X,"HANDE QMC Spawning Log File")')
            write (logging%spawn_unit, '(1X,"===========================")')
            write (logging%spawn_unit, '(1X,"Calculation type: FCIQMC")')
            write (logging%spawn_unit, '(1X,"Verbosity Settings:")')
        case(ccmc_calc)
            write (logging%spawn_unit, *) 'dsfgsg'
        end select
    end subroutine write_logging_spawn_header

    subroutine write_logging_death_header(logging)
        use calc, only: calc_type, fciqmc_calc, ccmc_calc
        use qmc_data, only: logging_t
        type(logging_t), intent(in) :: logging

        select case (calc_type)
        case(fciqmc_calc)
            write (logging%death_unit, '(1X,"HANDE QMC Death Log File")')
            write (logging%death_unit, '(1X,"========================")')
            write (logging%death_unit, '(1X,"Calculation type: FCIQMC")')
            write (logging%death_unit, '(1X,"Verbosity Settings:")')
        case(ccmc_calc)
            write (logging%death_unit, *) 'dsfgsg'
        end select
    end subroutine write_logging_death_header

end module logging
