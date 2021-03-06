module momentum_symmetry

! Module for handling model system crystal momentum symmetry.

! Stored symmetry information for the Hubbard model (and non-model periodic) systems.  UEG symmetry is
! done on the fly due to the size of the basis---see ueg module.

! Momentum symmetry for non-model periodic systems is implemented within read_in_symmetry.f90 and
! momentum_sym_read_in.f90.

use system

implicit none

contains

    subroutine init_momentum_symmetry(sys)

        ! Construct the symmetry tables.

        ! In/Out:
        !    sys: system to be studied.  On output the symmetry components are set.

        use system
        use kpoints, only: is_reciprocal_lattice_vector
        use checking, only: check_allocate
        use errors, only: stop_all
        use ueg_system, only: init_ueg_indexing

        type(sys_t), intent(inout) :: sys

        integer :: i, j, k, ierr, iunit
        integer :: ksum(sys%lattice%ndim)

        iunit = 6

        ! model systems use symmetry indices starting from 1.
        sys%sym0 = 1
        sys%nsym = sys%basis%nbasis/2 ! two spin orbitals per wavevector
        sys%sym_max = sys%nsym
        sys%sym0_tot = sys%sym0
        sys%nsym_tot = sys%nsym
        sys%sym_max_tot = sys%sym_max

        select case(sys%system)
        case(hub_k)

            ! Each wavevector corresponds to its own irreducible representation.
            ! The maximum system size considered will be quite small (ie <200)
            ! and the sum of any two wavevectors is another wavevector in the
            ! basis (up to a primitive reciprocal lattice vector).
            ! It is thus feasible to store the nsym^2 product table.
            allocate(sys%hubbard%mom_sym%sym_table(sys%nsym, sys%nsym), stat=ierr)
            call check_allocate('sym_table',sys%nsym*sys%nsym,ierr)
            allocate(sys%hubbard%mom_sym%inv_sym(sys%nsym), stat=ierr)
            call check_allocate('inv_sym',sys%nsym,ierr)

            sys%hubbard%mom_sym%gamma_sym = 0
            do i = 1, sys%nsym
                if (all(sys%basis%basis_fns(i*2)%l == 0)) sys%hubbard%mom_sym%gamma_sym = i
            end do
            if (sys%hubbard%mom_sym%gamma_sym == 0) call stop_all('init_momentum_symmetry', 'Gamma-point symmetry not found.' &
                      //'Kpoint meshes not containing the gamma point are not currently supported.')
            if (sys%tot_sym) sys%symmetry = sys%hubbard%mom_sym%gamma_sym

            do i = 1, sys%nsym
                do j = i, sys%nsym
                    ksum = sys%basis%basis_fns(i*2)%l + sys%basis%basis_fns(j*2)%l
                    do k = 1, sys%nsym
                        if (is_reciprocal_lattice_vector(sys, ksum - sys%basis%basis_fns(k*2)%l)) then
                            sys%hubbard%mom_sym%sym_table(i,j) = k
                            sys%hubbard%mom_sym%sym_table(j,i) = k
                            if (k == sys%hubbard%mom_sym%gamma_sym) then
                                sys%hubbard%mom_sym%inv_sym(i) = j
                                sys%hubbard%mom_sym%inv_sym(j) = i
                            end if
                            exit
                        end if
                    end do
                end do
            end do

            call print_hubbard_k_symmetry_info(sys, iunit)

        case(ueg)

            ! Trickier.
            ! No primitive reciprocal lattice and thus a secondary basis eight
            ! times larger than the basis used is required to span all
            ! possible k_i+k_j combinations.  As we wish to do calculations on
            ! basis sets containing 1000s of wavevectors, it is not feasible to
            ! store the product table as we do for the Hubbard model.

            ! Instead, we have a function which produces an index for a given
            ! k-point and a mapping array which converts that index to the index
            ! of the energy-ordered basis set.  The symmetry is then done on the
            ! fly.

            ! We'll only consider determinants with symmetry corresponding to
            ! a basis function though.
            sys%nsym = sys%basis%nbasis/2

            sys%ueg%gamma_sym = 0
            do i = 1, sys%nsym
                if (all(sys%basis%basis_fns(i*2)%l == 0)) sys%ueg%gamma_sym = i
            end do
            if (sys%ueg%gamma_sym == 0) call stop_all('init_momentum_symmetry', 'Gamma-point symmetry not found.')

            if (sys%tot_sym) sys%symmetry = sys%ueg%gamma_sym

            call init_ueg_indexing(sys)

        end select

    end subroutine init_momentum_symmetry

    subroutine print_hubbard_k_symmetry_info(sys, iunit)

        ! Function to print all information about symmetry of a given
        ! k-space hubbard model from an initialised sys_t object.

        ! In:
        !   sys: initialised sys_t object for k-space hubbard model.
        !   iunit: io unit to print information to.

        use parallel, only: parent
        use basis, only: write_basis_fn
        use system, only: sys_t
        use utils, only: int_fmt

        type(sys_t), intent(in) :: sys
        integer, intent(in) :: iunit
        character(4) :: fmt1
        integer :: i, j

        fmt1 = int_fmt(sys%nsym)

        if (parent) then
            write (iunit,'(1X,a20,/,1X,20("-"),/)') "Symmetry information"
            write (iunit,'(1X,a63,/)') 'The table below gives the label and inverse of each wavevector.'
            write (iunit,'(1X,a5,4X,a7)', advance='no') 'Index','k-point'
            do i = 1, sys%lattice%ndim
                write (iunit,'(3X)', advance='no')
            end do
            write (iunit,'(a7)') 'Inverse'
            do i = 1, sys%nsym
                write (iunit,'(i4,5X)', advance='no') i
                call write_basis_fn(sys, sys%basis%basis_fns(2*i), new_line=.false., print_full=.false.)
                write (iunit,'(5X,i4)') sys%hubbard%mom_sym%inv_sym(i)
            end do
            write (iunit,'()')
            write (iunit,'(1X,a83,/)') &
                "The matrix below gives the result of k_i+k_j to within a reciprocal lattice vector."
            do i = 1, sys%nsym
                do j = 1, sys%nsym
                    write (iunit,'('//fmt1//')', advance='no') sys%hubbard%mom_sym%sym_table(j,i)
                end do
                write (iunit,'()')
            end do
            write (iunit,'()')
        end if

    end subroutine print_hubbard_k_symmetry_info

    elemental function cross_product_k(sys, s1, s2) result(prod)

        ! In:
        !    sys: system being studied.
        !    s1, s2: irreducible representation labels/momentum labels.
        ! Returns:
        !    s1 \cross s2, the direct product of the two symmetries.

        ! NOTE: this is just a convenience wrapper around the different
        ! implementations of momentum symmetry.  Do not use in a tight loop!

        use system, only: sys_t, hub_k, ueg

        integer :: prod
        type(sys_t), intent(in) :: sys
        integer, intent(in) :: s1, s2

        select case(sys%system)
        case(hub_k)
            prod = cross_product_hub_k(sys%hubbard%mom_sym, s1, s2)
        case(ueg)
            prod = cross_product_ueg(sys, s1, s2)
        end select

    end function cross_product_k

    elemental function cross_product_hub_k(mom_sym, s1, s2) result(prod)

        ! In:
        !    mom_sym: basis function symmetry information.
        !    s1, s2: irreducible representation labels/momentum labels.
        ! Returns:
        !    s1 \cross s2, the direct product of the two symmetries.

        ! Hubbard model in momentum space has small enough basis that we can
        ! store the symmetry table easily.

        integer :: prod
        integer, intent(in) :: s1, s2
        type(mom_sym_t), intent(in) :: mom_sym

        prod = mom_sym%sym_table(s1, s2)

    end function cross_product_hub_k

    elemental function cross_product_ueg(sys, s1, s2) result(prod)

        ! In:
        !    sys: system being studied.
        !    s1, s2: irreducible representation labels/momentum labels.
        ! Returns:
        !    s1 \cross s2, the direct product of the two symmetries.
        !    If s1 and s2 are *not* in the basis, then an integer less than 1 is
        !    returned.  As such, this *must* *not* be called in a chain; i.e.
        !    the output used in another call to cross_product_ueg.  Instead, all
        !    vector summations must be performed before converting to a basis.

        ! UEG basis can be large; avoid storing O(N^2) symmetry table.

        use system, only: sys_t
        use ueg_system, only: ueg_basis_index

        integer :: prod
        type(sys_t), intent(in) :: sys
        integer, intent(in) :: s1, s2

        ! Can't use sys%lattice%ndim as the size in a pure function so set it
        ! to the max dimension and then use an array slice.
        integer :: k(3)

        ! Find k_1+k_2.  Need to convert s1 and s2 into basis set indices.
        k(:sys%lattice%ndim) = sys%basis%basis_fns(2*s1)%l + sys%basis%basis_fns(2*s2)%l
        ! Get symmetry index.  Need to convert from basis set index back into
        ! wavevector index.
        prod = (ueg_basis_index(sys%ueg%basis, k(:sys%lattice%ndim),1)+1)/2

    end function cross_product_ueg

    pure function symmetry_orb_list_hub_k(mom_sym, orb_list) result(isym)

        ! In:
        !    mom_sym: basis function symmetry information.
        !    orb_list: list of orbitals (e.g. determinant).
        ! Returns:
        !    symmetry index of list (i.e. direct product of the representations
        !    of all the orbitals in the list).

        ! For momentum symmetry in the Hubbard model.

        use symmetry_types, only: mom_sym_t

        integer :: isym
        type(mom_sym_t), intent(in) :: mom_sym
        integer, intent(in) :: orb_list(:)

        integer :: i

        isym = mom_sym%gamma_sym
        do i = lbound(orb_list, dim=1), ubound(orb_list, dim=1)
            isym = cross_product_hub_k(mom_sym, (orb_list(i)+1)/2, isym)
        end do

    end function symmetry_orb_list_hub_k

    pure function symmetry_orb_list_ueg(sys, orb_list) result(isym)

        ! In:
        !    sys: system to be studied.  On output the symmetry components are set.
        !    orb_list: list of orbitals (e.g. determinant).
        ! Returns:
        !    symmetry index of list (i.e. direct product of the representations
        !    of all the orbitals in the list).
        !    If the overall symmetry is *not* in the basis, then an integer less than 1 is
        !    returned.  As such, this *must* *not* be called in a chain; i.e.
        !    the output used in a call to cross_product_ueg.  Instead, all
        !    vector summations must be performed before converting to a basis.

        ! For momentum symmetry in the UEG.

        use system, only: sys_t
        use ueg_system, only: ueg_basis_index

        integer :: isym
        type(sys_t), intent(in) :: sys
        integer, intent(in) :: orb_list(:)

        integer :: i, k(sys%lattice%ndim)

        k = 0
        do i = lbound(orb_list, dim=1), ubound(orb_list, dim=1)
            ! Cannot use cross_product_ueg for multiple operations.
            k = k + sys%basis%basis_fns(orb_list(i))%l
        end do
        ! Convert to symmetry index.
        isym = (ueg_basis_index(sys%ueg%basis,k,1)+1)/2

    end function symmetry_orb_list_ueg

end module momentum_symmetry
