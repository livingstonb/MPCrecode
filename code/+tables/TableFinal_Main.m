classdef TableFinal_Main < tables.TableGen
	properties
		default_fname = '';
		included_names = {
			'Quarterly'
			'Annual'
		};
	end

	methods
		function obj = TableFinal_Main(...
			params, results, table_num, use_all)
            if nargin < 4
                use_all = false;
            end

			frequencies = [1, 4];
			obj = obj@tables.TableGen(...
				params, results, frequencies, use_all);

			obj.default_fname = sprintf(...
            	'Table%d_baselines.csv', table_num);
		end

		function output_table = create(obj, params, results)
			output_table = table();
			if isempty(obj.selected_cases)
			    return;
			end

			shocks_labels = params(1).shocks_labels;

			for ip = obj.selected_cases
				p = params(ip);
				result_structure = results(ip);

				new_column = intro_panel(result_structure, p);

				temp = panel_A_Income(result_structure, p);
				new_column = [new_column; temp];

				temp = tables.wealth_panel(result_structure);
				new_column = [new_column; temp];

				temp = tables.MPCPanels.size_effects(...
					result_structure, shocks_labels);
				new_column = [new_column; temp];

				temp = tables.MPCPanels.sign_effects(...
					result_structure, shocks_labels);
				new_column = [new_column; temp];

				column_label = sprintf('Specification%d', p.index);
				new_column.Properties.VariableNames = {column_label};
				output_table = [output_table, new_column];
			end

			obj.output = output_table;
		end
	end
end

function out = intro_panel(values, p, shocks_labels)
	out = table({p.name},...
		'VariableNames', {'results'},...
		'RowNames', {'Model'});

	new_labels = {	'Quarterly MPC (%)'
		            'Annual MPC (%)'
		            'Beta (Annualized)'
		};
	new_entries = {	round(values.direct.mpcs(5).avg_quarterly * 100, 1)
                    round(values.direct.mpcs(5).avg_annual * 100, 1)
                    round(values.direct.beta_annualized, 3) 
		};
	out = tables.TableGen.append_to_table(out,...
		new_entries, new_labels);
end

function out = panel_A_Income(values, p)
	out = tables.TableGen.new_table_with_header(...
		'Panel A: Income tables');

	new_labels = {	'Mean gross annual income'
		            'Stdev log annual gross income'
		            'Stdev log annual net income'
		};
	new_entries = {	values.direct.mean_grossy_A
                    values.direct.stdev_loggrossy_A
                    values.direct.stdev_lognety_A   
		};

	new_entries = aux.cellround(new_entries, 3);
	out = tables.TableGen.append_to_table(out,...
		new_entries, new_labels);
end