using ClimaCore
using ClimaCore: Operators, Spaces, Fields, Geometry
using UnPack
using LinearAlgebra
using DocStringExtensions
using NVTX
using Colors
using DiffEqBase

import OrdinaryDiffEq as ODE
import ClimaTimeSteppers as CTS

if !("." in LOAD_PATH)
    push!(LOAD_PATH, ".")
end
using ClimaLSM
using ClimaLSM.Soil
using ClimaLSM.Domains: HybridBox, SphericalShell, Column

include("../../SharedUtilities/boundary_conditions.jl")
include("../rre.jl")

FT = Float64
divf2c_op = Operators.DivergenceF2C(
    top = Operators.SetValue(FT(0.0)),
    bottom = Operators.SetValue(FT(0.0)),
)
divf2c_stencil = Operators.Operator2Stencil(divf2c_op)
gradc2f_op = Operators.GradientC2F()
gradc2f_stencil = Operators.Operator2Stencil(gradc2f_op)
interpc2f_op = Operators.InterpolateC2F()
interpc2f_stencil = Operators.Operator2Stencil(interpc2f_op)
compose = Operators.ComposeStencils()
to_scalar_coefs(vector_coefs) = map(vector_coef -> vector_coef.u₃, vector_coefs)


"""
    TridiagonalW{R, J, W, T}

Jacobian representation used for the modified Picard method.
"""
struct TridiagonalW{R, J, W, T}
    # reference to dtγ, which is specified by the ODE solver
    dtγ_ref::R
    ∂ϑₜ∂ϑ::J
    W_column_arrays::W

    # caches used to evaluate ldiv!
    temp1::T
    temp2::T

    # whether this struct is used to compute Wfact_t or Wfact
    transform::Bool
end

# TODO add IdentityW struct

"""
    TridiagonalW(Y, transform)

Constructor for the TridiagonalW struct, used for modified Picard.
Uses the space information from Y to allocate space for the
necessary fields.
"""
function TridiagonalW(Y, transform)
    FT = eltype(Y.soil.ϑ_l)
    space = axes(Y.soil.ϑ_l)
    N = Spaces.nlevels(space)

    tridiag_type = Operators.StencilCoefs{-1, 1, NTuple{3, FT}}
    J = Fields.Field(tridiag_type, space)
    J_column_array = [
        LinearAlgebra.Tridiagonal(
            Array{FT}(undef, N - 1),
            Array{FT}(undef, N),
            Array{FT}(undef, N - 1),
        ) for _ in 1:Threads.nthreads()
    ]
    dtγ_ref = Ref(zero(FT))

    return TridiagonalW(
        dtγ_ref,
        J,
        J_column_array,
        similar(Y),
        similar(Y),
        transform,
    )
end

# We only use Wfact, but the implicit/IMEX solvers require us to pass
# jac_prototype, then call similar(jac_prototype) to obtain J and Wfact. Here
# is a temporary workaround to avoid unnecessary allocations.
Base.similar(w::TridiagonalW) = w

"""
    Wfact!(W::TridiagonalW, Y, p, dtγ, t)

Compute the entries of the Jacobian and overwrite W with them.
See overleaf for Jacobian derivation: https://www.overleaf.com/project/63be02f455f84a77642ef485
"""
# TODO add Wfact! method for identity input
function Wfact!(W::TridiagonalW, Y, p, dtγ, t)
    (; dtγ_ref, ∂ϑₜ∂ϑ) = W
    dtγ_ref[] = dtγ

    if axes(p.soil.K) isa Spaces.CenterFiniteDifferenceSpace
        face_space = Spaces.FaceFiniteDifferenceSpace(axes(Y.soil.ϑ_l))
    elseif axes(p.soil.K) isa Spaces.CenterExtrudedFiniteDifferenceSpace
        face_space = Spaces.FaceExtrudedFiniteDifferenceSpace(axes(Y.soil.ϑ_l))
    else
        error("invalid model space")
    end

    # TODO create field of ones on faces once and store in W to reduce allocations
    ones_face_space = ones(face_space)
    @. ∂ϑₜ∂ϑ = compose(
        divf2c_stencil(Geometry.WVector(ones_face_space)),
        (
            interpc2f_op(p.soil.K) * to_scalar_coefs(
                gradc2f_stencil(
                    dψdθ(Y.soil.ϑ_l, ν, θ_r, vg_α, vg_n, vg_m, S_s),
                ),
            )
        ),
    )
end

"""
    Wfact!(W::UniformScaling{T}, x...) where T

In the case of the Picard method, where W = -I, we do not want to update
W when Wfact! is called.
"""
function Wfact!(W::UniformScaling{T}, x...) where {T}
    nothing
end

# Copied from https://github.com/CliMA/ClimaLSM.jl/blob/f41c497a12f91725ff23a9cd7ba8d563285f3bd8/examples/richards_implicit.jl#L152
# Checked against soiltest https://github.com/CliMA/ClimaLSM.jl/blob/e7eaf2e6fffaf64b2d824e9c5755d2f60fa17a69/test/Soil/soiltest.jl#L459
function dψdθ(θ, ν, θ_r, vg_α, vg_n, vg_m, S_s)
    S = (θ - θ_r) / (ν - θ_r)
    if S < 1.0
        return 1.0 / (vg_α * vg_m * vg_n) / (ν - θ_r) *
               (S^(-1 / vg_m) - 1)^(1 / vg_n - 1) *
               S^(-1 / vg_m - 1)
    else
        return 1.0 / S_s
    end
end

linsolve!(::Type{Val{:init}}, f, u0; kwargs...) = _linsolve!
_linsolve!(x, A, b, update_matrix = false; kwargs...) =
    LinearAlgebra.ldiv!(x, A, b)

# Function required by Krylov.jl (x and b can be AbstractVectors)
# See https://github.com/JuliaSmoothOptimizers/Krylov.jl/issues/605 for a
# related issue that requires the same workaround.
function LinearAlgebra.ldiv!(x, A::TridiagonalW, b)
    A.temp1 .= b
    LinearAlgebra.ldiv!(A.temp2, A, A.temp1)
    x .= A.temp2
end

function LinearAlgebra.ldiv!(
    x::Fields.FieldVector,
    A::TridiagonalW,
    b::Fields.FieldVector,
)
    (; dtγ_ref, ∂ϑₜ∂ϑ, W_column_arrays, transform) = A
    dtγ = dtγ_ref[]

    NVTX.@range "linsolve" color = Colors.colorant"lime" begin
        # Compute Schur complement
        Fields.bycolumn(axes(x.soil.ϑ_l)) do colidx
            _ldiv_serial!(
                x.soil.ϑ_l[colidx],
                b.soil.ϑ_l[colidx],
                dtγ,
                transform,
                ∂ϑₜ∂ϑ[colidx],
                W_column_arrays[Threads.threadid()], # can / should this be colidx?
            )
        end
    end
end

function _ldiv_serial!(
    x_column,
    b_column,
    dtγ,
    transform,
    ∂ϑₜ∂ϑ_column,
    W_column_array,
)
    x_column .= b_column

    x_column_view = parent(x_column)

    @views W_column_array.dl .= dtγ .* parent(∂ϑₜ∂ϑ_column.coefs.:1)[2:end]
    W_column_array.d .= -1 .+ dtγ .* parent(∂ϑₜ∂ϑ_column.coefs.:2)
    @views W_column_array.du .=
        dtγ .* parent(∂ϑₜ∂ϑ_column.coefs.:3)[1:(end - 1)]

    thomas_algorithm!(W_column_array, x_column_view)

    # Apply transform (if needed)
    if transform
        x_column .*= dtγ
    end
    return nothing
end

"""
    thomas_algorithm!(A, b)

Thomas algorithm for solving a linear system A x = b,
where A is a tri-diagonal matrix.
A and b are overwritten, solution is written to b.
Pass this as linsolve to ODEFunction.

Copied directly from https://github.com/CliMA/ClimaAtmos.jl/blob/99e44f4cd97307c4e8f760a16e7958d66d67e6e8/src/tendencies/implicit/schur_complement_W.jl#L410
"""
function thomas_algorithm!(A, b)
    nrows = size(A, 1)
    # first row
    @inbounds A[1, 2] /= A[1, 1]
    @inbounds b[1] /= A[1, 1]
    # interior rows
    for row in 2:(nrows - 1)
        @inbounds fac = A[row, row] - (A[row, row - 1] * A[row - 1, row])
        @inbounds A[row, row + 1] /= fac
        @inbounds b[row] = (b[row] - A[row, row - 1] * b[row - 1]) / fac
    end
    # last row
    @inbounds fac = A[nrows, nrows] - A[nrows - 1, nrows] * A[nrows, nrows - 1]
    @inbounds b[nrows] = (b[nrows] - A[nrows, nrows - 1] * b[nrows - 1]) / fac
    # back substitution
    for row in (nrows - 1):-1:1
        @inbounds b[row] -= b[row + 1] * A[row, row + 1]
    end
    return nothing
end

"""
    make_implicit_tendency(model::Soil.RichardsModel)

Construct the tendency function for the implicit terms of the RHS.
Adapted from https://github.com/CliMA/ClimaLSM.jl/blob/f41c497a12f91725ff23a9cd7ba8d563285f3bd8/examples/richards_implicit.jl#L173
"""
# compared math to make_rhs https://github.com/CliMA/ClimaLSM.jl/blob/main/src/Soil/rre.jl#L88
function make_implicit_tendency(model::Soil.RichardsModel)
    function implicit_tendency!(dY, Y, p, t)
        @unpack ν, vg_α, vg_n, vg_m, K_sat, S_s, θ_r = model.parameters
        (; K, ψ) = p.soil

        @. K = hydraulic_conductivity(
            K_sat,
            vg_m,
            effective_saturation(ν, Y.soil.ϑ_l, θ_r),
        )
        @. ψ = pressure_head(vg_α, vg_n, vg_m, θ_r, Y.soil.ϑ_l, ν, S_s)

        z = ClimaCore.Fields.coordinate_field(model.domain.space).z
        Δz_top, Δz_bottom = get_Δz(z)

        top_flux_bc = ClimaLSM.boundary_flux(
            model.boundary_conditions.water.top,
            ClimaLSM.TopBoundary(),
            Δz_top,
            p,
            t,
            model.parameters,
        )
        bot_flux_bc = ClimaLSM.boundary_flux(
            model.boundary_conditions.water.bottom,
            ClimaLSM.BottomBoundary(),
            Δz_bottom,
            p,
            t,
            model.parameters,
        )

        interpc2f = Operators.InterpolateC2F()
        gradc2f_water = Operators.GradientC2F()
        divf2c_water = Operators.DivergenceF2C(
            top = Operators.SetValue(Geometry.WVector.(top_flux_bc)),
            bottom = Operators.SetValue(Geometry.WVector.(bot_flux_bc)),
        )

        @. dY.soil.ϑ_l = -(divf2c_water(-interpc2f(K) * gradc2f_water(ψ + z)))
    end
    return implicit_tendency!
end

"""
    make_explicit_tendency(model::Soil.RichardsModel)

Construct the tendency function for the explicit terms of the RHS.
Adapted from https://github.com/CliMA/ClimaLSM.jl/blob/f41c497a12f91725ff23a9cd7ba8d563285f3bd8/examples/richards_implicit.jl#L204
"""
# compared math to make_rhs https://github.com/CliMA/ClimaLSM.jl/blob/main/src/Soil/rre.jl#L88
function make_explicit_tendency(model::Soil.RichardsModel)
    function explicit_tendency!(dY, Y, p, t)
        @unpack ν, vg_α, vg_n, vg_m, K_sat, S_s, θ_r = model.parameters

        @. p.soil.K = hydraulic_conductivity(
            K_sat,
            vg_m,
            effective_saturation(ν, Y.soil.ϑ_l, θ_r),
        )
        @. p.soil.ψ = pressure_head(vg_α, vg_n, vg_m, θ_r, Y.soil.ϑ_l, ν, S_s)
        hdiv = Operators.WeakDivergence()
        hgrad = Operators.Gradient()

        z = ClimaCore.Fields.coordinate_field(model.domain.space).z
        @. dY.soil.ϑ_l += -hdiv(-p.soil.K * hgrad(p.soil.ψ + z))
        Spaces.weighted_dss!(dY.soil.ϑ_l)
    end
    return explicit_tendency!
end

is_imex_CTS_algo(::CTS.IMEXAlgorithm) = true
is_imex_CTS_algo(::DiffEqBase.AbstractODEAlgorithm) = false

is_implicit(::ODE.OrdinaryDiffEqImplicitAlgorithm) = true
is_implicit(::ODE.OrdinaryDiffEqAdaptiveImplicitAlgorithm) = true
is_implicit(ode_algo) = is_imex_CTS_algo(ode_algo)

is_rosenbrock(::ODE.Rosenbrock23) = true
is_rosenbrock(::ODE.Rosenbrock32) = true
is_rosenbrock(::DiffEqBase.AbstractODEAlgorithm) = false
use_transform(ode_algo) =
    !(is_imex_CTS_algo(ode_algo) || is_rosenbrock(ode_algo))

# Setup largely taken from ClimaLSM.jl/test/Soil/soiltest.jl
is_true_picard = false

ν = FT(0.495)
K_sat = FT(0.0443 / 3600 / 100) # m/s
S_s = FT(1e-3) #inverse meters
vg_n = FT(2.0)
vg_α = FT(2.6) # inverse meters
vg_m = FT(1) - FT(1) / vg_n
θ_r = FT(0)
zmax = FT(0)
zmin = FT(-10)
nelems = 50

soil_domain = HybridBox(;
    zlim = (-10.0, 0.0),
    xlim = (0.0, 100.0),
    ylim = (0.0, 100.0),
    nelements = (10, 10, 10),
    npolynomial = 1,
    periodic = (true, true),
)
top_flux_bc = FluxBC((p, t) -> eltype(t)(0.0))
bot_flux_bc = FluxBC((p, t) -> eltype(t)(0.0))
sources = ()
boundary_fluxes = (; water = (top = top_flux_bc, bottom = bot_flux_bc))
params = Soil.RichardsParameters{FT}(ν, vg_α, vg_n, vg_m, K_sat, S_s, θ_r)

soil = Soil.RichardsModel{FT}(;
    parameters = params,
    domain = soil_domain,
    boundary_conditions = boundary_fluxes,
    sources = sources,
)

Y, p, coords = initialize(soil)

# specify ICs
function init_soil!(Ysoil, z, params)
    function hydrostatic_profile(
        z::FT,
        params::Soil.RichardsParameters{FT},
    ) where {FT}
        @unpack ν, vg_α, vg_n, vg_m, θ_r = params
        #unsaturated zone only, assumes water table starts at z_∇
        z_∇ = FT(-10)# matches zmin
        S = FT((FT(1) + (vg_α * (z - z_∇))^vg_n)^(-vg_m))
        ϑ_l = S * (ν - θ_r) + θ_r
        return FT(ϑ_l)
    end
    Ysoil.soil.ϑ_l .= hydrostatic_profile.(z, Ref(params))
end

init_soil!(Y, coords.z, soil.parameters)

t_start = 0.0
t_end = 100.0
dt = 10.0

update_aux! = make_update_aux(soil)
update_aux!(p, Y, t_start)

alg_kwargs = (; linsolve = linsolve!)

ode_algo = ODE.Rosenbrock23(; alg_kwargs...)
transform = use_transform(ode_algo)

W = is_true_picard ? -I : TridiagonalW(Y, transform)

jac_kwargs = if use_transform(ode_algo)
    (; jac_prototype = W, Wfact_t = Wfact!)
else
    (; jac_prototype = W, Wfact = Wfact!)
end

implicit_tendency! = make_implicit_tendency(soil)
explicit_tendency! = make_explicit_tendency(soil)

problem = SplitODEProblem(
    ODEFunction(
        implicit_tendency!;
        jac_kwargs...,
        tgrad = (∂Y∂t, Y, p, t) -> (∂Y∂t .= FT(0)),
    ),
    explicit_tendency!,
    Y,
    (t_start, t_end),
    p,
)
integrator = init(
    problem,
    ode_algo;
    dt = dt,
    adaptive = false,
    progress = true,
    progress_steps = 1,
)

sol = @timev ODE.solve!(integrator)
