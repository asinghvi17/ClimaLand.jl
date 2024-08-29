using Test
import ClimaComms
@static pkgversion(ClimaComms) >= v"0.6" && ClimaComms.@import_required_backends
using ClimaCore
import ClimaParams as CP
using Thermodynamics
using ClimaLand
using ClimaLand.Soil
import ClimaLand
import ClimaLand.Parameters as LP
using Dates


for FT in (Float32, Float64)
    @testset "Surface fluxes and radiation for soil, FT = $FT" begin
        earth_param_set = LP.LandParameters(FT)

        soil_domains = [
            ClimaLand.Domains.Column(;
                zlim = FT.((-100.0, 0.0)),
                nelements = 10,
            ),
            ClimaLand.Domains.HybridBox(;
                xlim = FT.((-1.0, 0.0)),
                ylim = FT.((-1.0, 0.0)),
                zlim = FT.((-100.0, 0.0)),
                nelements = (2, 2, 10),
                npolynomial = 1,
                periodic = (true, true),
            ),
        ]
        ν = FT(0.495)
        K_sat = FT(0.0443 / 3600 / 100) # m/s
        S_s = FT(1e-3) #inverse meters
        vg_n = FT(2.0)
        vg_α = FT(2.6) # inverse meters
        vg_m = FT(1) - FT(1) / vg_n
        hcm = vanGenuchten{FT}(; α = vg_α, n = vg_n)
        θ_r = FT(0.1)
        S_c = hcm.S_c
        @test Soil.dry_soil_layer_thickness(FT(1), S_c, FT(1)) == FT(0)
        @test Soil.dry_soil_layer_thickness(FT(0), S_c, FT(1)) == FT(1)

        ν_ss_om = FT(0.0)
        ν_ss_quartz = FT(1.0)
        ν_ss_gravel = FT(0.0)
        emissivity = FT(0.99)
        PAR_albedo = FT(0.2)
        NIR_albedo = FT(0.4)
        z_0m = FT(0.001)
        z_0b = z_0m
        # Radiation
        ref_time = DateTime(2005)
        SW_d = (t) -> 500
        LW_d = (t) -> 5.67e-8 * 280.0^4.0
        radiation = PrescribedRadiativeFluxes(
            FT,
            TimeVaryingInput(SW_d),
            TimeVaryingInput(LW_d),
            ref_time,
        )
        # Atmos
        precip = (t) -> 1e-8
        precip_snow = (t) -> 0
        T_atmos = (t) -> 285
        u_atmos = (t) -> 3
        q_atmos = (t) -> 0.005
        h_atmos = FT(3)
        P_atmos = (t) -> 101325
        atmos = PrescribedAtmosphere(
            TimeVaryingInput(precip),
            TimeVaryingInput(precip_snow),
            TimeVaryingInput(T_atmos),
            TimeVaryingInput(u_atmos),
            TimeVaryingInput(q_atmos),
            TimeVaryingInput(P_atmos),
            ref_time,
            h_atmos,
            earth_param_set,
        )
        @test atmos.gustiness == FT(1)
        top_bc = ClimaLand.Soil.AtmosDrivenFluxBC(atmos, radiation)
        zero_water_flux = WaterFluxBC((p, t) -> 0.0)
        zero_heat_flux = HeatFluxBC((p, t) -> 0.0)
        boundary_fluxes = (;
            top = top_bc,
            bottom = WaterHeatBC(;
                water = zero_water_flux,
                heat = zero_heat_flux,
            ),
        )
        params = ClimaLand.Soil.EnergyHydrologyParameters(
            FT;
            ν,
            ν_ss_om,
            ν_ss_quartz,
            ν_ss_gravel,
            hydrology_cm = hcm,
            K_sat,
            S_s,
            θ_r,
            PAR_albedo,
            NIR_albedo,
            emissivity,
            z_0m,
            z_0b,
        )

        for domain in soil_domains
            model = Soil.EnergyHydrology{FT}(;
                parameters = params,
                domain = domain,
                boundary_conditions = boundary_fluxes,
                sources = (),
            )
            drivers = ClimaLand.get_drivers(model)
            @test drivers == (atmos, radiation)
            Y, p, coords = initialize(model)
            Δz_top = model.domain.fields.Δz_top
            @test propertynames(p.drivers) == (
                :P_liq,
                :P_snow,
                :T,
                :P,
                :u,
                :q,
                :c_co2,
                :thermal_state,
                :SW_d,
                :LW_d,
                :θs,
            )
            @test propertynames(p.soil.turbulent_fluxes) ==
                  (:lhf, :shf, :vapor_flux, :r_ae)
            @test propertynames(p.soil) == (
                :K,
                :ψ,
                :θ_l,
                :T,
                :κ,
                :turbulent_fluxes,
                :ice_frac,
                :R_n,
                :top_bc,
                :sfc_scratch,
                :infiltration,
                :bottom_bc,
            )
            function init_soil!(Y, z, params)
                ν = params.ν
                FT = eltype(ν)
                Y.soil.ϑ_l .= ν / 2
                Y.soil.θ_i .= 0
                T = FT(280)
                ρc_s = Soil.volumetric_heat_capacity(
                    ν / 2,
                    FT(0),
                    params.ρc_ds,
                    params.earth_param_set,
                )
                Y.soil.ρe_int =
                    Soil.volumetric_internal_energy.(
                        FT(0),
                        ρc_s,
                        T,
                        params.earth_param_set,
                    )
            end

            t = Float64(0)
            init_soil!(Y, coords.subsurface.z, model.parameters)
            set_initial_cache! = make_set_initial_cache(model)
            set_initial_cache!(p, Y, t)
            space = axes(p.drivers.P_liq)
            @test p.drivers.P_liq == zeros(space) .+ FT(1e-8)
            @test p.drivers.P_snow == zeros(space) .+ FT(0)
            @test p.drivers.T == zeros(space) .+ FT(285)
            @test p.drivers.u == zeros(space) .+ FT(3)
            @test p.drivers.q == zeros(space) .+ FT(0.005)
            @test p.drivers.P == zeros(space) .+ FT(101325)
            @test p.drivers.LW_d == zeros(space) .+ FT(5.67e-8 * 280.0^4.0)
            @test p.drivers.SW_d == zeros(space) .+ FT(500)
            face_space = ClimaLand.Domains.obtain_face_space(
                model.domain.space.subsurface,
            )
            N = ClimaCore.Spaces.nlevels(face_space)
            surface_space = model.domain.space.surface
            z_sfc = ClimaCore.Fields.Field(
                ClimaCore.Fields.field_values(
                    ClimaCore.Fields.level(
                        ClimaCore.Fields.coordinate_field(face_space).z,
                        ClimaCore.Utilities.PlusHalf(N - 1),
                    ),
                ),
                surface_space,
            )
            T_sfc = ClimaCore.Fields.zeros(surface_space) .+ FT(280.0)
            @test ClimaLand.surface_emissivity(model, Y, p) == emissivity
            @test ClimaLand.surface_evaporative_scaling(model, Y, p) == FT(1)
            @test ClimaLand.surface_height(model, Y, p) == z_sfc
            @test ClimaLand.surface_albedo(model, Y, p) ==
                  PAR_albedo / 2 + NIR_albedo / 2
            @test ClimaLand.surface_temperature(model, Y, p, t) == T_sfc

            thermo_params =
                LP.thermodynamic_parameters(model.parameters.earth_param_set)
            ts_in =
                Thermodynamics.PhaseEquil_pTq.(
                    thermo_params,
                    p.drivers.P,
                    p.drivers.T,
                    p.drivers.q,
                )
            ρ_sfc = compute_ρ_sfc.(thermo_params, ts_in, T_sfc)
            @test ClimaLand.surface_air_density(
                model.boundary_conditions.top.atmos,
                model,
                Y,
                p,
                t,
                T_sfc,
            ) == ρ_sfc

            q_sat =
                Thermodynamics.q_vap_saturation_generic.(
                    Ref(thermo_params),
                    T_sfc,
                    ρ_sfc,
                    Ref(Thermodynamics.Liquid()),
                )
            g = LP.grav(model.parameters.earth_param_set)
            M_w = LP.molar_mass_water(model.parameters.earth_param_set)
            R = LP.gas_constant(model.parameters.earth_param_set)
            ψ_sfc = p.soil.sfc_scratch
            ClimaLand.Domains.linear_interpolation_to_surface!(
                ψ_sfc,
                p.soil.ψ,
                coords.subsurface.z,
                Δz_top,
            )
            q_sfc = @. (q_sat * exp(g * ψ_sfc * M_w / (R * T_sfc)))
            @test ClimaLand.surface_specific_humidity(
                model,
                Y,
                p,
                T_sfc,
                ρ_sfc,
            ) == q_sfc

            conditions = ClimaLand.turbulent_fluxes(
                model.boundary_conditions.top.atmos,
                model,
                Y,
                p,
                t,
            )
            R_n = ClimaLand.net_radiation(
                model.boundary_conditions.top.radiation,
                model,
                Y,
                p,
                t,
            )
            @test R_n == p.soil.R_n
            @test conditions == p.soil.turbulent_fluxes

            ClimaLand.Soil.soil_boundary_fluxes!(
                top_bc,
                ClimaLand.TopBoundary(),
                model,
                nothing,
                Y,
                p,
                t,
            )
            computed_water_flux = p.soil.top_bc.water
            computed_energy_flux = p.soil.top_bc.heat
            (; ν, θ_r, d_ds) = model.parameters
            _D_vapor = FT(LP.D_vapor(model.parameters.earth_param_set))
            S_l_sfc = p.soil.sfc_scratch
            ClimaLand.Domains.linear_interpolation_to_surface!(
                S_l_sfc,
                Soil.effective_saturation.(ν, Y.soil.ϑ_l, θ_r),
                coords.subsurface.z,
                Δz_top,
            )
            τ_a = ClimaLand.Domains.top_center_to_surface(
                @. (ν - p.soil.θ_l - Y.soil.θ_i)^(FT(5 / 2)) / ν
            )
            f_ice = ClimaLand.Domains.top_center_to_surface(
                @. effective_saturation(ν, Y.soil.θ_i, θ_r) / (
                    effective_saturation(ν, Y.soil.θ_i, θ_r) +
                    effective_saturation(ν, Y.soil.ϑ_l, θ_r)
                )
            )
            dsl = Soil.dry_soil_layer_thickness.(S_l_sfc, S_c, d_ds)
            r_soil = @. dsl / (_D_vapor * τ_a) # [s\m]
            r_ae = conditions.r_ae
            expected_water_flux = @. FT(precip(t)) .+
               conditions.vapor_flux * (1 - f_ice) * r_ae / (r_soil + r_ae)
            @test parent(computed_water_flux) ≈ parent(expected_water_flux)
            expected_energy_flux = @. R_n +
               conditions.lhf * r_ae / (r_soil + r_ae) +
               conditions.shf
            @test parent(computed_energy_flux) ≈ parent(expected_energy_flux)
        end
    end
end
