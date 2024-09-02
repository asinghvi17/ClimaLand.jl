var documenterSearchIndex = {"docs":
[{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"EditURL = \"https://github.com/CliMA/ClimateMachine.jl/../../..\"","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The AbstractModel framework allows users to define land component models (e.g. for snow, soil, vegetation, carbon...) which can be run in standalone mode, or as part of a land surface model with many components. In order to achieve this flexibility, we require a standard interface, which is what AbstractModels provides. The interface is designed to work with an external package for the time-stepping of ODEs - we are using DifferentialEquations.jl at present - , with ClimaCore.jl, for the spatial discretization of PDEs, and with ClimaLSM.jl, for designing and running multi-component land surface models. For a developer of a new land model component, using AbstractModels as shown below is the first step towards building a model which can be run in standalone or with ClimaLSM.jl.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"This tutorial introduces some of the functionality of the AbstractModel interface functions and types. We demonstrate how to use a Model <: AbstractModel structure to define a set of equations, and explain a few core methods which must be defined for your Model type in order to run a simulation.  We use a non-land modelling system of ODEs for this purpose, to demonstrate generality. For land model components, you would follow the same principles - see the carbon tutorial for a similar example.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Future tutorials (TBD where) will show to define simple land component models and run them together using ClimaLSM.jl.","category":"page"},{"location":"generated/model_tutorial/#General-setup","page":"Using AbstractModel functionality","title":"General setup","text":"","category":"section"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"We assume you are solving a system of the form of a set of PDEs or ODEs. Additional algebraic equations for can be accomodated as well, but only in addition to variables advanced using differential equations.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Spatially discretized PDEs reduce to a system of ODEs, so we can assume an ODE system in what follows without a loss of generality. When using AbstractModels, you should use ClimaCore to discretize your PDE, as applicable.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Your model defines a system of equations of the following form:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"fracd vecYd t = vecf(vecY vecx t mboxparams ldots)","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The variables that are stepped forward via a differential equation are referred to as prognostic variables, and are stored in vecY. Generically, we will speak of the functions vecf as the right hand side functions; these can be functions of the prognostic state, of space vecx, and of time t, as well as of other parameters. Note that quantities such as boundary conditions, source terms, etc, will appear within these right hand side functions.","category":"page"},{"location":"generated/model_tutorial/#Optional-auxiliary-variables","page":"Using AbstractModel functionality","title":"Optional auxiliary variables","text":"","category":"section"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"It may be that there are quantities, which depend on the state vector vecY, location, time, and other parameters, which are expensive to compute (e.g. requiring solving an implicit equation) and also needed multiple times in the right hand side functions.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Denoting these variables as vecp, your equations may be rewritten as:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"fracd vecYd t = vecf(vecY vecp vecx t mboxparams ldots)","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"vecp(vecx t) = vecg(vecY(t) vecx t mboxparams ldots)","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The variables vecp at the current timestep are functions of the state, space, time, and parameters. These variables are referred to as auxiliary variables (TBD: or cache variables). Their only purpose is for storing the value of a quantity in a pre-allocated spot in memory, to avoid computing something expensive many times per time-step, or to avoid allocating memory to store each timestep. They are not a required feature, strictly speaking, and should be only used for this particular use case. A model purely consisting of algebraic equations, running in standalone mode, is not supported (vecY cannot be zero dimensional).","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"In order to define this set of equations, in a manner which is consistent with the AbstractModel interface (used by ClimaLSM.jl) and time-stepping algorithms (OrdinaryDiffEq.jl for the present), the following must be provided.","category":"page"},{"location":"generated/model_tutorial/#The-Model","page":"Using AbstractModel functionality","title":"The Model","text":"","category":"section"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"All ClimaLSM component models are concrete instances of AbstractModels. The reason for grouping them in such a way is because they all have shared required functionality, as we will see, and can make use of common default behavior.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The model structure holds all of the information needed to create the full right hand side function, including parameters (which can be functions of space and time), boundary conditions, and physical equations.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The purpose of our AbstractModel interface is that it allows you to run land component models in standalone mode and in an LSM mode without a change in interface. However, we can still use this system to show how to set up a model, equations, etc.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"As a simple demonstration of use, we'll build a model now which describes the motion of a particle in the Henon-Heiles potential. This decribes a particle moving on a plane under a cubic potential energy function, and is a problem of historical and scientific interest as an example of a system exhibiting Hamiltonian chaos. To be clear, if you only want to integrate a system like this, you should not be using our AbstractModels interface, and working with OrdinaryDiffEq.jl directly!","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Let's first import some needed packages.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"using OrdinaryDiffEq: ODEProblem, solve, RK4\nusing Plots\nusing ClimaCore\nusing DifferentialEquations\nif !(\".\" in LOAD_PATH)\n    push!(LOAD_PATH, \".\")\nend\nusing ClimaLSM\nusing ClimaLSM.Domains","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Import the functions we are extending for our model:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"import ClimaLSM: name, make_rhs, prognostic_vars\nimport ClimaLSM.Domains: coordinates","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"There is only one free parameter in the model, λ, so our model structure is very simple. Remember, the model should contain everything you need to create the right hand side function.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"struct HenonHeiles{FT} <: AbstractModel{FT}\n    λ::FT\nend;","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"For reasons we will discuss momentarily, let's also define the name of the model:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"ClimaLSM.name(model::HenonHeiles) = :hh;","category":"page"},{"location":"generated/model_tutorial/#Right-hand-side-function","page":"Using AbstractModel functionality","title":"Right hand side function","text":"","category":"section"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Here is where we need to specify the equations of motion. The prognostic variables for the Henon-Heiles system consist of two position variables (x, y), and two momentum variables (m_x, m_y, where we are using m rather than p as is typical to avoid confusion with the auxiliary vector p). The differential equations are:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"dotx = m_x","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"doty = m_y","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"dotm_x = -x -2 λ xy","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"dotm_y = -y - λ (x² - y²)","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"These equations describe Newton's 2nd law for the particle, where the force acting is minus the gradient of the potential function (the aforementioned cubic); they are derived by taking the appropriate derivatives of the Hamiltonian (in this case, total energy) function.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"We now create the function which makes the rhs! function:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"function ClimaLSM.make_rhs(model::HenonHeiles{FT}) where {FT}\n    function rhs!(dY, Y, p, t)\n        dY.hh.x[1] = Y.hh.m[1]\n        dY.hh.x[2] = Y.hh.m[2]\n        dY.hh.m[1] = -Y.hh.x[1] - FT(2) * model.λ * Y.hh.x[1] * Y.hh.x[2]\n        dY.hh.m[2] = -Y.hh.x[2] - model.λ * (Y.hh.x[1]^FT(2) - Y.hh.x[2]^FT(2))\n    end\n    return rhs!\nend;","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"A couple of notes: the vector vecdY contains the evaluation of the right hand side function for each variable in vecY. It is updated in place (so no extra allocations are needed). Note that both vectors are not simple arrays. They are ClimaCore FieldVectors, which allow us to impose some organizational structure on the state while still behaving like arrays in some ways. We use the symbol returned by name(model) to create this hierarchy. There will ever only be one level to the hierarchy.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The arguments of rhs! are determined by the OrdinaryDiffEq interface, but should be fairly generic for any time-stepping algorithm. The rhs! function is only created once. If there are time-varying forcing terms appearing, for example, the forcing functions must be stored in model and passed in that way.","category":"page"},{"location":"generated/model_tutorial/#The-state-vectors-\\vec{Y}-and-\\vec{p}","page":"Using AbstractModel functionality","title":"The state vectors vecY and vecp","text":"","category":"section"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"We have given the state vector vecY a particular structure, and don't expect the user to build this themselves. In order to have the structure Y (and p) correctly created, the model developer needs to define the names of the prognostic and auxiliary variables:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"ClimaLSM.prognostic_vars(::HenonHeiles) = (:x, :m);","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"There are no auxiliary variables. By not defining a method for them, we are using the default (which adds no variables to p), i.e. ClimaLSM.auxiliary_vars(::HenonHeiles) = ().","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Lastly, we need to tell the interface something about the variables. What are they? Arrays? ClimaCore Fields? We have made the assumption that all variables are tied to a domain, or a set of coordinates. If a variable is solved for using an n-dimensional PDE, it is defined on an n-dimensional coordinate field, and the ODE system should have a number of prognostic variables equal to the number of unique coordinate points. If the variable is solved for using an ODE system to start with, the variables are most likely still tied in a way to a coordinate system. For example, a model solving for the behavior of snow water equivalent, using a simple single-layer model, only needs an ODE for SWE. But that variable exists across the entire surface of your domain, and hence should have a 2-d coordinate field, and be defined at each point on that discretized surface domain. In this case, our coordinates are 2-d, but on a continuous domain. Hence our coordinates are given by a vector with 2 elements. This is hard to explain, which is likely an indication that we should work on our code design more :)","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"ClimaLSM.Domains.coordinates(model::HenonHeiles{FT}) where {FT} =\n    FT.([0.0, 0.0]);","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"OK, let's try running a simulation now. Create a model instance, with λ = 1:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"hh = HenonHeiles{Float64}(1.0);","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Create the initial state structure, using the default method:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Y, p, _ = initialize(hh);","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Note that Y has the structure we planned on in our rhs! function, for x,","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Y.hh.x","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"2-element Vector{Float64}:\n 0.0\n 1.6e-322","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"and for m","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Y.hh.m","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"2-element Vector{Float64}:\n 0.0\n 1.6e-322","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Note also that p is empty:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"p.hh","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Float64[]","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Here we now update Y in place with initial conditions of our choosing.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Y.hh.x[1] = 0.0;\nY.hh.x[2] = 0.0;\nY.hh.m[1] = 0.5;\nY.hh.m[2] = 0.0;","category":"page"},{"location":"generated/model_tutorial/#Running-the-simulation","page":"Using AbstractModel functionality","title":"Running the simulation","text":"","category":"section"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Create the ode_function. In our case, since we don't have any auxiliary variables to update each timestep, this is equivalent to the rhs! function, but in other models, it might involve an update_aux! step as well.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"ode_function! = make_ode_function(hh);","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"From here on out, we are just using OrdinaryDiffEq.jl functions to integrate the system forward in time.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Initial and end times, timestep:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"t0 = 0.0;\ntf = 600.0;\ndt = 1.0;","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"ODE.jl problem statement:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"prob = ODEProblem(ode_function!, Y, (t0, tf), p);","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Solve command - we are using a fourth order Runge-Kutta timestepping scheme. ODE.jl uses adaptive timestepping, but we can still pass in a suggested timestep dt.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"sol = solve(prob, RK4(); dt = dt, reltol = 1e-6, abstol = 1e-6);","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Get the solution back, and make a plot.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"x = [sol.u[k].hh.x[1] for k in 1:1:length(sol.t)]\ny = [sol.u[k].hh.x[2] for k in 1:1:length(sol.t)]\n\nplot(x, y, xlabel = \"x\", ylabel = \"y\", label = \"\");\nsavefig(\"orbits.png\");","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"(Image: )","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"And, yes, we could be using a symplectic integrator, but that would require us to use a slightly different interface - and that isn't needed for our Clima LSM application.","category":"page"},{"location":"generated/model_tutorial/#And-now-for-some-bonus-material","page":"Using AbstractModel functionality","title":"And now for some bonus material","text":"","category":"section"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The motion of the system takes place in four dimensions, but it's hard for us to visualize. One nice way of doing so is via a Poincare section, or surface of section. The idea is that for quasiperiodic motion, which Hamiltonian dynamics result in, the orbit will repeatedly meet certain criteria, and we can look at the orbit variables when that criterion is met.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"For example, we can define our surface of section to be x = 0 dotx  0, since x is varying periodically and repeatedly passes through zero in the positive direction. We also will only look at orbits with a particular energy value, E_0.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Every time the section criterion is met, we plot (y m_y). Points on this surface provide a complete description of the orbit, because we can, with knowledge of x = 0 m_x 0 and E_0, back out the state of the system, which uniquely defines the orbit we are looking at.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"The functions below creates these initial conditions, given a value for E, λ, and y (setting m_y = 0 arbitrarily):","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"function set_ic_via_y!(Y, E, λ, y; my = 0.0, x = 0.0)\n    twiceV = λ * (x^2 + y^2 + 2 * x^2 * y - 2 / 3 * y^3)\n    mx = sqrt(2.0 * E - my^2 - twiceV)\n    Y.hh.x[1] = x\n    Y.hh.x[2] = y\n    Y.hh.m[1] = mx\n    Y.hh.m[2] = my\nend;","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"This function creates similar initial conditions, but via m_y :","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"function set_ic_via_my!(Y, E, λ, my; y = 0.0, x = 0.0)\n    twiceV = λ * (x^2 + y^2 + 2 * x^2 * y - 2 / 3 * y^3)\n    mx = sqrt(2.0 * E - my^2 - twiceV)\n    Y.hh.x[1] = x\n    Y.hh.x[2] = y\n    Y.hh.m[1] = mx\n    Y.hh.m[2] = my\nend;","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"This function takes initial conditions, runs an integration, and saves the values of the state on the surface of section, and then plots those points (thanks to the SciML team for creating a tutorial showing how to extract the state of the system when the section criterion is met.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"function map(Y, pl)\n    t0 = 0.0\n    tf = 4800.0\n    dt = 1.0\n    condition(u, t, integrator) = u.hh.x[1]\n    affect!(integrator) = nothing\n    cb = ContinuousCallback(\n        condition,\n        affect!,\n        nothing,\n        save_positions = (true, false),\n    )\n    prob = ODEProblem(ode_function!, Y, (t0, tf), p)\n    sol = solve(\n        prob,\n        RK4();\n        dt = dt,\n        reltol = 1e-6,\n        abstol = 1e-6,\n        callback = cb,\n        save_everystep = false,\n        save_start = false,\n        save_end = false,\n    )\n    y_section = [sol.u[k].hh.x[2] for k in 1:1:length(sol.t)]\n    my_section = [sol.u[k].hh.m[2] for k in 1:1:length(sol.t)]\n\n    scatter!(pl, y_section, my_section, label = \"\", markersize = 3, msw = 0)\nend;","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"Ok! Let's try it out:","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"E = 0.125;\nyvals = -0.35:0.05:0.35;\npl = scatter();\nfor yval in yvals\n    set_ic_via_y!(Y, E, 1.0, yval)\n    map(Y, pl)\nend;\nmyvals = [-0.42, -0.27, 0.05, 0.27, 0.42];\nfor myval in myvals\n    set_ic_via_my!(Y, E, 1.0, myval)\n    map(Y, pl)\nend;\n\nplot(pl, xlabel = \"y\", ylabel = \"m_y\");\nsavefig(\"surface.png\");","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"(Image: )","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"On a plot like this, a single orbit (indicated via point color) can be identified roughly as regular, or periodic, if it the points lie on a curve. Orbits which are chaotic fill out an area (orbits with a lot of numerical error also do...). The coexistence of these orbits arbitrarily close to each other, in the same system, is one fascinating aspect of deterministic chaos. Another fun aspect is seeing periodic orbits of different resonances. The set of cocentric curves are near a first-order resonance, meaning that every period for x (to reach zero), we see about one period in y,my space. The teal circles around them indicate a near resonant orbit of order 4.","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"","category":"page"},{"location":"generated/model_tutorial/","page":"Using AbstractModel functionality","title":"Using AbstractModel functionality","text":"This page was generated using Literate.jl.","category":"page"},{"location":"#ClimaLSM.jl","page":"Home","title":"ClimaLSM.jl","text":"","category":"section"},{"location":"Contributing/#Contributing","page":"Contribution guide","title":"Contributing","text":"","category":"section"},{"location":"Contributing/","page":"Contribution guide","title":"Contribution guide","text":"Thank you for contributing to ClimaLSM! We encourage Pull Requests (PRs). Please do not hesitate to ask questions.","category":"page"},{"location":"Contributing/#Some-useful-tips","page":"Contribution guide","title":"Some useful tips","text":"","category":"section"},{"location":"Contributing/","page":"Contribution guide","title":"Contribution guide","text":"When you start working on a new feature branch, make sure you start from master by running: git checkout master.\nMake sure you add tests for your code in test/ and appropriate documentation in the code and/or in docs/. All exported functions and structs must be documented.\nWhen your PR is ready for review, clean up your commit history by squashing and make sure your code is current with ClimateMachine master by rebasing.","category":"page"},{"location":"Contributing/#Continuous-integration","page":"Contribution guide","title":"Continuous integration","text":"","category":"section"},{"location":"Contributing/","page":"Contribution guide","title":"Contribution guide","text":"After rebasing your branch, you can ask for review. Fill out the template and provide a clear summary of what your PR does. When a PR is created or updated, a set of automated tests are run on the PR in our continuous integration (CI) system.","category":"page"},{"location":"Contributing/#Automated-testing","page":"Contribution guide","title":"Automated testing","text":"","category":"section"},{"location":"Contributing/","page":"Contribution guide","title":"Contribution guide","text":"Currently a number of checks are run per commit for a given PR.","category":"page"},{"location":"Contributing/","page":"Contribution guide","title":"Contribution guide","text":"JuliaFormatter checks if the PR is formatted with .dev/climaformat.jl.\nDocumentation rebuilds the documentation for the PR and checks if the docs are consistent and generate valid output.\nTests runs the file test/runtests.jl,  using Pkg.test(). These are a mix of unit tests and fast integration tests.","category":"page"},{"location":"Contributing/","page":"Contribution guide","title":"Contribution guide","text":"We use bors to manage merging PR's in the the ClimaLSM repo. If you're a collaborator and have the necessary permissions, you can type bors try in a comment on a PR to have integration test suite run on that PR, or bors r+ to try and merge the code.  Bors ensures that all integration tests for a given PR always pass before merging into master.","category":"page"}]
}
