module excit_gen_cauchy_schwarz

use const, only: i0, p

implicit none

type excit_gen_cauchy_schwarz_t
    real(p), allocatable :: aliasP(:,:) !(max(sys%nvirt_alpha,sys%nvirt_beta),sys%nel)
    integer, allocatable :: aliasY(:,:) !(max(sys%nvirt_alpha,sys%nvirt_beta),sys%nel)
    real(p), allocatable :: ia_weights(:,:) !(max(sys%nvirt_alpha,sys%nvirt_beta),sys%nel)
    real(p), allocatable :: ia_weights_tot(:) !(sys%nel)
    integer, allocatable :: virt_list_a(:) !(sys%nvirt_alpha)
    integer, allocatable :: virt_list_b(:) !(sys%nvirt_beta)
    integer, allocatable :: occ_list(:) !(nel)
end type excit_gen_cauchy_schwarz_t


contains
    subroutine create_weighted_excitation_list(sys, from, to_list, nto, weights, weighttot)
        ! Generate a list of allowed excitations from from to one of to_list with their weights based on
        ! sqrt(|<from to  | to  from>|)

        use system, only: sys_t
        use molecular_integrals, only: get_two_body_int_mol
        type(sys_t), intent(in) :: sys
        integer, intent(in) :: from, nto, to_list(nto)
        real(p), intent(out) :: weights(nto), weighttot
        
        integer :: i
        real(p) :: weight

        weighttot = 0 
        do i=1, nto
            weight = get_two_body_int_mol(sys%read_in%coulomb_integrals, from, to_list(i), to_list(i), from,  & 
                        sys%basis%basis_fns, sys%read_in%pg_sym) !This exchange integral should be +ve, but best abs below in case!
!            weight = 1
            weight = sqrt(abs(weight))
            weights(i) = weight
            weighttot = weighttot + weight
        enddo
    end subroutine create_weighted_excitation_list 

    function select_weighted_value_prec(rng, N, aliasP, aliasY) result(ret)
        ! Select an element, i=1..N with probability from pre-generated alias method weights
        ! This uses the alias method, requiring O(N) storage, and O(N) time
        
        ! In:
        !    N: the number of objects to select from
        !    aliasP: a length N array of precomputed alias reals.
        !    aliasY: a length N array of precomputed alias integers
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    ret: the index of the element chosen.

        ! The 'alias method' allows one to select from a discrete probability distribution of k objects (with object j having probability p_j) in O(1) time. There's an O(k) storage and O(k) setup cost - a list of k reals (P_j) and k integers (Y_j)  which requires O(k) setup.

        ! Pick a random real number x, 0<=x<k.  Let K=floor(x) and V=x-K. (so K is an integer and V the remainder).  X will be the result
        ! If V<P_K then X=K, else X=Y_K.

        ! Here's Knuth's exercise:
        ! Vol2: 3.4.1 Ex 7 [20] (A. J. Walker) Suppose we have a bunch of cubes of k different colors, say n_j cubes of color C_j for 1<=j<=k, and we have k boxes {B_1,...,B_k} each of which can hold exactly n cubes.  Furthermore n_1+...+n_k=kn, so the cubes will just fit in the boxes.  Prove (constructively) that there is always a way to put the cubes into the boxes so that each box contains at most two different colors of cubes; in fact there is a way to do it so that, whenever box B_j contains two colors, one of those colors is C_j.  Show how to use this principle to compute the P and Y tables given a probability distribution (p_1,...p_k).



        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        type(dSFMT_t), intent(inout) :: rng
        
        integer, intent(in) :: N
        integer :: ret

        real(p) :: aliasP(N)
        integer :: aliasY(N)
        
        real(p) :: x
        integer :: K 
        ! Pick a random real number x, 0<=x<k.  Let K=floor(x) and V=x-K. (so K is an integer and V the remainder).  X will be the result
        ! If V<P_K then X=K, else X=Y_K.
        x=get_rand_close_open(rng)*N
        K=floor(x)
        x=x-K
        K=K+1
        if (x<aliasP(K)) then
            ret=K
        else
            ret=aliasY(K)
        endif
    end function select_weighted_value_prec
    function select_weighted_value(rng, N, weights, totweight) result(ret)
        ! Select an element, i=1..N with probability weights(i)/totweight.
        ! This uses the alias method, requiring O(N) storage, and O(N) time
        
        ! In:
        !    N: the number of objects to select from
        !    weights: a length N array of reals containing the weights of each element
        !    totweight: sum(weights(1:N))
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    ret: the index of the element chosen.

        ! See notes in select_weighted_value_prec

        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        type(dSFMT_t), intent(inout) :: rng
        
        integer, intent(in) :: N
        real(p), intent(in) :: totweight, weights(N) 
        integer :: ret

        real(p) :: aliasP(N)
        integer :: aliasY(N)
        
        call generate_alias_tables(N, weights, totweight, aliasP, aliasY)        
        ret = select_weighted_value_prec(rng, N, aliasP, aliasY)
    end function select_weighted_value

    subroutine generate_alias_tables(N, weights, totweight, aliasU, aliasK)
        ! Generate an alias table for the alias method.
        ! This requires O(N) time and O(2N) scratch space
        !
        ! In:
        !    N: number of objects to select from
        !    weights: a length N array of reals containing the weights of each element
        !    totweight: sum(weights(1:N))
        ! Out:
        !    aliasU: a length N array of reals for the U table
        !    aliasK: a length N array of integers for the K table.

        !
        ! The alias method (a la Wikipedia)
        ! The distribution may be padded with additional probabilities /p_i / = 0 to increase n to a convenient value, such as a power of two.

        ! To generate the table, first initialize /U_i / = /np_i /. While doing this, divide the table entries into three categories:

        !  * The "overfull" group, where /U_i / > 1,
        !  * The "underfull" group, where /U_i / < 1 and K_i has not been
        !    initialized, and
        !  * The "exactly full" group, where /U_i / = 1 or K_i /has/ been
        !    initialized.

        ! If /U_i / = 1, the corresponding value K_i will never be consulted and is unimportant, but a value of /K_i / = /i/ is sensible.

        ! As long as not all table entries are exactly full, repeat the following steps:

        ! 1. Arbitrarily choose an overfull entry /U_i / > 1 and an underfull
        !    entry /U_j / < 1. (If one of these exists, the other must, as well.)
        ! 2. Allocate the unused space in entry j to outcome i, by setting /K_j /
        !    = /i/.
        ! 3. Remove the allocated space from entry i by changing /U_i / = /U_i /
        !    - (1 - /U_j /) = /U_i / + /U_j / - 1.
        ! 4. Entry j is now exactly full.
        ! 5. Assign entry i to the appropriate category based on the new value of
        !    U_i .  

        integer, intent(in) :: N
        real(p), intent(in) :: totweight, weights(N) 
        real(p), intent(out) :: aliasU(N)
        integer, intent(out) :: aliasK(N)

        ! Working space:  We need a list of the underfull and the overfull, and a copy of the weights
        integer :: underfull(N)
        integer :: overfull(N)
        integer :: i, nunder, nover, ov, un

        aliasU(:)=weights(:) * (N / totweight)
        nunder = 0
        nover = 0
        do i = 1, N
            if (aliasU(i) <= 1) then
                nunder = nunder + 1
                underfull(nunder) = i
            else ! account for weight=1 as underfull
                nover = nover +1
                overfull(nover) = i
            endif
            aliasK(i)=i !just in case
        enddo
        do while (nover > 0 .and. nunder > 0)
            ! match the last nover with the last nunder
            ov = overfull(nover)
            un = underfull(nunder)
            ! put ov as the alternate for un
            aliasK(un) = ov
            ! un is now full, so we remove it from the un list
            nunder = nunder - 1
            ! remove that much probability from the ov's amount
            aliasU(ov) = aliasU(ov) - (1 - aliasU(un))
            if (aliasU(ov) < 1) then
                !move it to the under list
                nunder = nunder + 1
                underfull(nunder) = overfull(nover)
                nover = nover - 1
            endif
        enddo 
    end subroutine generate_alias_tables        

    subroutine init_excit_mol_cauchy_schwarz_occ_o1(sys, ref, cs)
        use system, only: sys_t
        use qmc_data, only: reference_t
        type(sys_t), intent(in) :: sys
        type(reference_t), intent(in) :: ref
        type(excit_gen_cauchy_schwarz_t), intent(inout) :: cs

!locals
        integer :: i, j, ind_a, ind_b, maxv, nv

        

!temp storage
        maxv=max(sys%nvirt_alpha,sys%nvirt_beta)
        allocate(cs%aliasP(maxv,sys%nel))
        allocate(cs%aliasY(maxv,sys%nel))
        allocate(cs%ia_weights(maxv,sys%nel))
        allocate(cs%ia_weights_tot(sys%nel))
        allocate(cs%occ_list(sys%nel))
        allocate(cs%virt_list_a(sys%nvirt_alpha))
        allocate(cs%virt_list_b(sys%nvirt_beta))

        cs%occ_list(:)=ref%occ_list0(:)
!make the unocc list  
        j = 1     !the next occ to look at
        ind_a = 0 !the present position in the virt_list we're making
        ind_b = 0 !the present position in the virt_list we're making
        do i=1, sys%basis%nbasis
            if (i==ref%occ_list0(j)) then !our basis fn is in the ref
                j = j + 1
            else !need to store it as a virt
                if (sys%basis%basis_fns(j)%Ms == -1) then !beta
                    ind_b = ind_b + 1
                    cs%virt_list_b(ind_b) = j
                else
                    ind_a = ind_a + 1
                    cs%virt_list_a(ind_a) = j
                endif
            endif
        enddo

        do i=1, sys%nel
            j = ref%occ_list0(i)  !The elec we're looking at
            if (sys%basis%basis_fns(j)%Ms == -1) then !beta
                nv = sys%nvirt_beta
                call create_weighted_excitation_list(sys, j, cs%virt_list_b, nv, cs%ia_weights(:,i), cs%ia_weights_tot(i))
            else !alpha
                nv = sys%nvirt_alpha
                call create_weighted_excitation_list(sys, j, cs%virt_list_a, nv, cs%ia_weights(:,i), cs%ia_weights_tot(i))
            endif
            call generate_alias_tables(nv, cs%ia_weights(:,i), cs%ia_weights_tot(i), cs%aliasP(:,i), cs%aliasY(:,i))        
        enddo
    end subroutine init_excit_mol_cauchy_schwarz_occ_o1
    subroutine gen_excit_mol_cauchy_schwarz_occ_o1(rng, sys, cs, pattempt_single, cdet, pgen, connection, hmatel, allowed_excitation)

        ! Create a random excitation from cdet and calculate both the probability
        ! of selecting that excitation and the Hamiltonian matrix element.
        ! Weight the double excitations according the the Cauchy-Schwarz bound
        ! <ij|ab> <= Sqrt(<ia|ai><jb|bj>)
        ! This is an O(1) version which pretends the determinant excited from is the reference,
        ! then modifies the selected orbitals to be those of the determinant given.
        ! Each occupied and virtual not present in the det we're actually given will be
        ! mapped to the one of the equivalent free numerical index in the reference.

        ! In:
        !    sys: system object being studied.
        !    pattempt_single: Probability to attempt a single excitation.
        !    cdet: info on the current determinant (cdet) that we will gen
        !        from.
        !    parent_sign: sign of the population on the parent determinant (i.e.
        !        either a positive or negative integer).
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    pgen: probability of generating the excited determinant from cdet.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are gened.
        !    hmatel: < D | H | D' >, the Hamiltonian matrix element between a
        !        determinant and a connected determinant in molecular systems.
        !    allowed_excitation: false if a valid symmetry allowed excitation was not generated

        use determinants, only: det_info_t
        use excitations, only: excit_t
        use excitations, only: find_excitation_permutation1, find_excitation_permutation2,get_excitation_locations
        use hamiltonian_molecular, only: slater_condon1_mol_excit, slater_condon2_mol
        use system, only: sys_t
        use excit_gen_mol, only: calc_pgen_single_mol_no_renorm,find_ia_mol


! This introduces a circular dependency, so I've just copied the function for now
!        use excit_gen_mol, only: calc_pgen_single_mol_no_renorm

        use dSFMT_interface, only: dSFMT_t, get_rand_close_open

        type(sys_t), intent(in) :: sys
        type(excit_gen_cauchy_schwarz_t), intent(in) :: cs
        real(p), intent(in) :: pattempt_single
        type(det_info_t), intent(in) :: cdet
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: pgen, hmatel
        type(excit_t), intent(out) :: connection
        logical, intent(out) :: allowed_excitation

        integer ::  ij_spin, ij_sym

      
        integer :: a, b, i, j, a_ind, b_ind, i_ind, j_ind


        integer :: nex
        integer :: cdet_store(sys%nel)
        integer :: ref_store(sys%nel)
        integer :: ii, jj, t


        ! 1. Select single or double.
        if (get_rand_close_open(rng) < pattempt_single) then


            ! 2a. Select orbital to excite from and orbital to excite into.
            call find_ia_mol(rng, sys, sys%read_in%pg_sym%gamma_sym, cdet%f, cdet%occ_list, connection%from_orb(1), &
                             connection%to_orb(1), allowed_excitation)
            connection%nexcit = 1

            if (allowed_excitation) then
                ! 3a. Probability of generating this excitation.
                pgen = pattempt_single*calc_pgen_single_mol_no_renorm(sys, connection%to_orb(1))

                ! 4a. Parity of permutation required to line up determinants.
                call find_excitation_permutation1(sys%basis%excit_mask, cdet%f, connection)

                ! 5a. Find the connecting matrix element.
                hmatel = slater_condon1_mol_excit(sys, cdet%occ_list, connection%from_orb(1), connection%to_orb(1), connection%perm)
            else
                ! Forbidden---connection%to_orb(1) is already occupied.
                hmatel = 0.0_p
                pgen = 1.0_p ! Avoid any dangerous division by pgen by returning a sane (but cheap) value.
            end if


        else !we have a double

            ! 2b. Select orbitals to excite from
            
            call choose_ij_ind(rng, sys, cdet%occ_list, i_ind, j_ind, ij_spin)
            i = cdet%occ_list(i_ind)
            j = cdet%occ_list(j_ind)


            !now we've chosen i and j. 
 
            ! We now need to select the orbitals to excite into which we do with weighting:
            ! p(ab|ij) = p(a|i) p(b|j) + p(a|j) p(b|i)
            
            ! We actually choose a|i then b|j, but since we could have also generated the excitation b from i and a from j, we need to include that prob too.

            ! Given i, construct the weights of all possible a
            if (sys%basis%basis_fns(i)%Ms < 0) then
                a_ind = select_weighted_value_prec(rng, sys%nvirt_beta, cs%aliasP(:,i_ind), cs%aliasY(:,i_ind))
                ! Use the alias method to select i with the appropriate probability
                a = cs%virt_list_b(a_ind) 
            else
                a_ind = select_weighted_value_prec(rng, sys%nvirt_alpha, cs%aliasP(:,i_ind), cs%aliasY(:,i_ind))
                ! Use the alias method to select i with the appropriate probability
                a = cs%virt_list_b(a_ind) 
            endif 
            ! Given j construct the weights of all possible b
            if (sys%basis%basis_fns(j)%Ms < 0) then
                b_ind = select_weighted_value_prec(rng, sys%nvirt_beta, cs%aliasP(:,j_ind), cs%aliasY(:,j_ind))
                ! Use the alias method to select i with the appropriate probability
                b = cs%virt_list_b(b_ind) 
            else
                b_ind = select_weighted_value_prec(rng, sys%nvirt_alpha, cs%aliasP(:,j_ind), cs%aliasY(:,j_ind))
                ! Use the alias method to select i with the appropriate probability
                b = cs%virt_list_b(b_ind) 
            endif 

            ! 3b. Probability of generating this excitation.

            ! Calculate p(ab|ij) = p(a|i) p(j|b) + p(b|i)p(a|j)
          
            if (ij_spin==0) then 
                !not possible to have chosen the reversed excitation
                pgen=cs%ia_weights(a_ind,i_ind) / cs%ia_weights_tot(i_ind) &
                        * cs%ia_weights(b_ind,j_ind) / cs%ia_weights_tot(j_ind)
            else !i and j have same spin, so could have been selected in the other order.
                pgen= (   cs%ia_weights(a_ind, i_ind) * cs%ia_weights(b_ind, j_ind) &
                        + cs%ia_weights(b_ind, j_ind) * cs%ia_weights(a_ind, i_ind) ) &
                     /   (cs%ia_weights_tot(i_ind)*cs%ia_weights_tot(j_ind))
            endif
            pgen = (1.0_p - pattempt_single) * pgen *2.0_p/(sys%nel*(sys%nel-1)) ! pgen(ab)
            connection%nexcit = 2
            allowed_excitation = (a/=b)

            if (allowed_excitation) then
!Now do the translation.  We need a list of the substitutions in cdet vs the ref.
! i.e. for each orbital in the ref-lined-up cdet which is not in ref, we need the
! location.
!  This is currently done with an O(N) step, but might be sped up at least.

                call get_excitation_locations(cs%occ_list, cdet%occ_list, ref_store, cdet_store, sys%nel, nex)
! These orbitals might not be aligned in the most efficient way:
!  They may not match in spin, so first deal with this

                do ii=1, nex
                    if (sys%basis%basis_fns(ref_store(ii))%Ms/=sys%basis%basis_fns(cdet_store(ii))%Ms) then
                        jj = ii + 1
                        do while (sys%basis%basis_fns(ref_store(ii))%Ms/=sys%basis%basis_fns(cdet_store(jj))%Ms)
                            jj = jj + 1
                        enddo
                        !j now points to an orb of the same spin as i, so swap
                        t = cdet_store(ii)
                        cdet_store(ii) = cdet_store(jj)
                        cdet_store(jj) = t 
                    endif
                enddo
                     
! At this point we may want to align the orbitals even further to avoid strange cases where selection 
! probabilities are zero, but let's leave that for another day.

! Now see if i and j are in ref_store or a and b are in cdet_store and map appropriately

                connection%from_orb(1)=i
                connection%from_orb(2)=j
                connection%to_orb(1)=a
                connection%to_orb(2)=b 
                do ii=1, nex
                    if (ref_store(ii)==i_ind) then
                        connection%from_orb(1) = cdet%occ_list(cdet_store(ii))
                    else if (ref_store(ii)==j_ind) then
                        connection%from_orb(2) = cdet%occ_list(cdet_store(ii))
                    endif
                    if (cdet%occ_list(cdet_store(ii))==a) then
                        connection%to_orb(1) = cs%occ_list(ref_store(ii))
                    else if (cdet%occ_list(cdet_store(ii))==b) then
                        connection%to_orb(2) = cs%occ_list(ref_store(ii))
                    endif
                enddo
!Now order the excitation
                if( connection%to_orb(1) > connection%to_orb(2) ) then
                    t = connection%to_orb(1)
                    connection%to_orb(1) = connection%to_orb(2)
                    connection%to_orb(2) = t
                endif
                if( connection%from_orb(1) > connection%from_orb(2) ) then
                    t = connection%from_orb(1)
                    connection%from_orb(1) = connection%from_orb(2)
                    connection%from_orb(2) = t
                endif


!            write(6,*) "EXC",cdet%f,connection%from_orb, connection%to_orb,pgen

                ! 4b. Parity of permutation required to line up determinants.
                ! NOTE: connection%from_orb and connection%to_orb *must* be ordered.
                call find_excitation_permutation2(sys%basis%excit_mask, cdet%f, connection)

                ! 5b. Find the connecting matrix element.
                hmatel = slater_condon2_mol(sys, connection%from_orb(1), connection%from_orb(2), &
                                                  connection%to_orb(1), connection%to_orb(2), connection%perm)
            else
                ! Carelessly selected ij with no possible excitations.  Such
                ! events are not worth the cost of renormalising the generation
                ! probabilities.
                ! Return a null excitation.
                hmatel = 0.0_p
                pgen = 1.0_p
            end if

        end if
    end subroutine gen_excit_mol_cauchy_schwarz_occ_o1

    subroutine choose_ij_ind(rng, sys, occ_list, i_ind, j_ind, ij_spin)

        ! Randomly select two occupied orbitals in a determinant from which
        ! electrons are excited as part of a double excitation.
        !
        ! In:
        !    sys: system object being studied.
        !    occ_list: integer list of occupied spin-orbitals in the determinant.
        !        (min length: sys%nel.)
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    i, j: orbitals in determinant from which two electrons are excited.
        !        Note that i,j are ordered such that i<j.
        !    ij_sym: symmetry conjugate of the irreducible representation spanned by the codensity
        !        \phi_i*\phi_j. (We assume that ij is going to be in the bra of the excitation.)
        !    ij_spin: spin label of the combined ij codensity.
        !        ij_spin = -2   i,j both down
        !                =  0   i up and j down or vice versa
        !                =  2   i,j both up

        use system, only: sys_t

        use dSFMT_interface, only: dSFMT_t, get_rand_close_open

        type(sys_t), intent(in) :: sys
        integer, intent(in) :: occ_list(:)
        type(dSFMT_t), intent(inout) :: rng
        integer, intent(out) :: i_ind, j_ind, ij_spin

        integer :: ind, i, j

        ! See comments in choose_ij_k for how the occupied orbitals are indexed
        ! to allow one random number to decide the ij pair.

        ind = int(get_rand_close_open(rng)*sys%nel*(sys%nel-1)/2) + 1

        ! i,j initially refer to the indices in the lists of occupied spin-orbitals
        ! rather than the spin-orbitals.
        ! Note that the indexing scheme for the strictly lower triangular array
        ! assumes j>i.  As occ_list is ordered, this means that we will return
        ! i,j (referring to spin-orbitals) where j>i.  This ordering is
        ! convenient subsequently, e.g. is assumed in the
        ! find_excitation_permutation2 routine.
        j_ind = int(1.50_p + sqrt(2*ind-1.750_p))
        i_ind = ind - ((j_ind-1)*(j_ind-2))/2

        i = occ_list(i_ind)
        j = occ_list(j_ind)

        ! ij_spin = -2 (down, down), 0 (up, down or down, up), +2 (up, up)
        ij_spin = sys%basis%basis_fns(i)%Ms + sys%basis%basis_fns(j)%Ms

    end subroutine choose_ij_ind
    subroutine gen_excit_mol_cauchy_schwarz_occ(rng, sys, pattempt_single, cdet, pgen, connection, hmatel, allowed_excitation)

        ! Create a random excitation from cdet and calculate both the probability
        ! of selecting that excitation and the Hamiltonian matrix element.
        ! Weight the double excitations according the the Cauchy-Schwarz bound
        ! <ij|ab> <= Sqrt(<ia|ai><jb|bj>)

        ! In:
        !    sys: system object being studied.
        !    pattempt_single: Probability to attempt a single excitation.
        !    cdet: info on the current determinant (cdet) that we will gen
        !        from.
        !    parent_sign: sign of the population on the parent determinant (i.e.
        !        either a positive or negative integer).
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    pgen: probability of generating the excited determinant from cdet.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are gened.
        !    hmatel: < D | H | D' >, the Hamiltonian matrix element between a
        !        determinant and a connected determinant in molecular systems.
        !    allowed_excitation: false if a valid symmetry allowed excitation was not generated

        use determinants, only: det_info_t
        use excitations, only: excit_t
        use excitations, only: find_excitation_permutation1, find_excitation_permutation2
        use hamiltonian_molecular, only: slater_condon1_mol_excit, slater_condon2_mol
        use system, only: sys_t
        use excit_gen_mol, only: calc_pgen_single_mol_no_renorm, find_ia_mol, choose_ij_mol

        use dSFMT_interface, only: dSFMT_t, get_rand_close_open

        type(sys_t), intent(in) :: sys
        real(p), intent(in) :: pattempt_single
        type(det_info_t), intent(in) :: cdet
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: pgen, hmatel
        type(excit_t), intent(out) :: connection
        logical, intent(out) :: allowed_excitation

        integer ::  ij_spin, ij_sym

        real(p) :: ia_weights(max(sys%nvirt_alpha,sys%nvirt_beta))
        real(p) :: jb_weights(max(sys%nvirt_alpha,sys%nvirt_beta))
      
        real(p) :: ia_weights_tot 
        real(p) :: jb_weights_tot 
        integer :: a, b, i, j, a_ind, b_ind


        ! 1. Select single or double.
        if (get_rand_close_open(rng) < pattempt_single) then


            ! 2a. Select orbital to excite from and orbital to excite into.
            call find_ia_mol(rng, sys, sys%read_in%pg_sym%gamma_sym, cdet%f, cdet%occ_list, connection%from_orb(1), &
                             connection%to_orb(1), allowed_excitation)
            connection%nexcit = 1

            if (allowed_excitation) then
                ! 3a. Probability of generating this excitation.
                pgen = pattempt_single*calc_pgen_single_mol_no_renorm(sys, connection%to_orb(1))

                ! 4a. Parity of permutation required to line up determinants.
                call find_excitation_permutation1(sys%basis%excit_mask, cdet%f, connection)

                ! 5a. Find the connecting matrix element.
                hmatel = slater_condon1_mol_excit(sys, cdet%occ_list, connection%from_orb(1), connection%to_orb(1), connection%perm)
            else
                ! Forbidden---connection%to_orb(1) is already occupied.
                hmatel = 0.0_p
                pgen = 1.0_p ! Avoid any dangerous division by pgen by returning a sane (but cheap) value.
            end if


        else !we have a double

            ! 2b. Select orbitals to excite from
            
            call choose_ij_mol(rng, sys, cdet%occ_list, i, j, ij_sym, ij_spin)

            !now we've chosen i and j. 
 
            ! We now need to select the orbitals to excite into which we do with weighting:
            ! p(ab|ij) = p(a|i) p(b|j) + p(a|j) p(b|i)
            
            ! We actually choose a|i then b|j, but since we could have also generated the excitation b from i and a from j, we need to include that prob too.

            ! Given i, construct the weights of all possible a
            if (sys%basis%basis_fns(i)%Ms < 0) then
                call create_weighted_excitation_list(sys, i, cdet%unocc_list_beta, sys%nvirt_beta, ia_weights, ia_weights_tot)
                ! Use the alias method to select i with the appropriate probability
                a_ind = select_weighted_value(rng, sys%nvirt_beta, ia_weights, ia_weights_tot)
                a = cdet%unocc_list_beta(a_ind) 
            else
                call create_weighted_excitation_list(sys, i, cdet%unocc_list_alpha, sys%nvirt_alpha, ia_weights, ia_weights_tot)
                ! Use the alias method to select i with the appropriate probability
                a_ind = select_weighted_value(rng, sys%nvirt_alpha, ia_weights, ia_weights_tot)
                a = cdet%unocc_list_alpha(a_ind) 
            endif 
            ! Given j construct the weights of all possible b
            if (sys%basis%basis_fns(j)%Ms < 0) then
                call create_weighted_excitation_list(sys, j, cdet%unocc_list_beta, sys%nvirt_beta, jb_weights, jb_weights_tot)
                ! Use the alias method to select j with the appropriate probability
                b_ind = select_weighted_value(rng, sys%nvirt_beta, jb_weights, jb_weights_tot)
                b = cdet%unocc_list_beta(b_ind) 
            else
                call create_weighted_excitation_list(sys, j, cdet%unocc_list_alpha, sys%nvirt_alpha, jb_weights, jb_weights_tot)
                ! Use the alias method to select a with the appropriate probability
                b_ind = select_weighted_value(rng, sys%nvirt_alpha, jb_weights, jb_weights_tot)
                b = cdet%unocc_list_alpha(b_ind) 
            endif 

            ! 3b. Probability of generating this excitation.

            ! Calculate p(ab|ij) = p(a|i) p(j|b) + p(b|i)p(a|j)
          
            if (ij_spin==0) then 
                !not possible to have chosen the reversed excitation
                pgen=ia_weights(a_ind)/ia_weights_tot*jb_weights(b_ind)/jb_weights_tot
            else !i and j have same spin, so could have been selected in the other order.
                pgen=       (ia_weights(a_ind)*jb_weights(b_ind) + ia_weights(b_ind)*jb_weights(a_ind) ) &
                        /   (ia_weights_tot*jb_weights_tot)
            endif
            pgen = (1.0_p - pattempt_single) * pgen *2.0_p/(sys%nel*(sys%nel-1)) ! pgen(ab)
            connection%nexcit = 2

            allowed_excitation = (a/=b)

            if (i<j) then
                connection%from_orb(1)=i
                connection%from_orb(2)=j
            else
                connection%from_orb(2)=i
                connection%from_orb(1)=j
            endif
            if (a<b) then
                connection%to_orb(1)=a
                connection%to_orb(2)=b 
            else
                connection%to_orb(2)=a
                connection%to_orb(1)=b 
            endif
!            write(6,*) "EXC",cdet%f,connection%from_orb, connection%to_orb,pgen
            if (allowed_excitation) then

                ! 4b. Parity of permutation required to line up determinants.
                ! NOTE: connection%from_orb and connection%to_orb *must* be ordered.
                call find_excitation_permutation2(sys%basis%excit_mask, cdet%f, connection)

                ! 5b. Find the connecting matrix element.
                hmatel = slater_condon2_mol(sys, connection%from_orb(1), connection%from_orb(2), &
                                                  connection%to_orb(1), connection%to_orb(2), connection%perm)
            else
                ! Carelessly selected ij with no possible excitations.  Such
                ! events are not worth the cost of renormalising the generation
                ! probabilities.
                ! Return a null excitation.
                hmatel = 0.0_p
                pgen = 1.0_p
            end if

        end if
    end subroutine gen_excit_mol_cauchy_schwarz_occ

    subroutine gen_excit_mol_cauchy_schwarz_virt(rng, sys, pattempt_single, cdet, pgen, connection, hmatel, allowed_excitation)

        ! Create a random excitation from cdet and calculate both the probability
        ! of selecting that excitation and the Hamiltonian matrix element.
        ! Weight the double excitations according the the Cauchy-Schwarz bound
        ! <ij|ab> <= Sqrt(<ia|ai><jb|bj>)

        ! In:
        !    sys: system object being studied.
        !    pattempt_single: Probability to attempt a single excitation.
        !    cdet: info on the current determinant (cdet) that we will gen
        !        from.
        !    parent_sign: sign of the population on the parent determinant (i.e.
        !        either a positive or negative integer).
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    pgen: probability of generating the excited determinant from cdet.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are gened.
        !    hmatel: < D | H | D' >, the Hamiltonian matrix element between a
        !        determinant and a connected determinant in molecular systems.
        !    allowed_excitation: false if a valid symmetry allowed excitation was not generated

        use determinants, only: det_info_t
        use excitations, only: excit_t
        use excitations, only: find_excitation_permutation1, find_excitation_permutation2
        use hamiltonian_molecular, only: slater_condon1_mol_excit, slater_condon2_mol
        use system, only: sys_t
        use excit_gen_mol, only: calc_pgen_single_mol_no_renorm, find_ia_mol 

        use dSFMT_interface, only: dSFMT_t, get_rand_close_open

        type(sys_t), intent(in) :: sys
        real(p), intent(in) :: pattempt_single
        type(det_info_t), intent(in) :: cdet
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: pgen, hmatel
        type(excit_t), intent(out) :: connection
        logical, intent(out) :: allowed_excitation

        integer ::  ab_spin

        real(p) :: ia_weights(max(sys%nalpha,sys%nbeta))
        real(p) :: jb_weights(max(sys%nalpha,sys%nbeta))
      
        real(p) :: ia_weights_tot 
        real(p) :: jb_weights_tot 
        integer :: ind, a, b, i, j, i_ind, j_ind


        ! 1. Select single or double.
        if (get_rand_close_open(rng) < pattempt_single) then


            ! 2a. Select orbital to excite from and orbital to excite into.
            call find_ia_mol(rng, sys, sys%read_in%pg_sym%gamma_sym, cdet%f, cdet%occ_list, connection%from_orb(1), &
                             connection%to_orb(1), allowed_excitation)
            connection%nexcit = 1

            if (allowed_excitation) then
                ! 3a. Probability of generating this excitation.
                pgen = pattempt_single*calc_pgen_single_mol_no_renorm(sys, connection%to_orb(1))

                ! 4a. Parity of permutation required to line up determinants.
                call find_excitation_permutation1(sys%basis%excit_mask, cdet%f, connection)

                ! 5a. Find the connecting matrix element.
                hmatel = slater_condon1_mol_excit(sys, cdet%occ_list, connection%from_orb(1), connection%to_orb(1), connection%perm)
            else
                ! Forbidden---connection%to_orb(1) is already occupied.
                hmatel = 0.0_p
                pgen = 1.0_p ! Avoid any dangerous division by pgen by returning a sane (but cheap) value.
            end if


        else !we have a double

            ! 2b. Select orbitals to excite to

                        
            ! sys%nvirt is the number of virtual orbitals
            ind = int(get_rand_close_open(rng)*sys%nvirt*(sys%nvirt-1)/2.0_p) + 1
            ! a,b initially refer to the indices in the lists of virtual spin-orbitals
            ! rather than the spin-orbitals.
            b = int(1.50_p + sqrt(2*ind-1.750_p))
            a = ind - ((b-1)*(b-2))/2

            ! Now to convert from virtual #a to orbital a
            if (a <= sys%nvirt_alpha) then
                a = cdet%unocc_list_alpha(a)
            else
                a = cdet%unocc_list_beta(a-sys%nvirt_alpha)
            endif
            ! Now to convert from virtual #b to orbital b
            if (b <= sys%nvirt_alpha) then
                b = cdet%unocc_list_alpha(b)
            else
                b = cdet%unocc_list_beta(b-sys%nvirt_alpha)
            endif
            ab_spin = sys%basis%basis_fns(a)%Ms + sys%basis%basis_fns(b)%Ms

            !now we've chosen a and b. 
 
            ! We now need to select the orbitals to excite into which we do with weighting:
            ! p(ij|ab) = p(i|a) p(j|b) + p(i|b) p(j|a)
            
            ! We actually choose i|a then j|b, but since we could have also generated the excitation b from i and a from j, we need to include that prob too.

            ! Given a, construct the weights of all possible i
            if (sys%basis%basis_fns(a)%Ms < 0) then
                call create_weighted_excitation_list(sys, a, cdet%occ_list_beta, sys%nbeta, ia_weights, ia_weights_tot)
                ! Use the alias method to select i with the appropriate probability
                i_ind = select_weighted_value(rng, sys%nbeta, ia_weights, ia_weights_tot)
                i = cdet%occ_list_beta(i_ind) 
            else
                call create_weighted_excitation_list(sys, a, cdet%occ_list_alpha, sys%nalpha, ia_weights, ia_weights_tot)
                ! Use the alias method to select i with the appropriate probability
                i_ind = select_weighted_value(rng, sys%nalpha, ia_weights, ia_weights_tot)
                i = cdet%occ_list_alpha(i_ind) 
            endif 
            ! Given j construct the weights of all possible b
            if (sys%basis%basis_fns(b)%Ms < 0) then
                call create_weighted_excitation_list(sys, b, cdet%occ_list_beta, sys%nbeta, jb_weights, jb_weights_tot)
                ! Use the alias method to select j with the appropriate probability
                j_ind = select_weighted_value(rng, sys%nbeta, jb_weights, jb_weights_tot)
                j = cdet%occ_list_beta(j_ind) 
            else
                call create_weighted_excitation_list(sys, b, cdet%occ_list_alpha, sys%nalpha, jb_weights, jb_weights_tot)
                ! Use the alias method to select a with the appropriate probability
                j_ind = select_weighted_value(rng, sys%nalpha, jb_weights, jb_weights_tot)
                j = cdet%occ_list_alpha(j_ind) 
            endif 

            ! 3b. Probability of generating this excitation.

            ! Calculate p(ab|ij) = p(a|i) p(j|b) + p(b|i)p(a|j)
          
            if (ab_spin==0) then 
                !not possible to have chosen the reversed excitation
                pgen=ia_weights(i_ind)/ia_weights_tot*jb_weights(j_ind)/jb_weights_tot
            else !i and j have same spin, so could have been selected in the other order.
                pgen=       (ia_weights(i_ind)*jb_weights(j_ind) + ia_weights(j_ind)*jb_weights(i_ind) ) &
                        /   (ia_weights_tot*jb_weights_tot)
            endif
            pgen = (1.0_p - pattempt_single) * pgen *2.0_p/(sys%nvirt*(sys%nvirt-1)) ! pgen(ab)
            connection%nexcit = 2

            allowed_excitation = (i/=j)

            if (i<j) then
                connection%from_orb(1)=i
                connection%from_orb(2)=j
            else
                connection%from_orb(2)=i
                connection%from_orb(1)=j
            endif
            if (a<b) then
                connection%to_orb(1)=a
                connection%to_orb(2)=b 
            else
                connection%to_orb(2)=a
                connection%to_orb(1)=b 
            endif
!            write(6,*) "EXC",cdet%f,connection%from_orb, connection%to_orb,pgen
            if (allowed_excitation) then

                ! 4b. Parity of permutation required to line up determinants.
                ! NOTE: connection%from_orb and connection%to_orb *must* be ordered.
                call find_excitation_permutation2(sys%basis%excit_mask, cdet%f, connection)

                ! 5b. Find the connecting matrix element.
                hmatel = slater_condon2_mol(sys, connection%from_orb(1), connection%from_orb(2), &
                                                  connection%to_orb(1), connection%to_orb(2), connection%perm)
            else
                ! Carelessly selected ij with no possible excitations.  Such
                ! events are not worth the cost of renormalising the generation
                ! probabilities.
                ! Return a null excitation.
                hmatel = 0.0_p
                pgen = 1.0_p
            end if

        end if
    end subroutine gen_excit_mol_cauchy_schwarz_virt
end module excit_gen_cauchy_schwarz
