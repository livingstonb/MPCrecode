function params = parameters_other(runopts)

    % location of baseline income process for quarterly case
    QIncome = 'input/IncomeGrids/quarterly_b.mat';
    
    %----------------------------------------------------------------------
    % EXPERIMENTS
    %----------------------------------------------------------------------

    shocks = [-0.0081, -0.00405, -0.081, 0.0081, 0.00405, 0.081];

    % Quarterly
    params = setup.Params(4,'wealth3.2',QIncome);
    params.targetAY = 3.2;
    params.lumptransfer = 0.0081 * 2.0 * 4.0;
    params.shocks = shocks;

    params(2) = setup.Params(4,'wealth0.3',QIncome);
    params(2).targetAY = 0.3;
    params(2).lumptransfer = 0.0081 * 2.0 * 4.0;
    params(2).shocks = shocks;

    ii = 3;
    for bwidth = [0.0005, 0.001, 0.0025, 0.005, 0.01, 0.02]
    	name = sprintf('beta_heterog_width%1.4f', bwidth);
    	params(ii) = setup.Params(4,name,QIncome);
    	params(ii).betawidth = bwidth;
        params(ii).nbeta = 3;
        params(ii).targetAY = 3.2;
        params(ii).lumptransfer = 0.0081 * 2.0 * 4.0;
        params(ii).shocks = shocks;
    	ii = ii + 1;
    end
    

    %----------------------------------------------------------------------
    % ADJUST TO QUARTERLY VALUES, DO NOT CHANGE
    %----------------------------------------------------------------------
    params = setup.Params.adjust_if_quarterly(params);

    %----------------------------------------------------------------------
    % CALL METHODS/CHANGE SELECTED PARAMETERS, DO NOT CHANGE
    %----------------------------------------------------------------------

    params.set_run_parameters(runopts);

    % creates ordered 'index' field
    params.set_index();
    
    % select by number if there is one, otherwise select by names,
    % otherwise use all
    if numel(runopts.number) == 1
        params = setup.Params.select_by_number(params,runopts.number);
    elseif numel(runopts.number) > 1
        error('runopts.number must have 1 or zero elements')
    else
        params = setup.Params.select_by_names(params,runopts.names_to_run);
        params.set_index(); % index within .mat file
    end
end