! to dos:
! multicurve

subroutine lgm_swaption_engine(n_times, times, modpar, n_expiries, &
     expiries, callput, n_floats, &
     float_startidxes, float_mults, float_spreads, float_t1s, float_t2s, float_tps, &
     fix_startidxes, n_fixs, fix_cpn, fix_tps, res, &
     integration_points, stddevs)

  implicit none

  ! constants

  double precision, parameter:: M_SQRT2 = 1.41421356237309504880
  double precision, parameter:: M_SQRTPI = 1.77245385090551602792981
  double precision, parameter:: M_SQRT1_2 = 0.7071067811865475244008443621048490392848359376887

  ! interface

  integer:: n_times
  double precision, dimension(0:n_times-1):: times

  ! concatenated model parameter array: H, zeta, discounts
  double precision, dimension(0:3*n_times-1):: modpar

  integer:: n_expiries, expiries, callput
  integer, dimension(0:n_expiries):: fix_startidxes, float_startidxes
  integer:: n_floats, n_fixs
  double precision, dimension(0:n_floats-1):: float_mults, float_spreads
  integer, dimension(0:n_floats-1):: float_t1s, float_t2s
  integer, dimension(0:n_floats-1):: float_tps
  double precision:: fix_cpn
  integer, dimension(0:n_fixs-1):: fix_tps

  integer:: integration_points
  double precision:: stddevs

  double precision:: res

  ! additional variables

  integer:: idx, expiry0idx, expiry1idx, yidx0, yidx1
  integer:: i, k, l
  double precision, dimension(0:2*integration_points,2):: npv
  double precision, dimension(0:2*integration_points):: val, z
  double precision:: sigma_t0_t1, sigma_0_t0, sigma_0_t1
  double precision:: center, yidx, a, b, coeff1, coeff2, da, x0, x1, price
  double precision:: weight0, weight1, floatlegnpv, fixlegnpv
  double precision:: discount, forward, exercisevalue

  integer:: swapflag

  ! start of the calculation

  swapflag = 0

  !$openad INDEPENDENT(activevars)

  expiry0idx = expiries(n_expiries-1)
  expiry1idx = 0

  do k = 0, 2*integration_points, 1
     z(k) = -stddevs + dble(k)/dble(2*integration_points+1) * 2.0d0 * stddevs
     write (*,*) 'z(', k, ')=', z(k)
  end do


  ! loop over expiry dates
  do idx = expiries(n_expiries-1), expiries(0)-1, -1

     if (idx == expiries(0)-1) then
        expiry0idx = 0
     else
        expiry0idx = idx
     endif

     sigma_0_t0 = sqrt(modpar(n_times+expiry0idx))
     if (expiry1idx /= 0) then
        sigma_0_t1 = sqrt(modpar(n_times+expiry1idx))
        sigma_t0_t1 = sqrt(modpar(n_times+expiry1idx)-modpar(n_times+expiry0idx))
     end if

     ! loop over integration points
     do k = 0, 2*integration_points, 1

        ! roll back
        if (expiry1idx /= 0) then

           if (expiry0idx == 0) then
              center = 0.0d0
           else
              center = z(k)
           endif
           do i=0, 2*integration_points, 1
              yidx =  ( (center*sigma_0_t0 + &
                   dble(i-integration_points) * stddevs * sigma_t0_t1) / sigma_0_t1 + stddevs ) &
                   / (2*stddevs)
              yidx0 = floor(yidx)
              yidx1 = yidx0+1
              weight0 = yidx1 - yidx
              weight1 = yidx - yidx0
              val(i) = weight0 * npv(max(yidx0,0),1-swapflag) + &
                   weight1 * npv(min(yidx1,2*integration_points),1-swapflag)
           end do

           price = 0.0d0
           do i=0, 2*integration_points-1, 1
              a = (val(i+1)-val(i))/(z(i+1)-z(i))
              b = (val(i)*z(i+1)-val(i+1)*z(i)) / (z(i+1)-z(i))
              coeff1 = a
              coeff2 = - a * z(i) + b
              da = M_SQRT2 * coeff1
              x0 = z(i) * M_SQRT1_2
              x1 = z(i+1) * M_SQRT1_2
              price = price + 0.5d0 * coeff2 * erf(x1) - &
                   1.0d0 / (4.0d0 * M_SQRTPI) * exp(-x1 * x1) * &
                   (2.0d0 * da) - &
                   0.5d0 * coeff2 * erf(x0) - &
                   1.0d0 / (4.0d0 * M_SQRTPI) * exp(-x0 * x0) * &
                   (2.0d0 * da)
           end do

           npv(k,swapflag) = price

        end if

        ! payoff generation

        if(expiry0Idx > 0) then
           floatlegnpv = 0.0d0
           do l = float_startidxes(k), n_floats, 1
              forward = modpar(2*n_times+float_t2s(l)) * &
                   exp(-modpar(float_t2s(l))*z(k)*sigma_0_t0- &
                   0.5*modpar(float_t2s(l))*modpar(float_t2s(l))*modpar(n_times+float_t2s(l))) / &
                   (modpar(2*n_times+float_t1s(l))  * &
                   exp(-modpar(float_t1s(l))*z(k)*sigma_0_t0- &
                   0.5*modpar(float_t1s(l))*modpar(float_t1s(l))*modpar(n_times+float_t1s(l)))) &
                   - 1.0d0
              discount =  modpar(2*n_times+float_tps(l)) * &
                   exp(-modpar(float_tps(l))*z(k)*sigma_0_t0- &
                   0.5*modpar(float_tps(l))*modpar(float_tps(l))*modpar(n_times+float_tps(l)))
              floatlegnpv = floatlegnpv + float_mults(l) * ( float_spreads(l) + forward) * discount
           end do
           fixlegnpv = 0.0d0
           do l = fix_startidxes(k), n_fixs, 1
              discount = modpar(2*n_times+float_tps(l)) * &
                   exp(-modpar(fix_tps(l))*z(k)*sigma_0_t0- &
                   0.5*modpar(fix_tps(l))*modpar(fix_tps(l))*modpar(n_times+fix_tps(l)))
              fixlegnpv = fixlegnpv + fix_cpn(l) * discount
           end do
        end if

        exercisevalue = callput * (floatlegnpv - fixlegnpv)

        npv(k,swapflag) = max(npv(k,swapflag),exercisevalue)

     end do ! loop integration points

     swapflag = 1-swapflag

  end do ! loop expiry dates

  res = npv(0,1-swapflag)

  !$openad DEPENDENT(res)

end subroutine lgm_swaption_engine
