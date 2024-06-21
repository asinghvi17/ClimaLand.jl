using Test
import ClimaComms
@static pkgversion(ClimaComms) >= v"0.6" && ClimaComms.@import_required_backends
using ClimaCore
import ClimaParams
using ClimaLand
using ClimaLand.Domains: Column
using ClimaLand.Soil
using ClimaLand.Soil.Biogeochemistry
using Dates

import ClimaParams
import ClimaLand.Parameters as LP

for FT in (Float32, Float64)
    @testset "Soil respiration test set, FT = $FT" begin
        earth_param_set = LP.LandParameters(FT)
        # Make soil model args
        ν = FT(0.556)
        K_sat = FT(0.0443 / 3600 / 100) # m/s
        S_s = FT(1e-3) #inverse meters
        vg_n = FT(2.0)
        vg_α = FT(2.6) # inverse meters
        hydrology_cm = vanGenuchten{FT}(; α = vg_α, n = vg_n)
        θ_r = FT(0.1)
        ν_ss_om = FT(0.0)
        ν_ss_quartz = FT(1.0)
        ν_ss_gravel = FT(0.0)

        soil_ps = Soil.EnergyHydrologyParameters(
            FT;
            ν,
            ν_ss_om,
            ν_ss_quartz,
            ν_ss_gravel,
            K_sat,
            hydrology_cm,
            S_s,
            θ_r,
        )
        zmax = FT(0)
        zmin = FT(-1)
        nelems = 20
        lsm_domain = Column(; zlim = (zmin, zmax), nelements = nelems)
        zero_water_flux_bc = Soil.WaterFluxBC((p, t) -> 0.0)
        zero_heat_flux_bc = Soil.HeatFluxBC((p, t) -> 0.0)
        sources = ()
        boundary_fluxes = (;
            top = WaterHeatBC(;
                water = zero_water_flux_bc,
                heat = zero_heat_flux_bc,
            ),
            bottom = WaterHeatBC(;
                water = zero_water_flux_bc,
                heat = zero_heat_flux_bc,
            ),
        )
        soil_args = (;
            boundary_conditions = boundary_fluxes,
            sources = sources,
            domain = lsm_domain,
            parameters = soil_ps,
        )

        # Make biogeochemistry model args
        Csom = (z, t) -> eltype(z)(5.0)

        co2_parameters =
            Soil.Biogeochemistry.SoilCO2ModelParameters(FT; ν = 0.556)
        C = FT(4)
        co2_top_bc = Soil.Biogeochemistry.SoilCO2StateBC((p, t) -> C)
        co2_bot_bc = Soil.Biogeochemistry.SoilCO2StateBC((p, t) -> C)
        co2_sources = ()
        co2_boundary_conditions = (; top = co2_top_bc, bottom = co2_bot_bc)

        # Make a PrescribedAtmosphere - we only care about atmos_p though
        precipitation_function = (t) -> 1.0
        snow_precip = (t) -> 1.0
        atmos_T = (t) -> 1.0
        atmos_u = (t) -> 1.0
        atmos_q = (t) -> 1.0
        atmos_p = (t) -> 100000.0
        UTC_DATETIME = Dates.now()
        atmos_h = FT(30)
        atmos_co2 = (t) -> 1.0

        atmos = ClimaLand.PrescribedAtmosphere(
            TimeVaryingInput(precipitation_function),
            TimeVaryingInput(snow_precip),
            TimeVaryingInput(atmos_T),
            TimeVaryingInput(atmos_u),
            TimeVaryingInput(atmos_q),
            TimeVaryingInput(atmos_p),
            UTC_DATETIME,
            atmos_h,
            earth_param_set;
            c_co2 = TimeVaryingInput(atmos_co2),
        )

        soil_drivers = Soil.Biogeochemistry.SoilDrivers(
            Soil.Biogeochemistry.PrognosticMet{FT}(),
            Soil.Biogeochemistry.PrescribedSOC{FT}(Csom),
            atmos,
        )
        soilco2_args = (;
            boundary_conditions = co2_boundary_conditions,
            sources = co2_sources,
            domain = lsm_domain,
            parameters = co2_parameters,
            drivers = soil_drivers,
        )

        # Create integrated model instance
        model = LandSoilBiogeochemistry{FT}(;
            soil_args = soil_args,
            soilco2_args = soilco2_args,
        )
        Y, p, coords = initialize(model)
        @test propertynames(p.drivers) ==
              (:P_liq, :P_snow, :T, :P, :u, :q, :c_co2, :thermal_state)
        function init_soil!(Y, z, params)
            ν = params.ν
            FT = eltype(Y.soil.ϑ_l)
            Y.soil.ϑ_l .= FT(0.33)
            Y.soil.θ_i .= FT(0.0)
            T = FT(279.85)
            ρc_s =
                FT.(
                    Soil.volumetric_heat_capacity(
                        FT(0.33),
                        FT(0.0),
                        params.ρc_ds,
                        params.earth_param_set,
                    )
                )
            Y.soil.ρe_int .=
                Soil.volumetric_internal_energy.(
                    FT(0.0),
                    ρc_s,
                    T,
                    params.earth_param_set,
                )
        end

        function init_co2!(Y, C_0)
            Y.soilco2.C .= C_0
        end

        z = coords.subsurface.z
        init_soil!(Y, z, model.soil.parameters)
        init_co2!(Y, C)
        t0 = FT(0.0)
        set_initial_cache! = make_set_initial_cache(model)
        set_initial_cache!(p, Y, t0)

        @test p.soil.T ≈ Soil.Biogeochemistry.soil_temperature(
            model.soilco2.driver.met,
            p,
            Y,
            t0,
            z,
        )
        @test all(
            parent(
                Soil.Biogeochemistry.soil_SOM_C(
                    model.soilco2.driver.soc,
                    p,
                    Y,
                    t0,
                    z,
                ),
            ) .== FT(5.0),
        )
        @test p.soil.θ_l ≈ Soil.Biogeochemistry.soil_moisture(
            model.soilco2.driver.met,
            p,
            Y,
            t0,
            z,
        )

        try
            co2_parameters =
                Soil.Biogeochemistry.SoilCO2ModelParameters(FT; ν = 0.2)
            soil_drivers = Soil.Biogeochemistry.SoilDrivers(
                Soil.Biogeochemistry.PrognosticMet{FT}(),
                Soil.Biogeochemistry.PrescribedSOC{FT}(Csom),
                atmos,
            )
            soilco2_args = (;
                boundary_conditions = co2_boundary_conditions,
                sources = co2_sources,
                domain = lsm_domain,
                parameters = co2_parameters,
                drivers = soil_drivers,
            )

            # Create integrated model instance
            model = LandSoilBiogeochemistry{FT}(;
                soil_args = soil_args,
                soilco2_args = soilco2_args,
            )
            Y, p, coords = initialize(model)

            function init_soil_2!(Y, z, params)
                ν = params.ν
                FT = eltype(Y.soil.ϑ_l)
                Y.soil.ϑ_l .= FT(0.33)
                Y.soil.θ_i .= FT(0.0)
                T = FT(279.85)
                ρc_s = Soil.volumetric_heat_capacity(
                    FT(0.33),
                    FT(0.0),
                    params.ρc_ds,
                    params.earth_params_set,
                )
                Y.soil.ρe_int .=
                    Soil.volumetric_internal_energy.(
                        FT(0.0),
                        ρc_s,
                        T,
                        params.earth_param_set,
                    )
            end

            function init_co2_2!(Y, C_0)
                Y.soilco2.C .= C_0
            end

            z = coords.subsurface.z
            init_soil_2!(Y, z, model.soil.parameters)
            init_co2_2!(Y, C)
            t0 = FT(0.0)
            set_initial_cache! = make_set_initial_cache(model)
            set_initial_cache!(p, Y, t0)

            @test p.soil.T ≈ Soil.Biogeochemistry.soil_temperature(
                model.soilco2.driver.met,
                p,
                Y,
                t0,
                z,
            )
            soil_drivers = Soil.Biogeochemistry.SoilDrivers(
                Soil.Biogeochemistry.PrescribedMet{FT}(Csom, Csom),
                Soil.Biogeochemistry.PrescribedSOC{FT}(Csom),
                atmos,
            )
            soilco2_args = (;
                boundary_conditions = co2_boundary_conditions,
                sources = co2_sources,
                domain = lsm_domain,
                parameters = co2_parameters,
                drivers = soil_drivers,
            )

            # Create integrated model instance
            model = LandSoilBiogeochemistry{FT}(;
                soil_args = soil_args,
                soilco2_args = soilco2_args,
            )
        catch err
            @test isa(err, AssertionError)
        end
    end
end
