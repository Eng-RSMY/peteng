"""
fractional flow formulation and solution of a Water injection process
for Corey-type oil and water relative permeabilities on a
Cartesian coordinate (not radial)

inputs [unit] \\(default):

   + muw [Pa.s] \\(1e-3)
   + muo [Pa.s] \\(2e-5)
   + ut [m/s] \\(1e-5)
   + phi [-] \\(0.2)
   + k [m^2] \\(1e-12)
   + swc [-] \\(0.1)
   + sor [-] \\(0.05)
   + kro0 [-] \\(0.9)
   + no [-] \\(1.8)
   + krw0 [-] \\(0.2)
   + nw [-] \\(4.2)
   + sw0 [-] \\(1.0)
   + sw_inj [-] \\(0.0)
   + L [m] \\(domain length = 1.0)
   + pv_inj [-] \\(injected pore volumes = 5)

Outputs:

   + xt_shock (x/t shock position)
   + sw_shock
   + xt_prf
   + sw_prf
   + t [s] \\time
   + p_inj [Pa] \\(injection pressure history)
   + R_oil [-] \\oil recovery factor

Usage:
   using Roots, Dierckx
   include("rel_perms.jl")

   + (xt_shock, sw_shock, xt_prf, sw_prf, t, p_inj, R_oil)=frac_flow_wf()
   + (xt_shock, sw_shock, xt_prf, sw_prf, t, p_inj, R_oil)=frac_flow_wf(muw, muo, ut, phi,
k, swc, sor, kro0, no, krw0, nw, sw0, sw_inj, L, pv_inj)
"""
function frac_flow_wf(;muw=1e-3, muo=2e-5, ut=1e-5, phi=0.2,
  k=1e-12, swc=0.1, sor=0.05, kro0=0.9, no=1.8, krw0=0.2,
  nw=4.2, sw0=0.0, sw_inj=1.0, L=1, pv_inj=5)
  # sws(sw::Real)=((sw>swc)*(sw<1-sor)*(sw-swc)/(1-sor-swc)+(sw>=1-sor)*1.0)
  # sws(sw::Array{Float64})=((sw.>swc).*(sw.<1-sor).*(sw-swc)/(1-sor-swc)+(sw.>=1-sor).*ones(size(sw)))
  # kro_new(sw)=((sw.>=swc).*kro0.*(1-sws(sw)).^no+(sw.<swc).*(1+(kro0-1)/swc*sw))
  # krw_new(sw)=((sw.<=1-sor).*krw0.*sws(sw).^nw+(sw.>1-sor).*(-(1-krw0)/sor.*(1.0-sw)+1.0))
  # dkrwdsw_new(sw)=(nw*krw0*(1/(1-sor-swc))*sws(sw).^(nw-1))
  # dkrodsw_new(sw)=((-kro0*no*(1-sws(sw)).^(no-1))/(-swc-sor+1))
  kro_new = sw -> kro(sw, kro0, sor, swc, no)
  krw_new = sw -> krw(sw, krw0, sor, swc, nw)
  dkrwdsw_new = sw -> dkrwdsw(sw, krw0, sor, swc, nw)
  dkrodsw_new = sw -> dkrodsw(sw, kro0, sor, swc, no)
  fw(sw)=((krw_new(sw)/muw)/(krw_new(sw)/muw+kro_new(sw)/muo))
  dfw(sw)=((dkrwdsw_new(sw)/muw*(krw_new(sw)/muw+kro_new(sw)/muo)-
    (dkrwdsw_new(sw)/muw+dkrodsw_new(sw)/muo)*krw_new(sw)/muw)/
    (kro_new(sw)/muo+krw_new(sw)/muw)^2)
  eps1=1e-3
  dfw_num(sw) = (fw(sw+eps1)-fw(sw-eps1))/(2*eps1)
  ftot(sw)=kro_new(sw)/muo+krw_new(sw)/muw

# solve the nl equation to find the shock front saturation
  sw_shock = 0
  try
      f_shock = sw->(dfw(sw)-(fw(sw)-fw(sw0))/(sw-sw0))
      if f_shock(swc+eps())*f_shock(1-sor-eps())>0
          sw_shock = fzero(f_shock, (swc+1-sor)/2)
      else
          sw_shock = fzero(f_shock, [swc+eps(),1-sor-eps()])
      end
  catch
      println("swc=$swc, sor=$sor, kro0=$kro0, no=$no, krw0=$krw0, nw=$nw,")
      error("Could not find the shock front saturation!")
  end
  # sw_shock1 = sciopt.newton(f_shock, (swc+1-sor)/2.0) # just a test!
  # sw_shock = sw_shock1[1]

  s=collect(linspace(0.0,1.0,100))
  s1 = collect(linspace(sw_inj, sw_shock, 1000))
  xt_s1 = ut/phi*dfw.(s1)
  xt_s = ut/phi*dfw.(s)
  xt_shock = ut/phi*dfw(sw_shock)
  xt_prf=[xt_s1; xt_shock; xt_shock+eps(); 2*xt_shock]
  sw_prf=[s1; sw_shock; sw0; sw0]
  # println(xt_prf)
  # print(sw_shock)
# Go through the data first
  i=1
  while(true)
    if i==length(xt_prf)
      break
    elseif xt_prf[i]>=xt_prf[i+1]
      deleteat!(xt_prf, i+1)
      deleteat!(sw_prf, i+1)
    else
      i+=1
    end
  end
  # xt_prf_slim = unique(xt_prf)
  # sw_prf = sw_prf[indexin(xt_prf_slim, xt_prf)]
  # xt_prf = xt_prf_slim

# find the injection pressure history
  x = collect(linspace(0,L,1000))
  # sw_int = Spline1D([xt_prf; L/eps()], [sw_prf; sw0], k=1)
  sw_int = Spline1D(xt_prf, sw_prf, k=1)
  t_inj=pv_inj*phi*L/ut
  t = collect(linspace(0.0,t_inj, 200)) # [s] time
  p_inj = zeros(length(t))
  R_oil= zeros(length(t))
  p_inj[1]=trapz(x, ut./(k*(kro_new.(sw0*ones(size(x)))/muo+krw_new.(sw0*ones(size(x)))/muw)))
  for i in 2:length(t)
      xt = x/t[i]
      p_inj[i] = trapz(x, ut./(k*(kro_new.(sw_int(xt))/muo+krw_new.(sw_int(xt))/muw)))
      R_oil[i]=1.0-trapz(x/L, 1.0-sw_int(xt))/(1-sw0)
  end

# Return the results
    return xt_shock, sw_shock, xt_prf, sw_prf, t, p_inj, R_oil
end

function trapz(x,y)
# copied from https://github.com/hwborchers/NumericalMath.jl/blob/master/src/integrate.jl
  n=length(x)
  if (length(y) != n)
    error("Vectors 'x', 'y' must be of same length")
  end
  r=0
  for i in 2:n
    r+=(x[i] - x[i-1])*(y[i] + y[i-1])
  end
  return r/2.0
end
