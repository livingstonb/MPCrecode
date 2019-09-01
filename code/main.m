function [results,decomp_meanmpc] = main(p)
    % Endogenous Grid Points with AR1 + IID Income
    % Cash on Hand as State variable
    % Includes NIT and discount factor heterogeneity
    
    % This is the main function file for this code repository. Given a
    % structure of parameters, p, this script calls functions primarily to 
    % compute policy functions via the method of endogenous grip points, 
    % and to find the implied stationary distribution over the state space.

    results = struct('direct',[],'norisk',[],'sim',[]);
    results.Finished = false;

    % throw error if more than one type of heterogeneity are added
    if (p.nbeta > 1) + (numel(p.risk_aver)>1) + (numel(p.r)>1) + (numel(p.invies)>1) > 1
        error('only one form of heterogeneity allowed')
    else
        % find a better way to do this...
        p.nb = max([p.nbeta,numel(p.risk_aver),numel(p.r),numel(p.invies)]);
    end
    
    %% --------------------------------------------------------------------
    % HETEROGENEITY IN PREFERENCES/RETURNS
    % ---------------------------------------------------------------------
    heterogeneity = setup.Prefs_R_Heterogeneity(p);
    
    %% --------------------------------------------------------------------
    % INCOME
    % ---------------------------------------------------------------------
    income = setup.Income(p,heterogeneity);

    %% --------------------------------------------------------------------
    % ASSET GRIDS
    % ---------------------------------------------------------------------
    
    % grids for method of EGP
    grdEGP = setup.Grid(p,income,'EGP');

    % grids for finding stationary distribution
    grdDST = setup.Grid(p,income,'DST');

    %% --------------------------------------------------------------------
    % MODEL SOLUTION
    % ---------------------------------------------------------------------

    if p.IterateBeta == 1
        
        mpcshock = 0;
        iterate_EGP_x = @(x) solver.iterate_EGP(x,p,grdEGP,grdDST,heterogeneity,income,mpcshock);

        if numel(heterogeneity.betadist) == 1
            beta_ub = p.betaH;
        else
            % Don't let highest beta be such that (1-dieprob)*R*beta >= 1
            beta_ub = p.betaH  - max(heterogeneity.betagrid0);
        end
        beta_lb = p.betaL;

        % output function that limits number of fzero iterations
        check_evals = @(x,y,z) aux.fzero_checkiter(x,y,z,p.maxiterAY);
        
        options = optimset('TolX',p.tolAY,'OutputFcn',check_evals);
        [beta_final,~,exitflag] = fzero(iterate_EGP_x,[beta_lb,beta_ub],options);
        if exitflag ~= 1
            return
        end
    else
        % Beta was set in parameters
        beta_final = p.beta0;    
    end
    
    % Get policy functions and stationary distribution for final beta, in
    % 'basemofdel' structure
    if p.EpsteinZin == 1
        egp_ez_solver = solver.EGP_EZ_Solver(beta_final,p,grdEGP,heterogeneity,income);
        egp_ez_solver.solve(income);
        basemodel = egp_ez_solver.return_model();
    else
        mpcshock = 0;
        basemodel = solver.solve_EGP(beta_final,p,grdEGP,heterogeneity,income,mpcshock,[]);
    end
    [~,basemodel] = solver.find_stationary_adist(p,basemodel,income,grdDST);
    results.direct.adist = basemodel.adist;

    % Report beta and annualized beta
    results.direct.beta_annualized = beta_final^p.freq;
    results.direct.beta = beta_final;
    
    if basemodel.EGP_cdiff > p.tol_iter
        % EGP did not converge for beta, escape this parameterization
        return
    end
    
    %% --------------------------------------------------------------------
    % IMPORTANT MOMENTS
    % ---------------------------------------------------------------------

    results.direct.mean_s = basemodel.xdist(:)' * basemodel.sav_x(:);
    results.direct.mean_a = basemodel.mean_a;
    results.direct.mean_x = basemodel.xdist(:)' * basemodel.xvals(:);
    results.direct.mean_c = basemodel.xdist(:)' * basemodel.con_x(:);
    
    % One-period income statistics
    results.direct.mean_grossy1 = basemodel.xdist(:)' * basemodel.y_x(:);
    results.direct.mean_loggrossy1 = basemodel.xdist(:)' * log(basemodel.y_x(:));
    results.direct.mean_nety1 = basemodel.xdist(:)' * basemodel.nety_x(:);
    results.direct.mean_lognety1 = basemodel.xdist(:)' * log(basemodel.nety_x(:));
    results.direct.var_loggrossy1 = basemodel.xdist(:)' * (log(basemodel.y_x(:)) - results.direct.mean_loggrossy1).^2;
    results.direct.var_lognety1 = basemodel.xdist(:)' * (log(basemodel.nety_x(:)) - results.direct.mean_lognety1).^2;
    
    results.direct.mean_x_check = results.direct.mean_a + results.direct.mean_nety1;

    %% --------------------------------------------------------------------
    % WEALTH DISTRIBUTION
    % ---------------------------------------------------------------------

    % Create values for fraction constrained (HtM) at every pt in asset space,
    % defining constrained as a <= epsilon * mean annual gross labor income 
    % + borrowing limit
    sort_aspace = sortrows([grdDST.a.matrix(:) basemodel.adist(:)]);
    sort_agrid = sort_aspace(:,1);
    sort_adist = sort_aspace(:,2);

    sort_acumdist = cumsum(sort_adist);

    [aunique,uind] = unique(sort_agrid,'last');
    wpinterp = griddedInterpolant(aunique,sort_acumdist(uind),'linear');
    for i = 1:numel(p.epsilon)        
        % create interpolant to find fraction of constrained households
        if p.epsilon(i) == 0
            % Get exact figure
            results.direct.constrained(i) = basemodel.adist(:)' * (grdDST.a.matrix(:)==0);

            if p.Bequests == 1
                results.direct.s0 = results.direct.constrained(i);
            else
            	c = results.direct.constrained(i);
                results.direct.s0 = (c - p.dieprob) / (1 - p.dieprob);
            end
        else
            results.direct.constrained(i) = wpinterp(p.epsilon(i)*income.meany1*p.freq);
        end
    end
    
    % Wealth percentiles
    [acumdist_unique,uniqueind] = unique(sort_acumdist,'last');
    wpinterp_inverse = griddedInterpolant(acumdist_unique,sort_agrid(uniqueind),'linear');
    results.direct.wpercentiles = wpinterp_inverse(p.percentiles/100);
    
    % Top shares
    % Amount of total assets that reside in each pt on sorted asset space
    totassets = sort_adist .* sort_agrid;
    % Fraction of total assets in each pt on asset space
    cumassets = cumsum(totassets) / results.direct.mean_a;
    
    % create interpolant from wealth percentile to cumulative wealth share
    cumwealthshare = griddedInterpolant(acumdist_unique,cumassets(uniqueind),'linear');
    results.direct.top10share  = 1 - cumwealthshare(0.9);
    results.direct.top1share   = 1 - cumwealthshare(0.99);
    
    % save adist from model
    results.direct.adist = basemodel.adist;
    results.direct.agrid_dist = sum(sum(sum(basemodel.adist,4),3),2);
    
    %% --------------------------------------------------------------------
    % EGP FOR MODEL WITHOUT INCOME RISK
    % ---------------------------------------------------------------------
    
    % Deterministic model
    norisk = solver.solve_EGP_deterministic(p,grdEGP,heterogeneity,income,results.direct);
    if norisk.EGP_cdiff > p.tol_iter
        % EGP did not converge for beta, escape this parameterization
        return
    end
    
    %% --------------------------------------------------------------------
    % SIMULATIONS
    % ---------------------------------------------------------------------
    if p.Simulate == 1
        results.sim = solver.simulate(p,income,basemodel,grdDST,heterogeneity);
    end
    
    %% --------------------------------------------------------------------
    % MPCS FOR NO-RISK MODEL
    % ---------------------------------------------------------------------
    
    results.norisk.mpcs1_a_direct = ...
        statistics.direct_MPCs_by_computation_norisk(p,norisk,income,heterogeneity,grdDST);

    %% --------------------------------------------------------------------
    % DIRECTLY COMPUTED MPCs, IMPC(s,t)
    % ---------------------------------------------------------------------
    if p.mpcshocks_after_period1 == 1
        maxT = p.freq * 4 + 1;
    else
        maxT = 1;
    end
    mpcmodels = cell(6,maxT,maxT);
    
    shocks = [-1e-5 -0.01 -0.1 1e-5 0.01 0.1];
    
    % policy functions are the same as baseline when shock is received in
    % the current period
    
    for ishock = 1:6
        
        for is = 1:maxT
            mpcmodels{ishock,is,is} = basemodel;
        end

        if p.EpsteinZin == 0
            % mpcmodels{ishock,s,t} stores the policy functions associated with the case
            % where the household is currently in period t, but recieved news about
            % the period-s shock in period 1. Shock was of size shocks(ishock)
            model_lagged = cell(6,maxT-1);

            % get consumption functions conditional on future shock
            % 'lag' is number of periods before shock
            if shocks(ishock) > 0 && (maxT > 1)
                for lag = 1:maxT-1
                    if lag == 1
                        % shock is next period
                        nextmpcshock = shocks(ishock);
                        nextmodel = basemodel;
                    else
                        % no shock next period
                        nextmpcshock = 0;
                        nextmodel = model_lagged{ishock,lag-1};
                    end

                    model_lagged{ishock,lag} = solver.solve_EGP(results.direct.beta,p,grdEGP,...
                        heterogeneity,income,nextmpcshock,nextmodel);
                end

                % populate mpcmodels with remaining (s,t) combinations for t < s
                for is = 2:maxT
                for it = is-1:-1:1
                    mpcmodels{ishock,is,it} = model_lagged{ishock,is-it};
                end
                end
            end
        end
    end

    disp('Computing MPCs')
    mpc_finder = statistics.MPCFinder(p,income,grdDST,basemodel,mpcmodels);
    mpc_finder.solve(p,grdDST);
    results.direct.mpcs = mpc_finder.mpcs;
    clear mpc_finder
    
    %% --------------------------------------------------------------------
    % MPCs via DRAWING FROM STATIONARY DISTRIBUTION AND SIMULATING
    % ---------------------------------------------------------------------
    % model with income risk
    mpc_simulator = statistics.MPCSimulator(p);
    mpc_simulator.simulate(p,income,grdDST,heterogeneity,basemodel);

    results.direct = mpc_simulator.append_results(results.direct);

    % find annual mean and standard deviations of income
    if p.freq == 4
        % direct computations
        results.direct.mean_grossy_A = results.direct.mean_grossy1 * 4;
        % from simulations
        results.direct.stdev_loggrossy_A = mpc_simulator.stdev_loggrossy_A;
        results.direct.stdev_lognety_A = mpc_simulator.stdev_lognety_A;     
    else
        % direct computations
        results.direct.mean_grossy_A = results.direct.mean_grossy1;
        results.direct.stdev_loggrossy_A = sqrt(results.direct.var_loggrossy1);
        results.direct.stdev_lognety_A = sqrt(results.direct.var_lognety1);
    end
    
    clear mpc_simulator

    %% --------------------------------------------------------------------
    % DECOMPOSITION 1 (DECOMP OF E[mpc])
    % ---------------------------------------------------------------------
    decomp_meanmpc = statistics.decomposition_of_meanmpc(p,grdDST,results);
    
    %% --------------------------------------------------------------------
    % GINI
    % ---------------------------------------------------------------------
    % Wealth
    results.direct.wealthgini = aux.direct_gini(grdDST.a.matrix,basemodel.adist);
    
    % Gross income
    results.direct.grossincgini = aux.direct_gini(income.ysort,income.ysortdist);
    
    % Net income
    results.direct.netincgini = aux.direct_gini(income.netymat,income.ymatdist);  

    results.Finished = true; 
end